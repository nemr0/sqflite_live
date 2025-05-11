import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite_live/src/exceptions/file_failure.dart';
import 'package:sqflite_live/src/host/file_manager/file_manager.dart';

class IFileManager extends FileManager {
  Directory? hostDir;

  @override
  Future<Directory> prepareFiles(String dbPath) async {
    try{

      await _getHostPath();
      _copyDatabase(dbPath);
       _copyAssets(hostDir!.path);
      return hostDir!;
    } catch(e,s){
      throw (FileFailure(e.toString(), stackTrace: s));
    }
  }

  @override
  Future<bool> flushCache() async {
    if (hostDir != null) {
      if (hostDir!.existsSync()) {
        hostDir!.deleteSync(recursive: true);
        return true;
      }
    }
    return false;
  }
  Future<Directory> _getHostPath() async {
    try{
      if (hostDir == null) {
        // get cache directory
        final hostPath = '${(await getTemporaryDirectory()).path}/host';
        hostDir = Directory(hostPath);
        if (!hostDir!.existsSync()) {
          hostDir!.createSync(recursive: true);
        }
        return hostDir!;
      }
      return hostDir!;
    } catch(e,s){
      throw (FileFailure('Couldn\'t Creating Host directory: $e', stackTrace: s));
    }
  }
  void _copyDatabase(String fromPath)  {
    final dbFile = File(fromPath);
    if (!dbFile.existsSync()) {
      throw (FileFailure('Database file doesn\'t exist'));
    }
    final newDbFile = File('${hostDir!.path}/${dbFile.path.split('/').last}');
    if (!newDbFile.existsSync()) {
      newDbFile.createSync(recursive: true);
    }
    dbFile.copySync(newDbFile.path);
  }
  void _copyAssets(String toPath) {
    final assetsDirectory = Directory('assets/web');
  final files = assetsDirectory.listSync(recursive: true);
    for (var file in files) {
      if (file is File) {
        final newFilePath ='$toPath/${file.path.split(assetsDirectory.path).last}';
        print('New file path: $newFilePath');
        final newFile = File(newFilePath);
        if (!newFile.existsSync()) {
          newFile.createSync(recursive: true);
        }
        file.copySync(newFile.path);
      }
    }
  }

}
