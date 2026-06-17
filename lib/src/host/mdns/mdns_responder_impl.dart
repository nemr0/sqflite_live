import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite_live/src/host/logger/log_me.dart';
import 'package:sqflite_live/src/host/mdns/mdns_responder.dart';

/// A minimal mDNS responder that publishes a single `*.local` A record.
///
/// Dart's `multicast_dns` package can only *query* the network; to make a name
/// resolvable the host has to *answer* queries, which this does directly over
/// UDP. It binds the standard mDNS group (`224.0.0.251:5353`), replies to A /
/// ANY questions for [hostname], and — because some client platforms filter
/// inbound multicast (notably Android without a `MulticastLock`) — also pushes
/// periodic unsolicited announcements so resolvers can cache the record from a
/// packet they merely *receive* rather than one they had to solicit.
class IMdnsResponder extends MdnsResponder {
  IMdnsResponder({
    required String hostname,
    required Future<String?> Function() resolveAddress,
    required LogMe logMe,
  })  : _hostname = hostname.toLowerCase(),
        _resolveAddress = resolveAddress,
        _logMe = logMe;

  /// The IPv4 link-local multicast group reserved for mDNS.
  static final InternetAddress _group = InternetAddress('224.0.0.251');
  static const int _port = 5353;

  /// Record TTL advertised to resolvers, in seconds.
  static const int _ttl = 120;

  /// Re-announce comfortably before [_ttl] expires so cached records never
  /// lapse between announcements.
  static const Duration _announceInterval = Duration(seconds: 100);

  final String _hostname;
  final Future<String?> Function() _resolveAddress;
  final LogMe _logMe;

  RawDatagramSocket? _socket;
  Timer? _announceTimer;

  @override
  Future<void> start() async {
    if (_socket != null) return;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _port,
        // The OS mDNSResponder (macOS/iOS) already holds :5353; reuse so our
        // bind coexists with it instead of throwing "address already in use".
        reuseAddress: true,
        reusePort: true,
      )
        ..multicastHops = 255; // mDNS convention: TTL 255.

      try {
        socket.joinMulticast(_group);
      } catch (_) {
        // Some platforms won't join on the default interface; try each one.
        for (final ni in await NetworkInterface.list(
            type: InternetAddressType.IPv4, includeLoopback: false)) {
          try {
            socket.joinMulticast(_group, ni);
          } catch (_) {
            // Best effort — a single unjoinable interface isn't fatal.
          }
        }
      }

      _socket = socket;
      socket.listen(_onEvent);

      // Initial announcement burst (fire-and-forget) so resolvers learn the
      // name immediately, then keep it fresh on a timer.
      unawaited(_announceBurst());
      _announceTimer =
          Timer.periodic(_announceInterval, (_) => unawaited(announce()));
    } catch (e) {
      // Name resolution is a convenience on top of the IP URL — never let it
      // take the server down.
      _logMe.warning(
          'Local name "$_hostname" unavailable ($e); use the IP URL instead.');
    }
  }

  @override
  Future<void> announce() async {
    final socket = _socket;
    if (socket == null) return;
    final packet = await _buildAnswer();
    if (packet == null) return;
    try {
      socket.send(packet, _group, _port);
    } catch (e) {
      _logMe.warning('mDNS announce failed: $e');
    }
  }

  @override
  Future<void> stop() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    try {
      _socket?.leaveMulticast(_group);
    } catch (_) {
      // Already gone / never joined — nothing to clean up.
    }
    _socket?.close();
    _socket = null;
  }

  /// Sends a few announcements one second apart, mirroring how a fresh mDNS
  /// host announces a newly claimed name.
  Future<void> _announceBurst() async {
    for (var i = 0; i < 3 && _socket != null; i++) {
      await announce();
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null) return;
    if (_isQueryForUs(datagram.data)) {
      unawaited(announce());
    }
  }

  /// Returns whether [data] is an mDNS *query* asking for our hostname's A (or
  /// ANY) record. Responses and unrelated questions are ignored.
  bool _isQueryForUs(Uint8List data) {
    if (data.length < 12) return false;
    final header = ByteData.sublistView(data);
    // High bit of the flags word is QR: 0 = query, 1 = response.
    if ((header.getUint16(2) & 0x8000) != 0) return false;
    final questionCount = header.getUint16(4);

    var offset = 12;
    for (var i = 0; i < questionCount; i++) {
      final parsed = _readName(data, offset);
      if (parsed == null) return false;
      offset = parsed.offset;
      if (offset + 4 > data.length) return false;
      final qtype = header.getUint16(offset);
      offset += 4; // qtype (2) + qclass (2)
      const aRecord = 1;
      const anyRecord = 255;
      if ((qtype == aRecord || qtype == anyRecord) &&
          parsed.name.toLowerCase() == _hostname) {
        return true;
      }
    }
    return false;
  }

  /// Builds an mDNS response advertising `hostname -> currentIPv4`, or null if
  /// no usable IPv4 address is available.
  Future<Uint8List?> _buildAnswer() async {
    final ip = await _resolveAddress();
    if (ip == null) return null;
    final addr = InternetAddress.tryParse(ip);
    if (addr == null || addr.type != InternetAddressType.IPv4) return null;

    final builder = BytesBuilder();

    final header = ByteData(12);
    header.setUint16(2, 0x8400); // QR = response, AA = authoritative.
    header.setUint16(6, 1); // ANCOUNT = 1 answer.
    builder.add(header.buffer.asUint8List());

    builder.add(_encodeName(_hostname));

    final record = ByteData(10);
    record.setUint16(0, 1); // TYPE = A.
    record.setUint16(2, 0x8001); // CLASS = IN, with the cache-flush bit set.
    record.setUint32(4, _ttl);
    record.setUint16(8, 4); // RDLENGTH = 4 (one IPv4 address).
    builder.add(record.buffer.asUint8List());
    builder.add(addr.rawAddress);

    return builder.toBytes();
  }

  /// Encodes a dotted name as a sequence of length-prefixed labels terminated
  /// by a zero byte (DNS wire format).
  Uint8List _encodeName(String name) {
    final out = BytesBuilder();
    for (final label in name.split('.')) {
      final bytes = utf8.encode(label);
      out.addByte(bytes.length);
      out.add(bytes);
    }
    out.addByte(0);
    return out.toBytes();
  }

  /// Reads a DNS name starting at [offset], following compression pointers.
  /// Returns the decoded name and the offset of the byte *after* the name in
  /// the original record stream, or null if the encoding is malformed.
  _ParsedName? _readName(Uint8List data, int offset) {
    final labels = <String>[];
    var cursor = offset;
    int? resumeOffset;
    var guard = 0;

    while (true) {
      if (guard++ > 128 || cursor >= data.length) return null;
      final length = data[cursor];
      if (length == 0) {
        cursor += 1;
        break;
      }
      if ((length & 0xC0) == 0xC0) {
        // Compression pointer: top two bits set, next 14 bits are the offset.
        if (cursor + 1 >= data.length) return null;
        final pointer = ((length & 0x3F) << 8) | data[cursor + 1];
        resumeOffset ??= cursor + 2;
        cursor = pointer;
        continue;
      }
      cursor += 1;
      if (cursor + length > data.length) return null;
      labels.add(utf8.decode(data.sublist(cursor, cursor + length)));
      cursor += length;
    }

    return _ParsedName(labels.join('.'), resumeOffset ?? cursor);
  }
}

/// A decoded DNS name plus the offset to continue parsing from.
class _ParsedName {
  _ParsedName(this.name, this.offset);

  final String name;
  final int offset;
}
