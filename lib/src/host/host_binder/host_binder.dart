abstract class HostBinder{
  Future<void> startServer(String hostDirectory);
  Future<void> closeServer();
}