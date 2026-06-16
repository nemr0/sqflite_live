import 'package:sqflite_live/src/host/logger/log_me.dart';

/// A dependency-free [LogMe] that writes colored messages to the console.
///
/// Colors are emitted as ANSI escape codes; `[label](url)` markdown links
/// are rendered as clickable OSC 8 terminal hyperlinks.
class ILogMe extends LogMe {
  ILogMe(this.level);

  final LogLevel level;

  static const String _reset = '\x1B[0m';
  static const String _gray = '\x1B[90m';
  static const String _cyan = '\x1B[36m';
  static const String _yellow = '\x1B[33m';
  static const String _red = '\x1B[31m';

  void _log(LogLevel msgLevel, String prefix, String color, dynamic msg,
      {StackTrace? trace}) {
    if (level == LogLevel.off || msgLevel.index < level.index) return;
    final text = _markdownToHyperlinks(msg.toString());
    // ignore: avoid_print
    print('$color$prefix $text$_reset${trace != null ? '\n$trace' : ''}');
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

  /// Converts `[label](https://...)` markdown links into OSC 8 hyperlinks.
  String _markdownToHyperlinks(String msg) {
    final linkRE = RegExp(r'\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)');
    const esc = '\x1B';
    return msg.replaceAllMapped(linkRE, (m) {
      final label = m[1]!;
      final url = m[2]!;
      final open = '$esc]8;;$url$esc\\'; // OSC 8 ;; url ST
      final close = '$esc]8;;$esc\\'; // OSC 8 ;; ST
      return '$open$label$close';
    });
  }
}
