part of 'server_value_notifier.dart';
class ServerState {
  const ServerState();

}
class ServerStateInitial extends ServerState {
  const ServerStateInitial();
}
class ServerStateStarting extends ServerState {
  const ServerStateStarting();
}
class ServerStateRunning extends ServerState {
  const ServerStateRunning(this.message);
  final String message;
}
class ServerStateStopped extends ServerState {
  const ServerStateStopped();
}
class ServerStateError extends ServerState {
  const ServerStateError(this.message);
  final Failure message;
}