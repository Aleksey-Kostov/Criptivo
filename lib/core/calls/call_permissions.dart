import 'package:permission_handler/permission_handler.dart';

import 'call_models.dart';

class CallPermissions {
  /// Връща true ако нужните permission-и са granted.
  static Future<bool> ensure(CallKind kind) async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return false;

    if (kind == CallKind.video) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) return false;
    }
    return true;
  }

  static Future<bool> has(CallKind kind) async {
    final mic = await Permission.microphone.status;
    if (!mic.isGranted) return false;
    if (kind == CallKind.video) {
      final cam = await Permission.camera.status;
      if (!cam.isGranted) return false;
    }
    return true;
  }
}