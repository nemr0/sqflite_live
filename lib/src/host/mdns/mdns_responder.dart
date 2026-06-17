/// Publishes a `*.local` hostname over multicast DNS (mDNS / Bonjour /
/// zeroconf) so browsers on the same LAN can open the live server by name —
/// e.g. `http://sqflite.local:8081` — instead of memorising a raw IP.
///
/// mDNS only resolves names under the reserved `.local` TLD, and only the
/// device hosting the server can answer for its own name. Resolution is a
/// convenience layered on top of the IP URL: if it can't start (or the client
/// platform filters multicast), the IP URL still works.
abstract class MdnsResponder {
  /// Opens the multicast socket, starts answering A-record queries for the
  /// hostname, and sends an initial burst of unsolicited announcements so
  /// resolvers can cache the address without ever querying.
  Future<void> start();

  /// Re-announces the current address. Called after the app resumes, since the
  /// device's LAN IP may have changed while it was suspended.
  Future<void> announce();

  /// Stops responding and releases the multicast socket.
  Future<void> stop();
}
