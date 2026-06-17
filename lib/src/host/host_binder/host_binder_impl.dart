import 'dart:convert';
import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart';
import 'package:sqflite_live/src/exceptions/file_failure.dart';
import 'package:sqflite_live/src/host/db_executor.dart';
import 'package:sqflite_live/src/host/host_binder/host_binder.dart';
import 'package:sqflite_live/src/host/host_binder/host_parameters.dart';
import 'package:sqflite_live/src/host/logger/log_me.dart';
import 'package:sqflite_live/src/host/mdns/mdns_responder.dart';
import 'package:sqflite_live/src/host/mdns/mdns_responder_impl.dart';

import '../../exceptions/server_failure.dart';
class IHostBinder extends HostBinder{
  final HostParameters _hostParameters;
  final LogMe _logMe;
  /// Runs SQL sent by the viewer against the live database. When null, the
  /// `POST /exec` endpoint is disabled.
  final DbExecutor? _executor;
  IHostBinder(this._hostParameters,  this._logMe, [this._executor]);
  HttpServer? server;
  /// Publishes the `*.local` name over mDNS while the server is up. Null when
  /// the feature is disabled (empty hostname) or not yet started.
  MdnsResponder? _mdns;

  /// Safe, unprivileged port used when the requested one can't be bound.
  static const int _fallbackPort = 8081;

