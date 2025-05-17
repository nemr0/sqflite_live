import 'dart:io';

File getDbFileForTesting(){
  final File dbFile = File('${Directory.systemTemp.path}/test.db');
  if(dbFile.existsSync() == false) {
    dbFile.createSync();
  }
  return dbFile;
}

Directory getHostDirectoryForTesting(){
  final  hostDirectory = Directory('${Directory.systemTemp.path}/host_directory');
  if(hostDirectory.existsSync() == false) {
    hostDirectory.createSync();
  }
  return hostDirectory;
}