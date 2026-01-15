import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/app_logger.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const windowsSettings = WindowsInitializationSettings(
      appName: 'portal',
      appUserModelId: 'portal.portal.app.1.0',
      guid: '5d1b8c7f-2a4e-4c3d-9b6f-8e7a5d3c2b1a',
    );

    final initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      windows: defaultTargetPlatform == TargetPlatform.windows
          ? windowsSettings
          : null,
    );

    await _notifications.initialize(
      initializationSettings,
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
    // Android permissions are automatically granted at runtime
    // iOS requires explicit user permission request
    if (defaultTargetPlatform == TargetPlatform.android) {
      return true;
    }

    final result = await _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    return result ?? false;
  }
}
