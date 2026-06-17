## 1.3.0

- The live server is now reachable by name at **`http://sqflite.local:<port>`** via a built-in mDNS (Bonjour / zeroconf) responder — no more copying the device IP on the same Wi‑Fi. Configurable through the new `live(localHostname:)` parameter; pass `''` to disable and advertise the IP only. (mDNS resolves only the `.local` TLD; iOS needs the multicast networking entitlement and Android a `MulticastLock` to receive queries, so the server also announces periodically.)
- Run on **port 80** (`live(port: 80)`) to get a clean **`http://sqflite.local`** with no port suffix. Privileged ports can't be bound on Android or desktop-without-admin, so the server now falls back to `8081` automatically (with a warning) instead of failing to start.
- The console logger no longer leaks raw ANSI escapes (e.g. `^[[36m`) when the output stream doesn't render them; colors/hyperlinks are emitted only in capable terminals.

## 1.2.1

- Removed the `logger`, `equatable` and `archive` dependencies (smaller bundle).
- The viewer can now **edit the live database** — non-`SELECT` statements run against the app's open connection. ⚠️ Any device that can reach the server can run arbitrary SQL; debug builds only.
- The viewer now **auto-refreshes**: changes made inside the app appear within ~2s without a manual page reload, keeping your current query in view.
- Fixed the advertised server URL on devices with VPN/cellular by preferring WiFi/Ethernet addresses; other candidates are logged as fallbacks.
- `live()` returns a `SqfliteLive` handle (`start`, `stop`, `ensureRunning`, `dispose`). With `autoRestart: true` (default) the server stays up in the background and is rebuilt on resume only if it stopped responding.
- **Breaking:** `live(level:)` now takes the package's own `LogLevel` enum instead of logger's `Level`.
- Updated dependencies to caret (`^`) constraints and bumped the minimum SDK to Dart 3.

## 1.0.2

- Restore full package.

## 1.0.1

- Logging improvements.

## 1.0.0

- Handled devices that doesn't support symbolic links.
- Minified sqlite_viewer (total package size: 12kb).
- added tests.

## 0.4.1

- Update README.md to include instructions for Android emulator port forwarding.

## 0.4.0

- Initial version.
