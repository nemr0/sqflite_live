import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart';
import 'package:sqflite_live/src/exceptions/file_failure.dart';
import 'package:sqflite_live/src/host/file_manager/file_manager.dart';
import 'package:sqflite_live/src/host/host_binder/host_binder.dart';
import 'package:sqflite_live/src/host/host_binder/host_parameters.dart';
import 'package:sqflite_live/src/host/logger/log_me.dart';

import '../../exceptions/server_failure.dart';
class IHostBinder extends HostBinder{
  final HostParameters _hostParameters;
  final FileManager _fileManager;
  final LogMe _logMe;
  IHostBinder(this._hostParameters, this._fileManager, this._logMe);
  HttpServer? server;
  Future<String> _getLocalIpAddress() async {
    // List IPv4 network interfaces, excluding loopback.
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    // Choose the first address available, or return a default value.
    if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
      return interfaces.first.addresses.first.address;
    }
    return 'localhost';
  }
  @override
  Future<void> startServer(String hostDirectory) async {
    try {

      final Directory directory = Directory(hostDirectory);
      if (!directory.existsSync()) {
        throw(FileFailure('Host Directory Doesn\'t Exist!'));
      }

      server = await HttpServer.bind(InternetAddress.anyIPv4, _hostParameters.port);
      String ip =await _getLocalIpAddress();
      _logMe.info('🗂️ SQFLITE Server @ http://$ip:${_hostParameters.port}');
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