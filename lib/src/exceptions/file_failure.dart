import 'package:sqflite_live/src/exceptions/failure_abs.dart';

class FileFailure extends Failure {
  const FileFailure(super.message, {super.stackTrace});

  @override
  bool operator ==(Object other) => identical(this, other) || other is FileFailure
      && runtimeType == other.runtimeType
      && message == other.message
      && stackTrace == other.stackTrace;

  @override
  int get hashCode => message.hashCode ^ stackTrace.hashCode;    

  @override
  String toString() => 'FileFailure{message: $message, stackTrace: $stackTrace}';
}
