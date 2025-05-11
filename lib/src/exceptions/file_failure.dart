import 'package:sqflite_live/src/exceptions/failure_abs.dart';

class FileFailure extends Failure {
  const FileFailure(super.message, {super.stackTrace});
  @override
  List<Object?> get props => [message];

  @override
  String toString() => 'FileFailure{message: $message, stackTrace: $stackTrace}';
}
