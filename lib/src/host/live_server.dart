import 'package:sqflite_live/src/exceptions/failure_abs.dart';
import 'package:sqflite_live/src/host/file_manager/file_manager.dart';
import 'package:sqflite_live/src/host/host_binder/host_binder.dart';
import 'package:sqflite_live/src/host/host_binder/host_parameters.dart';
import 'package:sqflite_live/src/host/logger/log_me.dart';

/// Manages the live server by coordinating file preparation, starting the HTTP server,
/// and flushing resources when required.
class LiveServer {
  final FileManager _fileManager;
  final HostBinder _hostBinder;
  final HostParameters _hostParameters;
  final LogMe _logMe;
  /// Creates a [LiveServer] with the provided file manager, host binder, and host parameters.
  const LiveServer(
      this._fileManager, this._hostBinder, this._hostParameters, this._logMe);

  /// Prepares the necessary files, starts the HTTP server, and flushes resources.
  ///
  /// The optional parameter [data] can be used for additional runtime information.
  Future<void> run([void data]) async {
    try{
      final hostDir = await _fileManager.prepareFiles(_hostParameters.dbPath);
      await _hostBinder.startServer(hostDir.path);
    }on Failure catch(e){
      _logMe.error(e.message,trace: e.stackTrace);
    }catch(e,s){
      if(e is! Failure){
        _logMe.error(e.toString(),trace: s);
      }
    }
    finally{
     await flush();
    }
  }

  /// Flushes the server and file cache.
  ///
  /// This closes the HTTP server and flushes any cached files in the file manager.
  Future<void> flush() async {
    await _hostBinder.closeServer();
    await _fileManager.flush();
  }
}