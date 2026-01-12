import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    _isInitialized = true;

    developer.log(
      'Notification service initialized',
      name: 'portal.notification',
    );
  }

  void _onNotificationTap(NotificationResponse response) {
    developer.log(
      'Notification tapped: ${response.payload}',
      name: 'portal.notification',
    );
  }

  Future<void> showNewInstanceNotification({
    required int count,
    String? groupName,
  }) async {
    final title = count == 1 ? 'New Instance Opened' : 'New Instances Opened';
    final body = count == 1
        ? 'A new instance is now available'
        : '$count new instances are now available';

    const androidDetails = AndroidNotificationDetails(
      'group_instances',
      'Group Instances',
      channelDescription: 'Notifications for new group instances',
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
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      notificationDetails,
      payload: 'new_instances',
    );

    developer.log(
      'Showed notification: $title - $body',
      name: 'portal.notification',
    );
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
    developer.log(
      'Cancelled all notifications',
      name: 'portal.notification',
    );
  }

  Future<bool> get hasPermission async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return true;
    }

    final result = await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

    return result ?? false;
  }
}
