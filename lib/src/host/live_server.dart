
import 'package:sqflite_live/src/host/file_manager/file_manager.dart';
import 'package:sqflite_live/src/host/host_binder/host_parameters.dart';
import 'package:sqflite_live/src/host/host_binder/host_binder.dart';
import 'package:sqflite_live/src/host/logger/log_me.dart';


class LiveServer{
  final FileManager fileManager;
  final HostBinder hostBinder;
  final HostParameters hostParameters;
  final LogMe logMe;
  LiveServer(this.fileManager,  this.hostBinder, this.hostParameters, this.logMe);
  Future<void> run([void data]) async {
  final hostDir = await fileManager.prepareFiles(hostParameters.dbPath);
  print('hostPath: ${hostDir.path}');
  print('hostPath: ${hostDir.listSync()}');
  await hostBinder.host(hostDir.path);
  }

  Future<void> flush() async {
  await fileManager.flushCache();
  }
}