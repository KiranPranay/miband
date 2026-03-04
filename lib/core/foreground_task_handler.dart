import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Minimal keep-alive task handler.
/// The BLE connection lives on the main isolate in BLEManager;
/// this handler simply prevents Android from killing the process.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BandForegroundHandler());
}

class BandForegroundHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Keep-alive tick — nothing to do; the BLE stack is on the main isolate.
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
