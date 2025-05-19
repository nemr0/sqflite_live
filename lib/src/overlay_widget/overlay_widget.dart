import 'package:flutter/material.dart';
import 'package:sqflite_live/src/overlay_widget/server_value_notifier.dart';
class SqfliteLiveStats extends StatelessWidget {
  const SqfliteLiveStats({Key? key, required this.child}): super(key: key);
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        ValueListenableBuilder(valueListenable: serverState,
        builder: (BuildContext context, ServerState value, _) {
          return SizedBox();
        },
        ),
      ],
    );
  }
}

