## 1.2.1

- Removed the `logger` dependency; logging now uses a built-in, dependency-free colored console printer.
- Removed the `equatable` dependency.
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
