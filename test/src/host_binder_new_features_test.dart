import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_live/src/host/db_executor.dart';
import 'package:sqflite_live/src/host/host_binder/host_binder_impl.dart';
import 'package:sqflite_live/src/host/host_binder/host_parameters.dart';
import 'package:sqflite_live/src/host/logger/log_me.dart';
import 'package:sqflite_live/src/host/logger/log_me_impl.dart';
import 'test_helpers/get_paths.dart';
import 'test_helpers/real_http_overrides.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// A [DbExecutor] that records calls and returns configurable results.
class _FakeDbExecutor implements DbExecutor {
  final List<String> queryLog = [];
  final List<String> executeLog = [];
  int checkpointCount = 0;

  List<Map<String, Object?>> queryResult = [];
  int executeResult = 0;
  Exception? queryError;
  Exception? executeError;

  @override
  Future<List<Map<String, Object?>>> query(String sql) async {
    if (queryError != null) throw queryError!;
    queryLog.add(sql);
    return queryResult;
  }

  @override
  Future<int> execute(String sql) async {
    if (executeError != null) throw executeError!;
    executeLog.add(sql);
    return executeResult;
  }

  @override
  Future<void> checkpoint() async {
    checkpointCount++;
  }
}

/// A [LogMe] implementation that records every call.
class _RecordingLogMe extends LogMe {
  final List<String> infoCalls = [];
  final List<String> dataCalls = [];
  final List<String> warningCalls = [];
  final List<String> errorCalls = [];

