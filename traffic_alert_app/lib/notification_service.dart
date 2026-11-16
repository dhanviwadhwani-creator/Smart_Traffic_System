import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(settings: settings);

    // Android 13+ ke liye permission maangta hai
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> showHeavyTrafficAlert(String address) async {
    const androidDetails = AndroidNotificationDetails(
      'heavy_traffic_channel',
      'Heavy Traffic Alerts',
      channelDescription: 'Alerts for heavy traffic reports',
      importance: Importance.max,
      priority: Priority.high,
    );

    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Heavy Traffic Alert 🚨',
      body: 'Heavy traffic reported at $address',
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
  }
}