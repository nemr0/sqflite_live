import 'dart:convert';
import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart';
import 'package:sqflite_live/src/exceptions/file_failure.dart';
import 'package:sqflite_live/src/host/db_executor.dart';
import 'package:sqflite_live/src/host/host_binder/host_binder.dart';
import 'package:sqflite_live/src/host/host_binder/host_parameters.dart';
import 'package:sqflite_live/src/host/logger/log_me.dart';

import '../../exceptions/server_failure.dart';
class IHostBinder extends HostBinder{
  final HostParameters _hostParameters;
  final LogMe _logMe;
  /// Runs SQL sent by the viewer against the live database. When null, the
  /// `POST /exec` endpoint is disabled.
  final DbExecutor? _executor;
  IHostBinder(this._hostParameters,  this._logMe, [this._executor]);
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

      // shared: true lets a fresh bind coexist with a socket leaked by a
      // previous hot restart (whose Dart state was reset before closeServer
      // ran), instead of throwing "address already in use" — which would skip
      // the URL log below.
      server = await HttpServer.bind(InternetAddress.anyIPv4, _hostParameters.port,
          shared: true);
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
      final bool isQuery = head.startsWith('SELECT') ||
          head.startsWith('PRAGMA') ||
          head.startsWith('EXPLAIN') ||
          head.startsWith('WITH');
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
      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  @override
  Future<void> logAddress() async {
    final List<String> ips = await _getLocalIpAddresses();
    final int port = _hostParameters.port;
    final String primary = ips.isEmpty ? 'localhost' : ips.first;
    _logMe.info('🗂️ SQFLITE Server @ http://$primary:$port');
    if (ips.length > 1) {
      final others =
          ips.skip(1).map((ip) => 'http://$ip:$port').join('  •  ');
      _logMe.info('   if unreachable, try: $others');
    }
  }

  @override
  Future<void> closeServer() async {
    // force: true drops open connections immediately so a restart can't hang
    // waiting on a browser keep-alive socket.
    await server?.close(force: true);
    server = null;
  }

  @override
  Future<bool> isAlive() async {
    if (server == null) return false;
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
      final HttpClientRequest request =
          await client.get('127.0.0.1', _hostParameters.port, '/');
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