  @override
  void data(dynamic msg) => dataCalls.add(msg.toString());
  @override
  void info(dynamic msg) => infoCalls.add(msg.toString());
  @override
  void warning(dynamic msg) => warningCalls.add(msg.toString());
  @override
  void error(dynamic msg, {StackTrace? trace}) =>
      errorCalls.add(msg.toString());
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Sends a POST /exec request with [sql] as the body to [port].
Future<Map<String, dynamic>> postExec(int port, String sql) async {
  final client = HttpClient();
  try {
    final req = await client.post('127.0.0.1', port, '/exec');
    req.write(sql);
    final resp = await req.close().timeout(const Duration(seconds: 5));
    final body = await resp.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

/// Sends a GET /db-version request to [port].
Future<Map<String, dynamic>> getDbVersion(int port) async {
  final client = HttpClient();
  try {
    final req = await client.get('127.0.0.1', port, '/db-version');
    final resp = await req.close().timeout(const Duration(seconds: 5));
    final body = await resp.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = RealHttpOverrides();

  // Use a dedicated port range for these tests to avoid conflicts with
  // host_binder_test.dart (which uses 2231).
  const int basePort = 2240;

  group('IHostBinder — isAlive()', () {
    test('returns false when server has not been started (server == null)', () async {
      final params = HostParameters(dbPath: '/tmp/test.db', port: basePort);
      final binder = IHostBinder(params, ILogMe(LogLevel.off));
      final alive = await binder.isAlive();
      expect(alive, isFalse);
    });

    test('returns true when server is running and responds', () async {
      final hostDir = getHostDirectoryForTesting();
      final params = HostParameters(dbPath: '/tmp/test.db', port: basePort + 1);
      final binder = IHostBinder(params, ILogMe(LogLevel.off));

      // Start the server in the background (it loops until closed).
      final serverFuture = binder.startServer(hostDir.path);
      await Future.delayed(const Duration(milliseconds: 200));

      final alive = await binder.isAlive();
      expect(alive, isTrue);

      await binder.closeServer();
      // Drain the startServer future so we don't leave dangling work.
      await serverFuture.catchError((_) {});
    });

    test('returns false after server is closed', () async {
      final hostDir = getHostDirectoryForTesting();
      final params = HostParameters(dbPath: '/tmp/test.db', port: basePort + 2);
      final binder = IHostBinder(params, ILogMe(LogLevel.off));

      final serverFuture = binder.startServer(hostDir.path);
      await Future.delayed(const Duration(milliseconds: 200));

      await binder.closeServer();
      await serverFuture.catchError((_) {});

      final alive = await binder.isAlive();
      expect(alive, isFalse);
    });
  });

  group('IHostBinder — logAddress()', () {
    test('calls logger.info() with a URL containing the port', () async {
      final params = HostParameters(dbPath: '/tmp/test.db', port: basePort + 3);
      final recorder = _RecordingLogMe();
      final binder = IHostBinder(params, recorder);

      await binder.logAddress();

      expect(recorder.infoCalls, isNotEmpty);
      // Primary URL log should contain the port number.
      expect(
        recorder.infoCalls.any((msg) => msg.contains(':${params.port}')),
        isTrue,
        reason: 'Expected at least one log line containing the port',
      );
    });

    test('primary log message contains the SQFLITE server banner', () async {
      final params = HostParameters(dbPath: '/tmp/test.db', port: basePort + 4);
      final recorder = _RecordingLogMe();
      final binder = IHostBinder(params, recorder);

      await binder.logAddress();

      expect(
        recorder.infoCalls.any((msg) => msg.contains('SQFLITE')),
        isTrue,
      );
    });

    test('logAddress() does not throw', () async {
      final params = HostParameters(dbPath: '/tmp/test.db', port: basePort + 5);
      final binder = IHostBinder(params, ILogMe(LogLevel.off));
      await expectLater(binder.logAddress(), completes);
    });
  });

  group('IHostBinder — POST /exec endpoint (SQL classification)', () {
    late _FakeDbExecutor executor;
    late IHostBinder binder;
    late Future<void> serverFuture;
    const int port = basePort + 6;

    setUp(() async {
      executor = _FakeDbExecutor();
      final params = HostParameters(dbPath: '/tmp/test.db', port: port);
      binder = IHostBinder(params, ILogMe(LogLevel.off), executor);
      final hostDir = getHostDirectoryForTesting();
      serverFuture = binder.startServer(hostDir.path);
      await Future.delayed(const Duration(milliseconds: 200));
    });

    tearDown(() async {
      await binder.closeServer();
      await serverFuture.catchError((_) {});
    });

    test('SELECT is routed to executor.query()', () async {
      executor.queryResult = [
        {'id': 1, 'name': 'Alice'}
      ];
      final response = await postExec(port, 'SELECT * FROM users');
      expect(response.containsKey('rows'), isTrue);
      expect(executor.queryLog, contains('SELECT * FROM users'));
      expect(executor.executeLog, isEmpty);
    });

    test('PRAGMA is routed to executor.query()', () async {
      executor.queryResult = [];
      final response = await postExec(port, 'PRAGMA table_info(users)');
      expect(response.containsKey('rows'), isTrue);
      expect(executor.queryLog, contains('PRAGMA table_info(users)'));
    });

    test('EXPLAIN is routed to executor.query()', () async {
      executor.queryResult = [];
      await postExec(port, 'EXPLAIN SELECT * FROM users');
      expect(executor.queryLog.any((s) => s.startsWith('EXPLAIN')), isTrue);
    });

    test('WITH is routed to executor.query()', () async {
      executor.queryResult = [];
      const sql = 'WITH cte AS (SELECT 1) SELECT * FROM cte';
      await postExec(port, sql);
      expect(executor.queryLog, contains(sql));
    });

    test('INSERT is routed to executor.execute()', () async {
      executor.executeResult = 1;
      final response =
          await postExec(port, "INSERT INTO users VALUES (1, 'Bob', 30)");
      expect(response.containsKey('rowsAffected'), isTrue);
      expect(response['rowsAffected'], 1);
      expect(executor.executeLog, isNotEmpty);
    });

    test('UPDATE is routed to executor.execute()', () async {
      executor.executeResult = 2;
      final response =
          await postExec(port, "UPDATE users SET age = 25 WHERE id = 1");
      expect(response.containsKey('rowsAffected'), isTrue);
      expect(response['rowsAffected'], 2);
    });

    test('DELETE is routed to executor.execute()', () async {
      executor.executeResult = 3;
      final response = await postExec(port, 'DELETE FROM users WHERE id = 1');
      expect(response.containsKey('rowsAffected'), isTrue);
      expect(response['rowsAffected'], 3);
    });

    test('DDL CREATE is routed to executor.execute()', () async {
      executor.executeResult = 0;
      final response = await postExec(
          port, 'CREATE TABLE foo (id INTEGER PRIMARY KEY)');
      expect(response.containsKey('rowsAffected'), isTrue);
      expect(response['rowsAffected'], 0);
    });

    test('empty SQL body returns 400 with error payload', () async {
      final client = HttpClient();
      try {
        final req = await client.post('127.0.0.1', port, '/exec');
        req.write('');
        final resp = await req.close().timeout(const Duration(seconds: 5));
        final body = await resp.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        expect(resp.statusCode, HttpStatus.badRequest);
        expect(json.containsKey('error'), isTrue);
      } finally {
        client.close(force: true);
      }
    });

    test('executor error returns 400 with error payload', () async {
      executor.queryError = Exception('db error');
      final client = HttpClient();
      try {
        final req = await client.post('127.0.0.1', port, '/exec');
        req.write('SELECT 1');
        final resp = await req.close().timeout(const Duration(seconds: 5));
        final body = await resp.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        expect(resp.statusCode, HttpStatus.badRequest);
        expect(json.containsKey('error'), isTrue);
      } finally {
        client.close(force: true);
      }
    });

    test('whitespace-padded SELECT is still classified as a query', () async {
      executor.queryResult = [];
      final response = await postExec(port, '   SELECT id FROM users');
      expect(response.containsKey('rows'), isTrue);
    });

    test('lowercase select is classified as a query', () async {
      executor.queryResult = [];
      final response = await postExec(port, 'select * from users');
      expect(response.containsKey('rows'), isTrue);
      expect(executor.queryLog.any((s) => s.contains('select')), isTrue);
    });
  });

  group('IHostBinder — POST /exec without executor (disabled)', () {
    test('returns 503 serviceUnavailable when no executor is provided', () async {
      const int port = basePort + 7;
      final params = HostParameters(dbPath: '/tmp/test.db', port: port);
      // IHostBinder constructed without executor → writes disabled.
      final binder = IHostBinder(params, ILogMe(LogLevel.off));
      final hostDir = getHostDirectoryForTesting();
      final serverFuture = binder.startServer(hostDir.path);
      await Future.delayed(const Duration(milliseconds: 200));

      final client = HttpClient();
      try {
        final req = await client.post('127.0.0.1', port, '/exec');
        req.write('DELETE FROM users');
        final resp = await req.close().timeout(const Duration(seconds: 5));
        final body = await resp.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        expect(resp.statusCode, HttpStatus.serviceUnavailable);
        expect(json['error'], contains('disabled'));
      } finally {
        client.close(force: true);
        await binder.closeServer();
        await serverFuture.catchError((_) {});
      }
    });
  });

  group('IHostBinder — GET /db-version endpoint', () {
    late _FakeDbExecutor executor;
    late IHostBinder binder;
    late Future<void> serverFuture;
    const int port = basePort + 8;

    setUp(() async {
      executor = _FakeDbExecutor();
      final params = HostParameters(dbPath: '/tmp/test.db', port: port);
      binder = IHostBinder(params, ILogMe(LogLevel.off), executor);
      final hostDir = getHostDirectoryForTesting();
      serverFuture = binder.startServer(hostDir.path);
      await Future.delayed(const Duration(milliseconds: 200));
    });

    tearDown(() async {
      await binder.closeServer();
      await serverFuture.catchError((_) {});
    });

    test('/db-version calls checkpoint and returns size+modified', () async {
      final response = await getDbVersion(port);
      // Response always has 200; either size+modified or an error.
      expect(response.containsKey('size') || response.containsKey('error'),
          isTrue);
      // Checkpoint must be called before reading file stat.
      expect(executor.checkpointCount, greaterThanOrEqualTo(1));
    });

    test('/db-version returns JSON with status 200 even on file error', () async {
      // The cached.db file may not exist; the endpoint still returns 200
      // with an error field rather than a 5xx.
      final client = HttpClient();
      try {
        final req = await client.get('127.0.0.1', port, '/db-version');
        final resp = await req.close().timeout(const Duration(seconds: 5));
        expect(resp.statusCode, HttpStatus.ok);
        final body = await resp.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        expect(json, isA<Map<String, dynamic>>());
      } finally {
        client.close(force: true);
      }
    });
  });

  group('IHostBinder — closeServer()', () {
    test('sets server to null (isAlive returns false after close)', () async {
      const int port = basePort + 9;
      final params = HostParameters(dbPath: '/tmp/test.db', port: port);
      final binder = IHostBinder(params, ILogMe(LogLevel.off));
      final hostDir = getHostDirectoryForTesting();
      final serverFuture = binder.startServer(hostDir.path);
      await Future.delayed(const Duration(milliseconds: 200));

      expect(await binder.isAlive(), isTrue);
      await binder.closeServer();
      await serverFuture.catchError((_) {});
      expect(await binder.isAlive(), isFalse);
    });

    test('closeServer() can be called when server is null (no-op)', () async {
      const int port = basePort + 10;
      final params = HostParameters(dbPath: '/tmp/test.db', port: port);
      final binder = IHostBinder(params, ILogMe(LogLevel.off));
      // server is null; closing should not throw.
      await expectLater(binder.closeServer(), completes);
    });
  });
}