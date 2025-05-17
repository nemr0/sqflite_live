import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:sqflite_live/src/host/file_manager/file_manager.dart';
import 'package:sqflite_live/src/host/file_manager/file_manager_impl.dart';
import 'package:sqflite_live/src/host/host_binder/host_binder.dart';
import 'package:sqflite_live/src/host/host_binder/host_binder_impl.dart';
import 'package:sqflite_live/src/host/host_binder/host_parameters.dart';
import 'package:sqflite_live/src/host/logger/log_me.dart';
import 'package:sqflite_live/src/host/logger/log_me_impl.dart';
import 'test_helpers/get_paths.dart';
import 'test_helpers/real_http_overrides.dart';

void main(){
  group('HostBinder', ()  {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = RealHttpOverrides();

    final FileManager fileManager = IFileManager();

    final File dbFile =getDbFileForTesting();
    final String hostDirectory = getHostDirectoryForTesting().path;

    final HostParameters hostParameters = HostParameters(dbPath: dbFile.path, port: 2231);
    final LogMe logger = ILogMe(Level.all);
    final HostBinder hostBinder = IHostBinder(hostParameters,logger);
    test('startServer', () async {
      await fileManager.prepareFiles(dbFile.path,hostDir: hostDirectory);
      hostBinder.startServer(hostDirectory);
      await Future.delayed(Duration(seconds: 1));

      // ping the server

      final HttpClientResponse response =await (await HttpClient().getUrl(Uri.parse('http://localhost:${hostParameters.port}'))).close();

      expect(response.statusCode == 200 || response.statusCode == 404, true,reason: 'Server did not start');
    });

    test('closeServer', () async {
      hostBinder.closeServer();
      // ping the server
      try {
        await (await HttpClient().getUrl(Uri.parse('http://localhost:${hostParameters.port}'))).close();
        fail('Server did not close');
      } catch (e) {
        expect(e.toString(), contains('Connection refused'),reason: 'Server did not close');
      }

    });
     fileManager.flush();
  });
}