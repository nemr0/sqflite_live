import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart';
import 'package:sqflite_live/src/exceptions/file_failure.dart';
import 'package:sqflite_live/src/host/host_binder/host_binder.dart';
import 'package:sqflite_live/src/host/host_binder/host_parameters.dart';
import 'package:sqflite_live/src/host/logger/log_me.dart';

import '../../exceptions/server_failure.dart';
class IHostBinder extends HostBinder{
  final HostParameters _hostParameters;
  final LogMe _logMe;
  IHostBinder(this._hostParameters,  this._logMe);
  HttpServer? server;
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
  @override
  Future<void> startServer(String hostDirectory) async {
    try {

      final Directory directory = Directory(hostDirectory);
      if (!directory.existsSync()) {
        throw(FileFailure('Host Directory Doesn\'t Exist!'));
      }

      server = await HttpServer.bind(InternetAddress.anyIPv4, _hostParameters.port);
      final List<String> ips = await _getLocalIpAddresses();
      final int port = _hostParameters.port;
      final String primary = ips.isEmpty ? 'localhost' : ips.first;
      _logMe.info('🗂️ SQFLITE Server @ http://$primary:$port');
      if (ips.length > 1) {
        final others =
            ips.skip(1).map((ip) => 'http://$ip:$port').join('  •  ');
        _logMe.info('   if unreachable, try: $others');
      }
      await for (HttpRequest request in server!) {
        final String uriPath = (request.uri.path == '/' ? '/index.html' : request.uri.path).replaceFirst('/', '');
        final String filePath = join(hostDirectory, uriPath);
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
  @override
  Future<void> closeServer() async {
    await server?.close();
  }
}