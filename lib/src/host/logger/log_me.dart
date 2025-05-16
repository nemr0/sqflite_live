abstract class LogMe{
  void info(dynamic msg);
  void data(dynamic msg);
  void warning(dynamic msg);
  void error(dynamic msg, {StackTrace? trace});

}