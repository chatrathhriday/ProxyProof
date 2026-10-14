import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps attendance running with the screen locked or another app open.
///
/// Android only lets an app keep working in the background if it shows a notification
/// (a "foreground service"). The service itself does nothing: the BLE scan and the 10 s
/// reports keep running in the app's own isolate; the service just stops Android from
/// freezing or killing the process. Filtered BLE scans are allowed with the screen off.
class Background {
  static bool _ready = false;

  static void _init() {
    if (_ready) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'attendance',
        channelName: 'Attendance',
        channelDescription: 'Shown while ProxyProof is marking your attendance',
        // DEFAULT importance + vibration so a spot-check update actually buzzes the phone.
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.HIGH,
        enableVibration: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true, // CPU keeps running for the 10 s reports while the screen is off
      ),
    );
    _ready = true;
  }

  /// Asks for the notification permission (Android 13+) and to skip battery optimisation
  /// (Samsung and others otherwise pause background apps after a few minutes).
  static Future<void> requestPermissions() async {
    if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  static Future<void> start() async {
    _init();
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.connectedDevice],
      notificationTitle: 'ProxyProof is taking attendance',
      notificationText: 'You can lock your phone. Keep it with you in class.',
      callback: startCallback,
    );
  }

  static Future<void> update(String title, String text) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text);
  }

  static Future<void> stop() => FlutterForegroundTask.stopService();
}

// The package requires a task handler entry point; ours has nothing to do.
@pragma('vm:entry-point')
void startCallback() => FlutterForegroundTask.setTaskHandler(_IdleHandler());

class _IdleHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();
}
