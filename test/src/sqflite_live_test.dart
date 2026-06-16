import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_live/src/host/file_manager/file_manager.dart';
import 'package:sqflite_live/src/host/host_binder/host_binder.dart';
import 'package:sqflite_live/src/host/host_binder/host_parameters.dart';
import 'package:sqflite_live/src/host/live_server.dart';
import 'package:sqflite_live/src/host/logger/log_me.dart';
import 'package:sqflite_live/src/host/sqflite_live.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeFileManager extends FileManager {
  _FakeFileManager()
      : _dir = Directory.systemTemp.createTempSync('sqflite_live_test_');

  final Directory _dir;
  int flushCount = 0;
  bool _flushed = false;

  @override
  Future<Directory> prepareFiles(String dbPath, {String? hostDir}) async =>
      _dir;

  @override
  Future<bool> flush() async {
    flushCount++;
    _flushed = true;
    return true;
  }

  @override
  File get dbFile => File('${_dir.path}/test.db');
}

class _FakeHostBinder extends HostBinder {
  int startCount = 0;
  int closeCount = 0;
  int logAddressCount = 0;
  bool _alive = true;

  void setAlive(bool value) => _alive = value;

  @override
  Future<void> startServer(String hostDirectory) async {
    startCount++;
    // Simulate a long-running server that blocks until closeServer() is called.
    // For tests we just return immediately.
  }

  @override
  Future<void> closeServer() async {
    closeCount++;
  }

  @override
  Future<bool> isAlive() async => _alive;

  @override
  Future<void> logAddress() async {
    logAddressCount++;
  }
}

class _FakeLogMe extends LogMe {
  @override
  void data(dynamic msg) {}
  @override
  void info(dynamic msg) {}
  @override
  void warning(dynamic msg) {}
  @override
  void error(dynamic msg, {StackTrace? trace}) {}
}

/// A [LiveServer] subclass that allows controlling behaviour in tests without
/// touching real IO or HTTP.
class _FakeLiveServer extends LiveServer {
  _FakeLiveServer({
    bool startHealthy = true,
    bool runCompletes = true,
  })  : _startHealthy = startHealthy,
        _runCompletes = runCompletes,
        super(
          _FakeFileManager(),
          _FakeHostBinder(),
          HostParameters(dbPath: '/tmp/test.db', port: 9999),
          _FakeLogMe(),
        );

  final bool _startHealthy;
  final bool _runCompletes;

  bool _fakeRunning = false;
  int runCount = 0;
  int flushCount = 0;
  int announceCount = 0;
  bool healthy = true;

  @override
  bool get isRunning => _fakeRunning;

  @override
  Future<void> run([void data]) async {
    runCount++;
    _fakeRunning = true;
    if (_runCompletes) {
      _fakeRunning = false;
    }
    // In a real server run() only completes when the server is closed.
    // For tests we return immediately.
  }

  @override
  Future<void> flush() async {
    flushCount++;
    _fakeRunning = false;
  }

  @override
  Future<bool> isHealthy() async => healthy;

