/// Severity levels for [LogMe], ordered from most to least verbose.
///
/// Setting a level suppresses every message below it. [LogLevel.off]
/// silences all output.
enum LogLevel { debug, info, warning, error, off }

abstract class LogMe {
  void info(dynamic msg);
  void data(dynamic msg);
  void warning(dynamic msg);
  void error(dynamic msg, {StackTrace? trace});
}
