import 'dart:io';

bool isSupportedPlatform() {
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    return true;
  } else {
    return false;
  }
}