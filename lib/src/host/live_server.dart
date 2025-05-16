
import 'package:sqflite_live/src/host/file_manager/file_manager.dart';
import 'package:sqflite_live/src/host/host_binder/host_parameters.dart';

import 'host_binder/host_binder.dart';


class LiveServer{
  final FileManager _fileManager;
  final HostBinder _hostBinder;
  final HostParameters _hostParameters;
  const LiveServer(this._fileManager,  this._hostBinder, this._hostParameters);
  Future<void> run([void data]) async {
  final hostDir = await _fileManager.prepareFiles(_hostParameters.dbPath);
  await _hostBinder.startServer(hostDir.path);
  await flush();
  }

  Future<void> flush() async {
    await _hostBinder.closeServer();
  await _fileManager.flushCache();

  }
}