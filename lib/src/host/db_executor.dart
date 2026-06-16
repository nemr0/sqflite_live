import 'package:sqflite/sqflite.dart';

/// Runs SQL against the live database on behalf of the viewer.
///
/// Kept abstract so the HTTP layer doesn't depend on sqflite directly and can
/// be exercised with a fake in tests.
abstract class DbExecutor {
  /// Runs a row-returning statement (`SELECT`/`PRAGMA`/…) and returns the rows.
  Future<List<Map<String, Object?>>> query(String sql);

  /// Runs a mutating statement (`INSERT`/`UPDATE`/`DELETE`/DDL) and returns the
  /// number of affected rows (0 for statements that don't change rows).
  Future<int> execute(String sql);

  /// Flushes the write-ahead log into the main database file.
  ///
  /// sqflite opens databases in WAL mode by default, so committed writes live
  /// in the `-wal` sidecar until a checkpoint. The viewer only reads the main
  /// `.db` file, so without this it never sees recent app-side writes.
  Future<void> checkpoint();
}

/// [DbExecutor] backed by the app's live sqflite [Database] connection, so
/// changes go through SQLite normally and are visible to both the app and the
/// next viewer refresh.
class SqfliteExecutor implements DbExecutor {
  SqfliteExecutor(this._db);

  final Database _db;

  @override
  Future<List<Map<String, Object?>>> query(String sql) => _db.rawQuery(sql);

  @override
  Future<int> execute(String sql) => _db.rawUpdate(sql);

  @override
  Future<void> checkpoint() async {
    // TRUNCATE checkpoints all frames and shrinks the WAL back to empty, so the
    // main file is a complete, self-contained snapshot for the viewer to read.
    await _db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
  }
}
