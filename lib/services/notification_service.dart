import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/app_logger.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const _windowsAppName = 'portal';
  static const _windowsAppUserModelId = 'portal.portal.app.1.0';
  static const _windowsGuid = '5d1b8c7f-2a4e-4c3d-9b6f-8e7a5d3c2b1a';
  static const _androidIcon = '@mipmap/ic_launcher';
  static const _androidChannelId = 'group_instances';
  static const _androidChannelName = 'Group Instances';
  static const _androidChannelDescription =
      'Notifications for new group instances';
  static const _notificationPayloadNewInstances = 'new_instances';

  int _notificationCounter = 0;

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings(_androidIcon);

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const windowsSettings = WindowsInitializationSettings(
      appName: _windowsAppName,
      appUserModelId: _windowsAppUserModelId,
      guid: _windowsGuid,
    );

    final initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      windows: defaultTargetPlatform == TargetPlatform.windows
          ? windowsSettings
          : null,
    );

    await _notifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    _isInitialized = true;

    AppLogger.info(
      'Notification service initialized',
      subCategory: 'notification',
    );
  }

  void _onNotificationTap(NotificationResponse response) {
    AppLogger.info(
      'Notification tapped: ${response.payload}',
      subCategory: 'notification',
    );
  }

  Future<void> showNewInstanceNotification({required int count}) async {
    final title = count == 1 ? 'New Instance Opened' : 'New Instances Opened';
    final body = count == 1
        ? 'A new instance is now available'
        : '$count new instances are now available';

    const androidDetails = AndroidNotificationDetails(
      _androidChannelId,
      _androidChannelName,
      channelDescription: _androidChannelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      showWhen: true,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _notifications.show(
      id:
          DateTime.now().millisecondsSinceEpoch ~/ 1000 +
          (_notificationCounter++),
      title: title,
      body: body,
      notificationDetails: notificationDetails,
      payload: _notificationPayloadNewInstances,
    );

    AppLogger.info(
      'Showed notification: $title - $body',
      subCategory: 'notification',
    );
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
    AppLogger.info('Cancelled all notifications', subCategory: 'notification');
  }

  Future<bool> get hasPermission async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return true;
      case TargetPlatform.iOS:
        final result = await _notifications
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);

        return result ?? false;
      case TargetPlatform.macOS:
        final result = await _notifications
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);

        return result ?? false;
      default:
        return false;
    }
  }
}
