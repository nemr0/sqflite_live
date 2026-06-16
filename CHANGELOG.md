## 1.2.1

- Removed the `logger`, `equatable` and `archive` dependencies.
- Fixed the advertised server URL on devices with a VPN or cellular connection: WiFi/Ethernet addresses are now preferred over VPN/cellular/AWDL interfaces (which other devices on the LAN can't reach), and any additional candidate addresses are logged as fallbacks.
- `live()` now returns a `SqfliteLive` handle with `start()`, `stop()`, `ensureRunning()` and `dispose()` for explicit control of the server lifecycle. By default (`autoRestart: true`) the server is left running when the app is backgrounded; when the app returns to the foreground the handle probes it with a loopback request and rebuilds it only if it stopped responding. Pass `autoRestart: false` to opt out.
- The host directory is now recreated on every server start, fixing a `PathNotFoundException` when the server was rebuilt (e.g. on app resume) after a previous stop had deleted it.
- Replaced logger's `Level` with a built-in `LogLevel` enum (`debug`, `info`, `warning`, `error`, `off`), exported from the package. **Breaking:** update `live(level: Level.x)` calls to `live(level: LogLevel.x)`.
- Updated remaining dependencies to their latest versions and switched to caret (`^`) version constraints.
- Bumped the minimum SDK to Dart 3 (`sdk: ^3.0.0`).

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
