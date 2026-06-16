

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_live/src/host/db_executor.dart';
import 'package:sqflite_live/src/host/file_manager/file_manager.dart';
import 'package:sqflite_live/src/host/file_manager/file_manager_impl.dart';
import 'package:sqflite_live/src/host/host_binder/host_binder_impl.dart';
import 'package:sqflite_live/src/host/live_server.dart';
import 'package:sqflite_live/src/host/logger/log_me.dart';
import 'package:sqflite_live/src/host/logger/log_me_impl.dart';
import 'package:sqflite_live/src/host/sqflite_live.dart';

import 'host/host_binder/host_parameters.dart';
import 'is_supported_platform.dart';
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
  /// - [level]: The logging level used to initialize the logger. Defaults to [LogLevel.info].
  /// - [port]: Port number on which the live server should run. Defaults to 8081.
  /// - [autoRestart]: When true (default), the server is automatically stopped
  ///   when the app is backgrounded and restarted when it returns to the
  ///   foreground.
  ///
  /// Returns a [SqfliteLive] handle you can use to [SqfliteLive.stop],
  /// [SqfliteLive.start] or [SqfliteLive.dispose] the server, or `null` when
  /// [enabled] is false or the platform is unsupported.

  Future<SqfliteLive?> live({bool enabled = kDebugMode,LogLevel level = LogLevel.info,int port = 8081,bool autoRestart = true}) async {
    if(enabled == false || isSupportedPlatform()==false) return null;
    final logger = ILogMe(level);
    final path = await getDatabasesPath();
    final hostParameter = HostParameters(dbPath: path, port: port);
    final FileManager fileManager = IFileManager();
    // `this` is the live connection, so SQL from the viewer runs on the same
    // database the app uses.
    final DbExecutor executor = SqfliteExecutor(this);
    final liveServer = LiveServer(
        fileManager , IHostBinder(hostParameter,logger,executor), hostParameter,logger);
    final live = SqfliteLive(liveServer, autoRestart: autoRestart);
    await live.start();
    return live;
  }
}
