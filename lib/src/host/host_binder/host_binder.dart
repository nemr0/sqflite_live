import 'dart:developer';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:sqflite_live/src/host/file_manager/file_manager.dart';
import 'package:sqflite_live/src/host/host_binder/host_parameters.dart';
import 'package:shelf/shelf_io.dart'    as shelf_io;
import 'package:shelf_static/shelf_static.dart';

import '../../exceptions/server_failure.dart';
class HostBinder{
  final HostParameters hostParameters;
  HttpServer? server;
  final FileManager fileManager;
  HostBinder(this.hostParameters, this.fileManager);
  host(String hostDir) async {
   try {
      // Serve everything under assets/web/ (make sure you've
      // declared that folder in your pubspec under flutter.assets)
      final staticHandler = createStaticHandler(
        hostDir,
        defaultDocument: 'index.html',
      );

      final handler = Pipeline().addMiddleware(logRequests()).addHandler(staticHandler);

      server = await shelf_io.serve(
          handler, InternetAddress.anyIPv4, hostParameters.port);
      print('🗂️  Static server running at http://${server?.address.address}:${hostParameters.port}/index.html?url=${fileManager.dbName}.db/');
    }catch(e,s){
     log('e: $e,$s');
     throw(ServerFailure(e.toString(),stackTrace: s));
   }
  }
  flush(){

  }
}