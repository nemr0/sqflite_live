import 'package:logger/logger.dart';
import 'package:sqflite_live/src/host/logger/log_me.dart';

class ILogMe extends LogMe{
  final Level level;
  ILogMe(this.level){
   _logger = Logger(printer: PrettyPrinter(),level: level);
  }
  late final Logger _logger;
  @override
  void data(dynamic msg) {
   _logger.d(msg);
  }

  @override
  void error(dynamic msg, {StackTrace? trace}) {
    _logger.f(msg,stackTrace: trace);
  }

  @override
  void info(dynamic msg) {
   _logger.i(msg);
  }

  @override
  void warning(dynamic msg) {
   _logger.w(msg);
  }
}
/// matches [label](https://...)
class _MarkdownLinkPrinter extends LogPrinter {
  final LogPrinter _inner = PrettyPrinter();
  _MarkdownLinkPrinter();

  @override
  List<String> log(LogEvent event) {
    // render with inner printer, then post-process each line
    return _inner
        .log(event)
        .map(markdownToHyperlinks)
        .toList();
  }

  String markdownToHyperlinks(String msg) {
    final linkRE = RegExp(r'\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)');
    const esc = '\x1B';
    return msg.replaceAllMapped(linkRE, (m) {
      final label = m[1]!;
      final url   = m[2]!;
      final open  = '$esc]8;;$url$esc\\';  // OSC 8 ;; url ST
      final close = '$esc]8;;$esc\\';      // OSC 8 ;; ST
      return '$open$label$close';
    });
  }
}