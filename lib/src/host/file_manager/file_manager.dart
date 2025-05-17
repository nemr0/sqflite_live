import 'dart:io';

/// Abstract class for managing files associated with the live server.
///
/// This class is responsible for:
/// \- Creating the host directory if it doesn’t exist.
/// \- Copying the database file to the host directory.
/// \- Copying the hosting files to the host directory.
/// \- Returning the host directory after preparation.
///
/// Implementations must also provide functionality to delete the host directory and all its contents.
abstract class FileManager {
  FileManager();
  /// Prepares the necessary files by:
  /// \- Creating the host directory if it does not exist.
  /// \- Copying the database file and hosting files into the directory.
  /// \- Returning the prepared host directory.
  ///
  /// [dbPath] is the path to the database file.
  /// Returns a [Future]<[Directory]> representing the host directory.
  Future<Directory> prepareFiles(String dbPath,{String? hostDir});

  /// Deletes the host directory and all its contents.
  ///
  /// Returns a [Future]<[bool]> that indicates whether the flush operation was successful.
  Future<bool> flush();

  /// Returns the database file.
  File get dbFile;

  /// Returns the name of the database file.
  ///
  /// This is extracted from the path of [dbFile] by splitting the path using `/` as the separator.
  String get dbName => dbFile.path.split('/').last;
}