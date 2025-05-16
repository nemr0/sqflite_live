import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_live/sqflite_live.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
   await DatabaseHelper.instance.database;
  // Insert some random data once (you might guard this so it only runs on first launch)
  await DatabaseHelper.instance.insertRandomData();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'sqflite Demo',
      home: Scaffold(
        appBar: AppBar(title: Text('sqflite Demo')),
        body: Center(child: Text('Database Initialized')),
      ),
    );
  }
}

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const _dbName = 'demo.db';
  static const _dbVersion = 1;

  // table names
  static const userTable = 'users';
  static const taskTable = 'tasks';

  // singleton Database reference
  Database? _db;
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  // open the database & create tables if they don't exist
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    return (await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
    ))..live(level: Level.all);

  }

  // SQL to create the two tables
  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $userTable (
        id   INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        age  INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE $taskTable (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        title    TEXT NOT NULL,
        user_id  INTEGER NOT NULL,
        is_done  INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(user_id) REFERENCES $userTable(id)
      )
    ''');
  }

  /// Inserts some random users and tasks.
  Future<void> insertRandomData() async {
    final db = await database;
    final rnd = Random();

    // generate 5 random users
    for (int i = 0; i < 5; i++) {
      final name = 'User${rnd.nextInt(1000)}';
      final age  = rnd.nextInt(60) + 18;
      await db.insert(userTable, {
        'name': name,
        'age': age,
      });
    }

    // fetch all user IDs
    final users = await db.query(userTable, columns: ['id']);
    if (users.isEmpty) return;

    // for each user, generate 2–4 tasks
    for (var u in users) {
      final uid = u['id'] as int;
      final taskCount = rnd.nextInt(3) + 2; // between 2 and 4
      for (int j = 0; j < taskCount; j++) {
        await db.insert(taskTable, {
          'title': 'Task ${rnd.nextInt(10000)}',
          'user_id': uid,
          'is_done': rnd.nextBool() ? 1 : 0,
        });
      }
    }
  }

  // (Optional) helper to fetch and print data for debugging
  Future<void> debugPrintAll() async {
    final db = await database;
    final allUsers = await db.query(userTable);
    final allTasks = await db.query(taskTable);
    if (kDebugMode) {
      print('=== USERS ===');
    }
    for (var u in allUsers) {
      if (kDebugMode) {
        print(u);
      }
    }
    if (kDebugMode) {
      print('=== TASKS ===');
    }
    for (var t in allTasks) {
      if (kDebugMode) {
        print(t);
      }
    }
  }
}
