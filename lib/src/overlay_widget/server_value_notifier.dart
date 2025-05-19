import 'package:flutter/cupertino.dart' show ValueNotifier;
import 'package:sqflite_live/src/exceptions/failure_abs.dart';
part 'package:sqflite_live/src/overlay_widget/server_states.dart';
final serverState = ValueNotifier<ServerState>(ServerStateInitial());
