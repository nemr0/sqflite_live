/// Abstract class that defines the contract for binding an HTTP server.
///
/// Implementations of this class must provide methods to start and stop
/// the HTTP server.
abstract class HostBinder {
  /// Starts the server with the given [hostDirectory] used as the base for serving files.
  Future<void> startServer(String hostDirectory);

  /// Closes the running server and cleans up resources.
  Future<void> closeServer();

  /// Whether the server is currently bound and actually responding to
  /// requests. Used to decide if a stale server needs rebuilding after the
  /// app returns from the background.
  Future<bool> isAlive();

  /// Logs the URL(s) the server is reachable at. Called when the server starts
  /// and again when the app resumes onto a still-running server, so the address
  /// is always visible in the console.
  Future<void> logAddress();
}