import 'dart:io';

abstract class FileManager {
  ///
  /// - Creates the host directory if it doesn't exist
  /// - Copies the database file to the host directory
  /// - Copies the hosting files to the host directory
  /// - Returns the host directory
  Future<Directory> prepareFiles(String dbPath);
  /// Deletes the host directory and all its contents
  Future<bool> flushCache();

  File get dbFile;
  String get dbName => dbFile.path.split('/').last;
}