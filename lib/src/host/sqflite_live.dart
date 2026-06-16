import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sqflite_live/src/host/live_server.dart';

/// A handle to a running live server.
///
/// Returned from `Database.live()`. Use it to [stop], [start] (restart),
/// [ensureRunning] or [dispose] the server explicitly instead of leaving it
/// fire-and-forget.
///
/// When `autoRestart` is enabled (the default), the handle registers itself as
/// a [WidgetsBindingObserver]. It deliberately does **not** stop the server
/// when the app is backgrounded — mobile OSes suspend the process anyway.
/// Instead, on [AppLifecycleState.resumed] it probes the server with a real
/// loopback request and only rebuilds it if it stopped responding (e.g. the
/// OS tore the socket down while suspended). A server that survived
/// backgrounding is left untouched.
///
/// After a rebuild the browser only needs a refresh.
class SqfliteLive with WidgetsBindingObserver {
  /// Creates a handle around [server]. When [autoRestart] is true it starts
  /// observing app lifecycle changes immediately.
  ///
  /// Must be constructed after `WidgetsFlutterBinding.ensureInitialized()`.
  SqfliteLive(this._server, {this.autoRestart = true}) {
    if (autoRestart) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  final LiveServer _server;

  /// Whether the handle automatically checks/rebuilds the server when the app
  /// returns to the foreground.
  final bool autoRestart;

  bool _disposed = false;

  /// The currently running [LiveServer.run] future, if serving. Completes only
  /// when the server is closed, so [stop] awaits it to guarantee a clean
  /// unwind before a restart.
  Future<void>? _runFuture;

  /// Whether the HTTP server is currently bound and serving.
  bool get isRunning => _server.isRunning;

  /// Starts the server. No-op if it is already running or the handle has been
  /// disposed.
  Future<void> start() async {
    if (_disposed || _server.isRunning) return;
    // run() only completes when the server is closed, so don't await it here.
    _runFuture = _server.run();
  }

  /// Stops the server and cleans up the host files. The handle stays usable —
  /// call [start] or [ensureRunning] again to bring it back.
  Future<void> stop() async {
    await _server.flush();
    // Wait for run()'s request loop to fully unwind so a subsequent start()
    // doesn't race a half-closed server. Guarded with a timeout so a wedged
    // socket can never hang the caller.
    try {
      await _runFuture?.timeout(const Duration(seconds: 3));
    } catch (_) {
      // Timed out or run() threw on close; either way we're stopping.
    }
    _runFuture = null;
  }

  /// Ensures a working server is running: if the current one no longer responds
  /// (typically after the app was suspended in the background), it is rebuilt;
  /// otherwise it is left as-is.
  Future<void> ensureRunning() async {
    if (_disposed) return;
    if (await _server.isHealthy()) {
      // Still up — just re-log the URL so it's visible after resuming.
      await _server.announce();
      return;
    }
    await stop();
    await start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!autoRestart || _disposed) return;
    // Intentionally do nothing on pause/hidden/detached: keep the server as-is
    // and only repair it if it didn't survive once we're back in foreground.
    if (state == AppLifecycleState.resumed) {
      ensureRunning();
    }
  }

  /// Permanently tears down the server and stops observing lifecycle events.
  /// The handle cannot be reused afterwards.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (autoRestart) {
      WidgetsBinding.instance.removeObserver(this);
    }
    await stop();
  }
}
