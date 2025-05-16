import 'package:sqflite_live/src/exceptions/failure_abs.dart';

class FileFailure extends Failure {
  const FileFailure(final String message, {final StackTrace? stackTrace}) : super(message,stackTrace: stackTrace);
  @override
  List<Object?> get props => [message];

  @override
  String toString() => 'FileFailure{message: $message, stackTrace: $stackTrace}';
}
