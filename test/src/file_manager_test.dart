import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_live/src/host/file_manager/file_manager.dart';
import 'package:sqflite_live/src/host/file_manager/file_manager_impl.dart';

import 'test_helpers/get_paths.dart';

void main(){
  group('IFileManager', (){
    TestWidgetsFlutterBinding.ensureInitialized();
    final FileManager fileManager = IFileManager();

    final File dbFile =getDbFileForTesting();
    final String hostDirectory = getHostDirectoryForTesting().path;

    test('prepareFiles', () async {


      // Create the host directory
      await fileManager.prepareFiles( dbFile.path,hostDir: hostDirectory,);

      // Check if the directory was created
      expect(Directory(hostDirectory).existsSync(), true,reason: 'Host directory was not created');

      // Check if the database file was copied
      expect(dbFile.existsSync(), true,reason: 'Database file was not linked');
    });
    test('flush', () async {
      // Flush the host directory
      await fileManager.flush();

      // Check if the directory was deleted
      expect(Directory(hostDirectory).existsSync(), false,reason: 'Host directory was not deleted');
    });
  });
}