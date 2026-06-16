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
  LiveServer(
      this._fileManager, this._hostBinder, this._hostParameters, this._logMe);

  bool _isRunning = false;

  /// Whether the HTTP server is currently bound and serving requests.
  bool get isRunning => _isRunning;

  /// Whether the server actually responds to a request right now.
  ///
  /// Stronger than [isRunning]: after the OS suspends a backgrounded app the
  /// request loop may still appear running while its socket is dead, so this
  /// performs a real loopback request.
  Future<bool> isHealthy() => _hostBinder.isAlive();

  /// Re-logs the URL(s) the server is reachable at (e.g. on app resume).
  Future<void> announce() => _hostBinder.logAddress();

  /// Prepares the necessary files and starts the HTTP server.
  ///
  /// The returned future does not complete until the server is closed (via
  /// [flush]), since it awaits the request loop. On failure the resources are
  /// flushed automatically; on a clean stop the caller owns the [flush].
  ///
  /// The optional parameter [data] can be used for additional runtime information.
  Future<void> run([void data]) async {
    if (_isRunning) return;
    _isRunning = true;
    try{
      final hostDir = await _fileManager.prepareFiles(_hostParameters.dbPath);
      await _hostBinder.startServer(hostDir.path);
    }on Failure catch(e){
      _logMe.error(e.message,trace: e.stackTrace);
      await flush();
    }catch(e,s){
      if(e is! Failure){
        _logMe.error(e.toString(),trace: s);
      }
      await flush();
    }
    finally{
     _isRunning = false;
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