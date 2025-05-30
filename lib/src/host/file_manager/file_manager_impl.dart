import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_live/src/exceptions/failure_abs.dart';
import 'package:sqflite_live/src/exceptions/file_failure.dart';
import 'package:sqflite_live/src/host/file_manager/file_manager.dart';
import 'package:flutter/services.dart' show  ByteData, Uint8List, rootBundle;

class IFileManager extends FileManager {

  Directory? _hostDir;
  File? _dbPath;

  @override
  Future<Directory> prepareFiles(String db,{String? hostDir}) async {
    try {
      if(hostDir == null) {
        await _getHostPath();
      } else{
        _hostDir = Directory(hostDir);
        if(_hostDir!.existsSync() == false)  _hostDir!.createSync(recursive: true);
      }
      await _linkDb(db);
      await _extractAssets(_hostDir!.path);
      return _hostDir!;
    } on FileFailure catch (_) {
      rethrow;
    } catch (e, s) {
      throw FileFailure(e.toString(), stackTrace: s);
    }
  }

  @override
  Future<bool> flush() async {
    if (_hostDir != null) {
      if (_hostDir!.existsSync()) {
        _hostDir!.deleteSync(recursive: true);
        return true;
      }
    }
    return false;
  }

  Future<Directory> _getHostPath() async {
    try {
      if (_hostDir == null) {
        // get cache directory
        final hostPath = join((await getApplicationSupportDirectory()).path,'host');
        _hostDir = Directory(hostPath);
        if (!_hostDir!.existsSync()) {
          _hostDir!.createSync(recursive: true);
        }
        return _hostDir!;
      }
      return _hostDir!;
    } catch (e, s) {
      throw (FileFailure('Couldn\'t Creating Host directory: $e',
          stackTrace: s));
    }
  }

  Future<void> _linkDb(String fromPath) async {
    final fileSystemEntityType = await FileSystemEntity.type(fromPath, followLinks: false);
    switch (fileSystemEntityType) {
      case FileSystemEntityType.directory:
        _createDbLink(_firstDBFileFrom(Directory(fromPath)));
        break;
      case FileSystemEntityType.file:
        _createDbLink(File(fromPath));
        break;
      default:
        throw (_dbFileNotFoundFailure);
    }
  }

  static const Failure _dbFileNotFoundFailure =
      FileFailure('Database file doesn\'t exist');


  void _createDbLink(File file) {
    if (!file.existsSync()) {
      throw (_dbFileNotFoundFailure);
    }
    final dbPath  = '${_hostDir!.path}/cached.db';
    try{
      final newDbFile = Link(dbPath);
      if (newDbFile.existsSync()) {
        newDbFile.deleteSync();
      }
      newDbFile.createSync(file.path);

      _dbPath = file;
    }catch(e,s){
      if(e is FileSystemException) {
       File(dbPath).createSync();
       file.copySync(dbPath);
      } else {
        throw (FileFailure('error: $e', stackTrace: s));
      }
    }
  }

  File _firstDBFileFrom(Directory dbDir) {
    if (!dbDir.existsSync()) throw (_dbFileNotFoundFailure);
    final files =
        dbDir.listSync().where((e) => e is File && e.path.endsWith('.db'));
    if (files.isEmpty) throw (_dbFileNotFoundFailure);
    return files.first as File;
  }

  Future<void> _extractAssets(String toPath) async {
    // 1. Load the ZIP from your bundled assets
    final ByteData zipData = await rootBundle.load('packages/sqflite_live/sqlite_viewer/package.zip');

    // 2. Convert to Uint8List & decode
    final Uint8List bytes = zipData.buffer.asUint8List();
    final Archive archive = ZipDecoder().decodeBytes(bytes);

    // 3. Ensure the target root directory exists
    final Directory targetDir = Directory(toPath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    // 4. Iterate over every entry in the ZIP
    for (final ArchiveFile file in archive) {
      // Compute the full output path
      final String outPath = join(toPath, file.name);

      if (file.isFile) {
        // Ensure parent directories exist
        final File outFile = File(outPath);
        await outFile.parent.create(recursive: true);

        // Write the file contents
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        // It's a directory, so just create it
        await Directory(outPath).create(recursive: true);
      }
    }

  }

  @override
  File get dbFile  {
    if(_dbPath == null) throw(_dbFileNotFoundFailure);
    return _dbPath!;
  }
}
