// Language: dart
// File: `test/src/fake_http_overrides.dart`
import 'dart:io';

class RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    // Temporarily remove the global override to avoid recursion.
    final current = HttpOverrides.current;
    HttpOverrides.global = null;
    final client = HttpClient(context: context);
    HttpOverrides.global = current;
    return client;
  }
}