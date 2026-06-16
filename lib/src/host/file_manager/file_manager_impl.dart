import 'dart:async';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_live/src/exceptions/failure_abs.dart';
import 'package:sqflite_live/src/exceptions/file_failure.dart';
import 'package:sqflite_live/src/host/file_manager/file_manager.dart';
import 'package:flutter/services.dart' show AssetManifest, ByteData, rootBundle;

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
      }
      // Ensure the directory exists on disk. It may be cached from a previous
      // run but deleted by flush() (e.g. when the server is stopped on app
      // pause and restarted on resume), so recreate it whenever missing.
      if (!_hostDir!.existsSync()) {
        _hostDir!.createSync(recursive: true);
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

  /// Asset key prefix under which the bundled viewer files live.
  static const String _viewerAssetPrefix =
      'packages/sqflite_live/sqlite_viewer/';

  /// Copies the bundled sqlite_viewer files out to [toPath].
  ///
  /// The viewer ships as plain Flutter assets (not a zip), so we read the
  /// asset manifest, take every key under [_viewerAssetPrefix] and write it to
  /// disk preserving the directory structure. This keeps the package free of
  /// any archive/zip dependency.
  Future<void> _extractAssets(String toPath) async {
    final Directory targetDir = Directory(toPath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final AssetManifest manifest =
        await AssetManifest.loadFromAssetBundle(rootBundle);
    final Iterable<String> assetKeys = manifest
        .listAssets()
        .where((key) => key.startsWith(_viewerAssetPrefix));

    for (final String key in assetKeys) {
      final String relativePath = key.substring(_viewerAssetPrefix.length);
      if (relativePath.isEmpty) continue;

      final File outFile = File(join(toPath, relativePath));
      await outFile.parent.create(recursive: true);

      final ByteData data = await rootBundle.load(key);
      await outFile.writeAsBytes(data.buffer
          .asUint8List(data.offsetInBytes, data.lengthInBytes));
    }
  }

  @override
  File get dbFile  {
    if(_dbPath == null) throw(_dbFileNotFoundFailure);
    return _dbPath!;
  }
}
