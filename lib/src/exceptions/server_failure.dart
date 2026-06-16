import 'package:sqflite_live/src/exceptions/failure_abs.dart';

class ServerFailure extends Failure{
 const ServerFailure(super.message,{super.stackTrace});

  @override 
  bool operator ==(Object other) => identical(this, other) || other is ServerFailure && runtimeType == other.runtimeType && message == other.message && stackTrace == other.stackTrace;
  @override
  int get hashCode => message.hashCode ^ stackTrace.hashCode;

  @override
  String toString() => 'ServerFailure{message: $message, stackTrace: $stackTrace}';
}