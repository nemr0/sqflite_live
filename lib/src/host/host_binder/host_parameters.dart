/// Represents the parameters for the host server.
///
/// Contains the port to bind the server and the database path used for file operations.
class HostParameters {
  /// Port number for the HTTP server.
  final int port;

  /// Path to the database used by the host.
  final String dbPath;

  /// The `*.local` hostname to publish over mDNS so the server is reachable by
  /// name (e.g. `http://sqflite.local:$port`). An empty string disables mDNS
  /// and falls back to advertising the IP only.
  final String localHostname;

  /// Creates [HostParameters] with the required [dbPath] and [port].
  HostParameters({
    required this.dbPath,
    required this.port,
    this.localHostname = 'sqflite.local',
  });
}