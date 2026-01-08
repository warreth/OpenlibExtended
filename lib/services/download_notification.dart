// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloadNotificationService {
  static final DownloadNotificationService _instance =
      DownloadNotificationService._internal();
  factory DownloadNotificationService() => _instance;
  DownloadNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;

    final status = await Permission.notification.status;
    if (status.isGranted) {
      return true;
    }

    final result = await Permission.notification.request();
    return result.isGranted;
  }

  Future<bool> checkNotificationPermission() async {
    if (!Platform.isAndroid) return true;

    final status = await Permission.notification.status;
    return status.isGranted;
  }

  Future<void> initialize() async {
    if (_initialized) return;

    if (Platform.isAndroid) {
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/launcher_icon');

      const InitializationSettings initSettings =
          InitializationSettings(android: androidSettings);

      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );

      _initialized = true;
    }
  }

  void _onNotificationTap(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
  }

  Future<void> showDownloadNotification({
    required int id,
    required String title,
    String? body,
    required int progress,
  }) async {
    if (!_initialized || !Platform.isAndroid) return;

    AndroidNotificationDetails androidDetails;

    if (progress >= 0 && progress < 100) {
      androidDetails = AndroidNotificationDetails(
        'download_channel',
        'Downloads',
        channelDescription: 'Book download progress notifications',
        importance: Importance.low,
        priority: Priority.low,
        showProgress: true,
        maxProgress: 100,
        progress: progress,
        ongoing: true,
        autoCancel: false,
        playSound: false,
        enableVibration: false,
        icon: '@mipmap/launcher_icon',
        styleInformation: BigTextStyleInformation(
          body ?? '',
          contentTitle: title,
        ),
      );
    } else {
      androidDetails = AndroidNotificationDetails(
        'download_channel',
        'Downloads',
        channelDescription: 'Book download progress notifications',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: false,
        autoCancel: true,
        playSound: progress == -1,
        enableVibration: false,
        icon: '@mipmap/launcher_icon',
        styleInformation: BigTextStyleInformation(
          body ?? '',
          contentTitle: title,
        ),
      );
    }

    NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      id,
      title,
      body,
      notificationDetails,
    );
  }

  Future<void> cancelNotification(int id) async {
    if (!_initialized) return;
    await _notificationsPlugin.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    if (!_initialized) return;
    await _notificationsPlugin.cancelAll();
  }
}