  @override
  Future<void> announce() async {
    announceCount++;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SqfliteLive — basic state', () {
    test('isRunning reflects LiveServer.isRunning', () {
      final server = _FakeLiveServer();
      final live = SqfliteLive(server, autoRestart: false);
      expect(live.isRunning, isFalse);
    });

    test('start() calls server.run() and marks running', () async {
      final server = _FakeLiveServer(runCompletes: false);
      final live = SqfliteLive(server, autoRestart: false);
      await live.start();
      expect(server.runCount, 1);
    });

    test('start() is a no-op when already running', () async {
      final server = _FakeLiveServer(runCompletes: false);
      server._fakeRunning = true; // simulate already-running server
      final live = SqfliteLive(server, autoRestart: false);
      await live.start();
      expect(server.runCount, 0,
          reason: 'start() should not call run() when already running');
    });

    test('start() is a no-op after dispose()', () async {
      final server = _FakeLiveServer();
      final live = SqfliteLive(server, autoRestart: false);
      await live.dispose();
      await live.start();
      expect(server.runCount, 0,
          reason: 'start() should not call run() after dispose');
    });
  });

  group('SqfliteLive — stop()', () {
    test('stop() calls server.flush()', () async {
      final server = _FakeLiveServer();
      final live = SqfliteLive(server, autoRestart: false);
      await live.stop();
      expect(server.flushCount, 1);
    });

    test('stop() can be called multiple times without error', () async {
      final server = _FakeLiveServer();
      final live = SqfliteLive(server, autoRestart: false);
      await live.stop();
      await live.stop();
      expect(server.flushCount, 2);
    });
  });

  group('SqfliteLive — dispose()', () {
    test('dispose() calls stop() which calls flush()', () async {
      final server = _FakeLiveServer();
      final live = SqfliteLive(server, autoRestart: false);
      await live.dispose();
      expect(server.flushCount, 1);
    });

    test('dispose() is idempotent — second call is a no-op', () async {
      final server = _FakeLiveServer();
      final live = SqfliteLive(server, autoRestart: false);
      await live.dispose();
      await live.dispose();
      // flush() is called only once; second dispose returns early.
      expect(server.flushCount, 1);
    });

    test('start() after dispose() is a no-op', () async {
      final server = _FakeLiveServer();
      final live = SqfliteLive(server, autoRestart: false);
      await live.dispose();
      await live.start();
      expect(server.runCount, 0);
    });

    test('ensureRunning() after dispose() is a no-op', () async {
      final server = _FakeLiveServer();
      final live = SqfliteLive(server, autoRestart: false);
      await live.dispose();
      // Should not throw and should not call any server method.
      await expectLater(live.ensureRunning(), completes);
    });
  });

  group('SqfliteLive — ensureRunning()', () {
    test('when server is healthy, announces and does NOT restart', () async {
      final server = _FakeLiveServer();
      server.healthy = true;
      final live = SqfliteLive(server, autoRestart: false);
      await live.ensureRunning();
      expect(server.announceCount, 1);
      expect(server.runCount, 0,
          reason: 'should not restart a healthy server');
    });

    test('when server is NOT healthy, stops and restarts it', () async {
      final server = _FakeLiveServer();
      server.healthy = false;
      final live = SqfliteLive(server, autoRestart: false);
      await live.ensureRunning();
      // stop() → flush() is called once, then start() → run() is called once.
      expect(server.flushCount, greaterThanOrEqualTo(1));
      expect(server.runCount, 1);
      expect(server.announceCount, 0,
          reason: 'announce is only called for a still-healthy server');
    });

    test('when server is healthy, announce count increases on each call', () async {
      final server = _FakeLiveServer();
      server.healthy = true;
      final live = SqfliteLive(server, autoRestart: false);
      await live.ensureRunning();
      await live.ensureRunning();
      expect(server.announceCount, 2);
    });
  });

  group('SqfliteLive — autoRestart lifecycle observer', () {
    test('with autoRestart=false, lifecycle changes are ignored', () async {
      final server = _FakeLiveServer();
      server.healthy = false; // would restart if observed
      final live = SqfliteLive(server, autoRestart: false);
      live.didChangeAppLifecycleState(AppLifecycleState.resumed);
      // Give a chance for any async ensureRunning() to kick off.
      await Future<void>.delayed(Duration.zero);
      expect(server.runCount, 0,
          reason: 'autoRestart=false should not react to lifecycle changes');
    });

    test('with autoRestart=true, resumed triggers ensureRunning()', () async {
      final server = _FakeLiveServer();
      server.healthy = true;
      final live = SqfliteLive(server, autoRestart: true);
      live.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(server.announceCount, greaterThanOrEqualTo(1));
      await live.dispose();
    });

    test('non-resumed lifecycle states do not trigger ensureRunning()', () async {
      final server = _FakeLiveServer();
      server.healthy = false; // would restart if ensureRunning is called
      final live = SqfliteLive(server, autoRestart: true);
      for (final state in [
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.detached,
        AppLifecycleState.inactive,
      ]) {
        live.didChangeAppLifecycleState(state);
      }
      await Future<void>.delayed(Duration.zero);
      expect(server.runCount, 0,
          reason: 'only resumed should trigger ensureRunning');
      await live.dispose();
    });

    test('after dispose, lifecycle changes are ignored even with autoRestart=true',
        () async {
      final server = _FakeLiveServer();
      server.healthy = false;
      final live = SqfliteLive(server, autoRestart: true);
      await live.dispose();
      server.runCount = 0; // reset after dispose's own stop()
      live.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(server.runCount, 0);
    });
  });

  group('SqfliteLive — autoRestart flag', () {
    test('autoRestart defaults to true', () {
      final server = _FakeLiveServer();
      final live = SqfliteLive(server);
      expect(live.autoRestart, isTrue);
      live.dispose();
    });

    test('autoRestart can be set to false', () {
      final server = _FakeLiveServer();
      final live = SqfliteLive(server, autoRestart: false);
      expect(live.autoRestart, isFalse);
    });
  });

  group('SqfliteLive — start/stop cycle', () {
    test('start then stop can be called multiple times', () async {
      final server = _FakeLiveServer();
      final live = SqfliteLive(server, autoRestart: false);
      await live.start();
      await live.stop();
      await live.start();
      await live.stop();
      // run() called twice, flush() called twice.
      expect(server.runCount, 2);
      expect(server.flushCount, 2);
    });
  });
}
