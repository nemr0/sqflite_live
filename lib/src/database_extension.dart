
import 'package:logger/logger.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_live/src/host/file_manager/file_manager.dart';
import 'package:sqflite_live/src/host/file_manager/file_manager_impl.dart';
import 'package:sqflite_live/src/host/host_binder/host_binder_impl.dart';
import 'package:sqflite_live/src/host/live_server.dart';
import 'package:sqflite_live/src/host/logger/log_me_impl.dart';

import 'host/host_binder/host_parameters.dart';

extension SqlfliteExtension on Database {
  Future<void> live({Level level = Level.warning,int port = 8081}) async {
    final logger = ILogMe(level);
    final path = await getDatabasesPath();
    final hostParameter = HostParameters(dbPath: path, port: 8081);
    final FileManager fileManager = IFileManager();
    LiveServer liveServer = LiveServer(
        fileManager , IHostBinder(hostParameter,fileManager,logger), hostParameter);
    try {
      await liveServer.run();
    } catch (e, s) {
      logger.error(e, trace: s);
    } finally {
      await liveServer.flush();
    }
  }
}
