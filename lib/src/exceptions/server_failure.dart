import 'package:sqflite_live/src/exceptions/failure_abs.dart';

class ServerFailure extends Failure{
  ServerFailure(super.message,{super.stackTrace});

  @override
  List<Object?> get props => [];
}