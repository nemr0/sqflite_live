import 'package:sqflite_live/src/exceptions/failure_abs.dart';

class ServerFailure extends Failure{
 const ServerFailure(final String message,{final StackTrace? stackTrace}) : super(message,stackTrace: stackTrace);

  @override
  List<Object?> get props => [];
}