  /// The port the server actually bound to. May differ from the requested
  /// [HostParameters.port] if it fell back (e.g. port 80 on a platform that
  /// disallows binding privileged ports).
  int? _boundPort;
  int get _port => _boundPort ?? _hostParameters.port;
  /// Returns all non-loopback IPv4 addresses, most-likely-reachable first.
  ///
  /// WiFi/Ethernet (`en*`, `eth*`) addresses are preferred. Interfaces that
  /// other devices on the same WiFi usually can't route to — VPN tunnels
  /// (`utun`, `ipsec`, `ppp`), cellular (`pdp_ip`) and Apple Wireless Direct
  /// (`awdl`) — are pushed to the back, so the advertised URL is one a browser
  /// on the same network can actually open. Without this, an iPhone with a VPN
  /// or cellular up may advertise an unreachable address and connections time
  /// out.
  Future<List<String>> _getLocalIpAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );

    bool isLikelyUnreachable(String name) =>
        name.startsWith('utun') ||
        name.startsWith('ipsec') ||
        name.startsWith('ppp') ||
        name.startsWith('pdp_ip') ||
        name.startsWith('awdl');

    final preferred = <String>[];
    final fallback = <String>[];
    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        (isLikelyUnreachable(interface.name) ? fallback : preferred)
            .add(addr.address);
      }
    }
    return [...preferred, ...fallback];
  }

  /// Binds the HTTP server, falling back to [_fallbackPort] when a privileged
  /// port (<1024, e.g. 80 for a clean `http://sqflite.local` URL) can't be
  /// bound — which is the norm on Android and on desktop without admin rights.
  ///
  /// shared: true lets a fresh bind coexist with a socket leaked by a previous
  /// hot restart (whose Dart state was reset before closeServer ran), instead
  /// of throwing "address already in use".
  Future<HttpServer> _bind(int port) async {
    try {
      final HttpServer s = await HttpServer.bind(InternetAddress.anyIPv4, port,
          shared: true);
      _boundPort = port;
      return s;
    } on SocketException catch (e) {
      if (port < 1024 && port != _fallbackPort) {
        _logMe.warning(
            'Could not bind port $port ($e) — this platform likely forbids '
            'privileged ports. Falling back to $_fallbackPort; the URL will '
            'include :$_fallbackPort.');
        return _bind(_fallbackPort);
      }
      rethrow;
    }
  }

  @override
  Future<void> startServer(String hostDirectory) async {
    try {

      final Directory directory = Directory(hostDirectory);
      if (!directory.existsSync()) {
        throw(FileFailure('Host Directory Doesn\'t Exist!'));
      }

      server = await _bind(_hostParameters.port);
      await _startLocalDomain();
      await logAddress();
      await for (HttpRequest request in server!) {
        if (request.method == 'POST' && request.uri.path == '/exec') {
          await _handleExec(request);
          continue;
        }
        if (request.method == 'GET' && request.uri.path == '/db-version') {
          await _handleDbVersion(request, hostDirectory);
          continue;
        }
        final String uriPath = (request.uri.path == '/' ? '/index.html' : request.uri.path).replaceFirst('/', '');
        final String filePath = join(hostDirectory, uriPath);
        // The viewer reads the main db file, but sqflite buffers writes in the
        // WAL sidecar. Checkpoint on each db fetch so app-side writes made since
        // the last fetch are flushed into the file the browser is about to read.
        if (uriPath == 'cached.db') {
          try {
            await _executor?.checkpoint();
          } catch (e) {
            _logMe.warning('wal checkpoint failed before serving db: $e');
          }
        }
        final File file = File(filePath);
        if ( file.existsSync()) {
          request.response.statusCode = HttpStatus.ok;
          final String mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';

          // Set content type header; you might want to add MIME type detection here
          request.response.headers.set(HttpHeaders.contentTypeHeader, mimeType);
          await request.response.addStream(file.openRead());
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('File not found: $filePath');
        }
        await request.response.close();
      }

    } catch (e, s) {
      throw ServerFailure(e.toString(), stackTrace: s);
    }
  }
  /// Handles `POST /exec`: runs the request body as SQL against the live
  /// database and replies with JSON — `{"rows": [...]}` for row-returning
  /// statements, `{"rowsAffected": n}` for mutations, or `{"error": "..."}`.
  Future<void> _handleExec(HttpRequest request) async {
    request.response.headers
        .set(HttpHeaders.contentTypeHeader, 'application/json');
    try {
      final DbExecutor? executor = _executor;
      if (executor == null) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.write('{"error":"writes are disabled"}');
        return;
      }
      final String sql = (await utf8.decoder.bind(request).join()).trim();
      if (sql.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('{"error":"empty SQL"}');
        return;
      }
      final String head = sql.trimLeft().toUpperCase();
      // A WITH (CTE) prefix can front either a query or a mutation
      // (`WITH x AS (...) INSERT/UPDATE/DELETE ...`), so peek past it for a
      // mutation keyword instead of assuming it's read-only.
      final bool isQuery;
      if (head.startsWith('WITH')) {
        isQuery = !RegExp(r'\b(INSERT|UPDATE|DELETE|REPLACE)\b').hasMatch(head);
      } else {
        isQuery = head.startsWith('SELECT') ||
            head.startsWith('PRAGMA') ||
            head.startsWith('EXPLAIN');
      }
      final Object payload;
      if (isQuery) {
        payload = {'rows': await executor.query(sql)};
      } else {
        final int affected = await executor.execute(sql);
        _logMe.data('🖊️ exec: $affected row(s) affected — $sql');
        payload = {'rowsAffected': affected};
      }
      request.response.statusCode = HttpStatus.ok;
      // Stringify anything not natively JSON-encodable (e.g. BLOB bytes).
      request.response.write(jsonEncode(payload, toEncodable: (o) => o.toString()));
    } catch (e) {
      _logMe.error('exec failed: $e');
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  /// Handles `GET /db-version`: checkpoints the WAL, then replies with a cheap
  /// signature of the database file (`{"size": n, "modified": ms}`) the viewer
  /// can poll. When the signature changes the viewer re-fetches `cached.db`.
  Future<void> _handleDbVersion(
      HttpRequest request, String hostDirectory) async {
    request.response.headers
        .set(HttpHeaders.contentTypeHeader, 'application/json');
    try {
      // Flush pending writes so size/mtime reflect the latest committed data.
      await _executor?.checkpoint();
      final File db = File(join(hostDirectory, 'cached.db'));
      final FileStat stat = await db.stat();
      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({
        'size': stat.size,
        'modified': stat.modified.millisecondsSinceEpoch,
      }));
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  /// Brings up the mDNS responder so the server answers to its `*.local`
  /// name. Skipped when [HostParameters.localHostname] is empty.
  Future<void> _startLocalDomain() async {
    final String host = _hostParameters.localHostname;
    if (host.isEmpty) return;
    _mdns ??= IMdnsResponder(
      hostname: host,
      resolveAddress: () async {
        final ips = await _getLocalIpAddresses();
        return ips.isEmpty ? null : ips.first;
      },
      logMe: _logMe,
    );
    await _mdns!.start();
  }

  /// Builds an `http://` URL for [hostOrIp], omitting the `:80` suffix so the
  /// default HTTP port produces a clean address (`http://sqflite.local`).
  String _url(String hostOrIp) =>
      _port == 80 ? 'http://$hostOrIp' : 'http://$hostOrIp:$_port';

  @override
  Future<void> logAddress() async {
    final List<String> ips = await _getLocalIpAddresses();
    final String primary = ips.isEmpty ? 'localhost' : ips.first;
    final String host = _hostParameters.localHostname;
    if (host.isNotEmpty) {
      _logMe.info('🗂️ SQFLITE Server @ ${_url(host)}');
      _logMe.info('   or by IP: ${_url(primary)}');
    } else {
      _logMe.info('🗂️ SQFLITE Server @ ${_url(primary)}');
    }
    if (ips.length > 1) {
      final others = ips.skip(1).map(_url).join('  •  ');
      _logMe.info('   if unreachable, try: $others');
    }
    // The IP may have changed since the last bind (e.g. across a resume), so
    // refresh the mDNS record while we're re-announcing the address.
    await _mdns?.announce();
  }

  @override
  Future<void> closeServer() async {
    await _mdns?.stop();
    _mdns = null;
    // force: true drops open connections immediately so a restart can't hang
    // waiting on a browser keep-alive socket.
    await server?.close(force: true);
    server = null;
    _boundPort = null;
  }

  @override
  Future<bool> isAlive() async {
    if (server == null) return false;
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
      final HttpClientRequest request =
          await client.get('127.0.0.1', _port, '/');
      final HttpClientResponse response =
          await request.close().timeout(const Duration(seconds: 2));
      await response.drain<void>();
      return true;
    } catch (_) {
      // Connection refused / timed out / reset => the socket didn't survive.
      return false;
    } finally {
      client?.close(force: true);
    }
  }
}