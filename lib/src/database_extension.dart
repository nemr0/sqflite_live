
import 'package:logger/logger.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_live/src/host/file_manager/file_manager.dart';
import 'package:sqflite_live/src/host/file_manager/file_manager_impl.dart';
import 'package:sqflite_live/src/host/host_binder/host_binder_impl.dart';
import 'package:sqflite_live/src/host/live_server.dart';
import 'package:sqflite_live/src/host/logger/log_me_impl.dart';

import 'host/host_binder/host_parameters.dart';
/// Provides an extension on the [Database] class to start
/// a live server for debugging and logging purposes.
///
/// The extension adds a [live] method to [Database] allowing
/// the server to be started, logging errors if they occur and
/// performing necessary cleanup after execution.
extension SqlfliteExtension on Database {

  /// Runs the live server when [enabled] is true.
  ///
  ///
  /// Parameters:
  /// - [enabled]: Flag to determine if the live server should start. Defaults to true.
  /// - [level]: The logging level used to initialize the logger. Defaults to [Level.warning].
  /// - [port]: Port number on which the live server should run. Defaults to 8081.

  Future<void> live({bool enabled = true,Level level = Level.warning,int port = 8081}) async {
    if(enabled == false) return;
    final logger = ILogMe(level);
    final path = await getDatabasesPath();
    LiveServer liveServer;
    final hostParameter = HostParameters(dbPath: path, port: port);
    final FileManager fileManager = IFileManager();
    liveServer = LiveServer(
        fileManager , IHostBinder(hostParameter,fileManager,logger), hostParameter,logger);
    liveServer.run();

  }
}
