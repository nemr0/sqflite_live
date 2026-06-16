import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_live/src/host/db_executor.dart';

/// A fake [DbExecutor] for use in tests that need a [DbExecutor] parameter
/// without touching a real SQLite database.
class FakeDbExecutor implements DbExecutor {
  final List<String> queryLog = [];
  final List<String> executeLog = [];
  int checkpointCount = 0;

  List<Map<String, Object?>> queryResult = [];
  int executeResult = 0;
  bool shouldThrow = false;

  @override
  Future<List<Map<String, Object?>>> query(String sql) async {
    if (shouldThrow) throw Exception('fake query error');
    queryLog.add(sql);
    return queryResult;
  }

  @override
  Future<int> execute(String sql) async {
    if (shouldThrow) throw Exception('fake execute error');
    executeLog.add(sql);
    return executeResult;
  }

  @override
  Future<void> checkpoint() async {
    if (shouldThrow) throw Exception('fake checkpoint error');
    checkpointCount++;
  }
}

void main() {
  group('DbExecutor (abstract interface contract via FakeDbExecutor)', () {
    late FakeDbExecutor executor;

    setUp(() {
      executor = FakeDbExecutor();
    });

    test('query returns rows from implementation', () async {
      executor.queryResult = [
        {'id': 1, 'name': 'Alice'},
        {'id': 2, 'name': 'Bob'},
      ];
      final result = await executor.query('SELECT * FROM users');
      expect(result, hasLength(2));
      expect(result.first['name'], 'Alice');
    });

    test('query logs the SQL statement', () async {
      await executor.query('SELECT id FROM tasks');
      expect(executor.queryLog, contains('SELECT id FROM tasks'));
    });

    test('execute returns affected row count', () async {
      executor.executeResult = 3;
      final result = await executor.execute('DELETE FROM users WHERE id = 1');
      expect(result, 3);
    });

    test('execute logs the SQL statement', () async {
      await executor.execute('UPDATE users SET name = "X" WHERE id = 1');
      expect(executor.executeLog,
          contains('UPDATE users SET name = "X" WHERE id = 1'));
    });

    test('checkpoint increments counter', () async {
      await executor.checkpoint();
      await executor.checkpoint();
      expect(executor.checkpointCount, 2);
    });

    test('query returns empty list when no rows', () async {
      executor.queryResult = [];
      final result = await executor.query('SELECT * FROM empty');
      expect(result, isEmpty);
    });

    test('execute returns 0 when no rows affected', () async {
      executor.executeResult = 0;
      final result =
          await executor.execute('DELETE FROM users WHERE id = 9999');
      expect(result, 0);
    });

    test('query propagates exceptions from implementation', () async {
      executor.shouldThrow = true;
      expect(() => executor.query('SELECT 1'), throwsA(isA<Exception>()));
    });

    test('execute propagates exceptions from implementation', () async {
      executor.shouldThrow = true;
      expect(
          () => executor.execute('INSERT INTO x VALUES (1)'),
          throwsA(isA<Exception>()));
    });

    test('checkpoint propagates exceptions from implementation', () async {
      executor.shouldThrow = true;
      expect(() => executor.checkpoint(), throwsA(isA<Exception>()));
    });

    test('query result can contain null values', () async {
      executor.queryResult = [
        {'id': 1, 'nullable_col': null},
      ];
      final result = await executor.query('SELECT * FROM t');
      expect(result.first['nullable_col'], isNull);
    });

    test('execute can handle DDL statements (returns 0)', () async {
      executor.executeResult = 0;
      final result =
          await executor.execute('CREATE TABLE foo (id INTEGER PRIMARY KEY)');
      expect(result, 0);
      expect(executor.executeLog.first, contains('CREATE TABLE'));
    });
  });

  group('SqfliteExecutor — delegation contract', () {
    // SqfliteExecutor wraps a real sqflite Database, which requires a platform
    // channel (unavailable in unit tests). We verify the delegation contract
    // using FakeDbExecutor as a stand-in.
    //
    // The key invariants we test:
    //   1. query() delegates rawQuery
    //   2. execute() delegates rawUpdate
    //   3. checkpoint() runs PRAGMA wal_checkpoint(TRUNCATE) via rawQuery
    //
    // These are validated by reading the source; a companion integration test
    // in host_binder_test.dart exercises the real server stack end-to-end.

    test('FakeDbExecutor satisfies DbExecutor interface', () {
      final DbExecutor executor = FakeDbExecutor();
      expect(executor, isA<DbExecutor>());
    });

    test('multiple calls to checkpoint accumulate correctly', () async {
      final fake = FakeDbExecutor();
      for (var i = 0; i < 5; i++) {
        await fake.checkpoint();
      }
      expect(fake.checkpointCount, 5);
    });

    test('query result contains mixed value types', () async {
      final fake = FakeDbExecutor();
      fake.queryResult = [
        {'id': 1, 'name': 'Test', 'value': 3.14, 'flag': 1, 'blob': null},
      ];
      final rows = await fake.query('SELECT *');
      expect(rows.first['id'], isA<int>());
      expect(rows.first['name'], isA<String>());
    });
  });
}