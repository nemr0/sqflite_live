import 'dart:io' show stdout;

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:sqflite_live/src/host/logger/log_me.dart';

/// A dependency-free [LogMe] that writes colored messages via [debugPrint].
///
/// [debugPrint] is the Flutter-friendly console sink (throttled, stripped from
/// release builds). Colors are emitted as ANSI escape codes and `[label](url)`
/// markdown links as clickable OSC 8 terminal hyperlinks — but only when the
/// output stream actually interprets them. When stdout is a pipe or a console
/// that doesn't (e.g. some IDE debug consoles, or `flutter run`'s forwarded
/// output), plain text is emitted instead so raw `\x1B[..m` escapes never leak.
class ILogMe extends LogMe {
  ILogMe(this.level);

  final LogLevel level;

  /// Whether the current output stream renders ANSI escape sequences.
  static final bool _supportsAnsi = _detectAnsiSupport();

  static bool _detectAnsiSupport() {
    try {
      return stdout.supportsAnsiEscapes;
    } catch (_) {
      // stdout may be unavailable on some embeddings; assume no ANSI.
      return false;
    }
  }

  static const String _reset = '\x1B[0m';
  static const String _gray = '\x1B[90m';
  static const String _cyan = '\x1B[36m';
  static const String _yellow = '\x1B[33m';
  static const String _red = '\x1B[31m';

  void _log(LogLevel msgLevel, String prefix, String color, dynamic msg,
      {StackTrace? trace}) {
    if (level == LogLevel.off || msgLevel.index < level.index) return;
    final text = _formatLinks(msg.toString());
    final suffix = trace != null ? '\n$trace' : '';
    if (_supportsAnsi) {
      debugPrint('$color$prefix $text$_reset$suffix');
    } else {
      debugPrint('$prefix $text$suffix');
    }
  }

  @override
  void data(dynamic msg) => _log(LogLevel.debug, '🐛', _gray, msg);

  @override
  void info(dynamic msg) => _log(LogLevel.info, 'ℹ️', _cyan, msg);

  @override
  void warning(dynamic msg) => _log(LogLevel.warning, '⚠️', _yellow, msg);

  @override
  void error(dynamic msg, {StackTrace? trace}) =>
      _log(LogLevel.error, '⛔', _red, msg, trace: trace);

  /// Renders `[label](https://...)` markdown links as OSC 8 terminal
  /// hyperlinks when ANSI is supported, or as plain `label (url)` otherwise.
  String _formatLinks(String msg) {
    final linkRE = RegExp(r'\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)');
    const esc = '\x1B';
    return msg.replaceAllMapped(linkRE, (m) {
      final label = m[1]!;
      final url = m[2]!;
      if (!_supportsAnsi) return '$label ($url)';
      final open = '$esc]8;;$url$esc\\'; // OSC 8 ;; url ST
      final close = '$esc]8;;$esc\\'; // OSC 8 ;; ST
      return '$open$label$close';
    });
  }
}
