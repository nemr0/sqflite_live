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
