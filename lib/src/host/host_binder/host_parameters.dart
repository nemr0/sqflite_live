/// Represents the parameters for the host server.
///
/// Contains the port to bind the server and the database path used for file operations.
class HostParameters {
  /// Port number for the HTTP server.
  final int port;

  /// Path to the database used by the host.
  final String dbPath;

  /// Creates [HostParameters] with the required [dbPath] and [port].
  HostParameters({
    required this.dbPath,
    required this.port,
  });
}