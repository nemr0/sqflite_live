import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' show join;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_live/sqflite_live.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const _dbName = 'demo.db';
  static const _dbVersion = 1;

  // table names
  static const userTable = 'users';
  static const taskTable = 'tasks';

  final _rnd = Random();

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
    )
    /// JUST ADD THIS:::
    ..live(enabled: kDebugMode, level: LogLevel.info, port: 8881));
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

  Future<List<Map<String, Object?>>> getUsers() async {
    final db = await database;
    return db.query(userTable, orderBy: 'id');
  }

  Future<List<Map<String, Object?>>> getTasks() async {
    final db = await database;
    return db.query(taskTable, orderBy: 'id');
  }

  /// Inserts one random user.
  Future<void> insertRandomUser() async {
    final db = await database;
    await db.insert(userTable, {
      'name': 'User${_rnd.nextInt(1000)}',
      'age': _rnd.nextInt(60) + 18,
    });
  }

  /// Inserts one random task assigned to a random existing user.
  Future<void> insertRandomTask() async {
    final db = await database;
    final users = await db.query(userTable, columns: ['id']);
    if (users.isEmpty) return;
    final uid = users[_rnd.nextInt(users.length)]['id'] as int;
    await db.insert(taskTable, {
      'title': 'Task ${_rnd.nextInt(10000)}',
      'user_id': uid,
      'is_done': _rnd.nextBool() ? 1 : 0,
    });
  }

  /// Renames a random user (an UPDATE, to test edits).
  Future<void> renameRandomUser() async {
    final db = await database;
    final users = await db.query(userTable, columns: ['id']);
    if (users.isEmpty) return;
    final uid = users[_rnd.nextInt(users.length)]['id'] as int;
    await db.update(
      userTable,
      {'name': 'Renamed${_rnd.nextInt(1000)}', 'age': _rnd.nextInt(60) + 18},
      where: 'id = ?',
      whereArgs: [uid],
    );
  }

  /// Toggles a task's done flag.
  Future<void> toggleTask(int id, bool done) async {
    final db = await database;
    await db.update(
      taskTable,
      {'is_done': done ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes a specific user and their tasks.
  Future<void> deleteUser(int id) async {
    final db = await database;
    await db.delete(taskTable, where: 'user_id = ?', whereArgs: [id]);
    await db.delete(userTable, where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes a random user (and their tasks).
  Future<void> deleteRandomUser() async {
    final db = await database;
    final users = await db.query(userTable, columns: ['id']);
    if (users.isEmpty) return;
    await deleteUser(users[_rnd.nextInt(users.length)]['id'] as int);
  }

  /// Removes every row from both tables.
  Future<void> clearAll() async {
    final db = await database;
    await db.delete(taskTable);
    await db.delete(userTable);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Open the database and start the live server. Watch the console for the
  // 🗂️ SQFLITE Server @ http://… URL, open it in a browser on the same
  // network, then use the buttons in the app and refresh the browser to see
  // the changes live.
  await DatabaseHelper.instance.database;
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'sqflite_live Demo',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _db = DatabaseHelper.instance;
  late final ScrollController _scrollController;
  // Holding the rows in notifiers lets only the affected slivers rebuild
  // instead of the whole page on every refresh.
  final _users = ValueNotifier<List<Map<String, Object?>>>(const []);
  final _tasks = ValueNotifier<List<Map<String, Object?>>>(const []);

  @override
  void initState() {
    _scrollController = ScrollController();
    super.initState();
    _refresh();

  }

  @override
  void dispose() {
    _scrollController.dispose();
    _users.dispose();
    _tasks.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final users = await _db.getUsers();
    final tasks = await _db.getTasks();
    if (!mounted) return;
    _users.value = users;
    _tasks.value = tasks;
  }

  Future<void> _run(Future<void> Function() action, String message) async {
    await action();
    await _refresh();
    if (!mounted) return;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('sqflite_live Demo'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (!_scrollController.hasClients) return;
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        },
        child: const Icon(Icons.arrow_upward),
      ),
      body: Column(
        children: [
          // Rebuilds only when the *emptiness* of either list flips, so the
          // buttons don't churn while rows change.
          _ActionBar(
            users: _users,
            tasks: _tasks,
            onAddUser: () => _run(_db.insertRandomUser, 'Added a user'),
            onAddTask: () => _run(_db.insertRandomTask, 'Added a task'),
            onDeleteUser: () => _run(_db.deleteRandomUser, 'Deleted a user'),
            onUpdateUser: () => _run(_db.renameRandomUser, 'Renamed a user'),
            onClear: () => _run(_db.clearAll, 'Cleared the database'),
          ),
          const Divider(height: 1),
          Expanded(
            child: ValueListenableBuilder<List<Map<String, Object?>>>(
              valueListenable: _users,
              builder: (context, users, _) {
                return ValueListenableBuilder<List<Map<String, Object?>>>(
                  valueListenable: _tasks,
                  builder: (context, tasks, _) {
                    if (users.isEmpty && tasks.isEmpty) {
                      return const Center(
                        child: Text(
                          'Empty database.\nUse "Add user" to start.',
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    return CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        SliverToBoxAdapter(
                          child: _SectionHeader('Users (${users.length})'),
                        ),
                        SliverList.builder(
                          itemCount: users.length,
                          itemBuilder: (context, i) {
                            final u = users[i];
                            final id = u['id'] as int;
                            return _UserTile(
                              key: ValueKey('user-$id'),
                              id: id,
                              name: u['name'] as String,
                              age: u['age'] as int,
                              onDelete: () => _run(
                                () => _db.deleteUser(id),
                                'Deleted ${u['name']}',
                              ),
                            );
                          },
                        ),
                        SliverToBoxAdapter(
                          child: _SectionHeader('Tasks (${tasks.length})'),
                        ),
                        SliverList.builder(
                          itemCount: tasks.length,
                          itemBuilder: (context, i) {
                            final t = tasks[i];
                            final id = t['id'] as int;
                            final done = (t['is_done'] as int) == 1;
                            return _TaskTile(
                              key: ValueKey('task-$id'),
                              title: t['title'] as String,
                              userId: t['user_id'] as int,
                              done: done,
                              onToggle: () => _run(
                                () => _db.toggleTask(id, !done),
                                'Toggled task',
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    super.key,
    required this.id,
    required this.name,
    required this.age,
    required this.onDelete,
  });

  final int id;
  final String name;
  final int age;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(child: Text('$id')),
      title: Text(name),
      subtitle: Text('Age: $age'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    super.key,
    required this.title,
    required this.userId,
    required this.done,
    required this.onToggle,
  });

  final String title;
  final int userId;
  final bool done;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        done ? Icons.check_circle : Icons.radio_button_unchecked,
      ),
      title: Text(title),
      subtitle: Text('user_id: $userId'),
      onTap: onToggle,
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.users,
    required this.tasks,
    required this.onAddUser,
    required this.onAddTask,
    required this.onDeleteUser,
    required this.onUpdateUser,
    required this.onClear,
  });

  final ValueListenable<List<Map<String, Object?>>> users;
  final ValueListenable<List<Map<String, Object?>>> tasks;
  final VoidCallback onAddUser;
  final VoidCallback onAddTask;
  final VoidCallback onDeleteUser;
  final VoidCallback onUpdateUser;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: onAddUser,
            icon: const Icon(Icons.person_add),
            label: const Text('Add user'),
          ),
          // Each gate widget rebuilds only when its own enabled state flips.
          _EnabledGate(
            listenable: users,
            isEnabled: () => users.value.isNotEmpty,
            builder: (enabled) => FilledButton.tonalIcon(
              onPressed: enabled ? onAddTask : null,
              icon: const Icon(Icons.add_task),
              label: const Text('Add task'),
            ),
          ),
          _EnabledGate(
            listenable: users,
            isEnabled: () => users.value.isNotEmpty,
            builder: (enabled) => OutlinedButton.icon(
              onPressed: enabled ? onUpdateUser : null,
              icon: const Icon(Icons.edit),
              label: const Text('Rename user'),
            ),
          ),
          _EnabledGate(
            listenable: users,
            isEnabled: () => users.value.isNotEmpty,
            builder: (enabled) => OutlinedButton.icon(
              onPressed: enabled ? onDeleteUser : null,
              icon: const Icon(Icons.person_remove),
              label: const Text('Delete user'),
            ),
          ),
          _EnabledGate(
            listenable: Listenable.merge([users, tasks]),
            isEnabled: () => users.value.isNotEmpty || tasks.value.isNotEmpty,
            builder: (enabled) => TextButton.icon(
              onPressed: enabled ? onClear : null,
              icon: const Icon(Icons.delete_sweep),
              label: const Text('Clear all'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rebuilds [builder] whenever [listenable] fires, passing the current
/// [isEnabled] result. Keeps each button's rebuild scope to just itself.
class _EnabledGate extends StatelessWidget {
  const _EnabledGate({
    required this.listenable,
    required this.isEnabled,
    required this.builder,
  });

  final Listenable listenable;
  final bool Function() isEnabled;
  final Widget Function(bool enabled) builder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => builder(isEnabled()),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
