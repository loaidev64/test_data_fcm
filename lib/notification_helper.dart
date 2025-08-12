import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';

class NotificationHelper {
  static final flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static const initializationSettingsAndroid =
      AndroidInitializationSettings('ic_launcher');
  static const initializationSettingsIos = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestSoundPermission: true,
  );

  static Future<void> initialize() async {
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIos,
    );
    await flutterLocalNotificationsPlugin.initialize(initializationSettings,
        onDidReceiveNotificationResponse: onDidReceiveNotificationResponse);
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await FirebaseMessaging.instance.requestPermission();

    FirebaseMessaging.onBackgroundMessage(onBackgroundMessage);
    FirebaseMessaging.onMessage.listen(onBackgroundMessage);
  }

  static Future<BigPictureStyleInformation?> _loadImageFromNetwork(String? imageUrl, String title, String body) async {
    if(imageUrl == null) return null;

    final response = await http.get(Uri.parse(imageUrl));
    if (response.statusCode == 200) {
      final bigPicture = ByteArrayAndroidBitmap(response.bodyBytes);
      return BigPictureStyleInformation(
        bigPicture,
        contentTitle: title,
        summaryText: body,
      );
    } else {
      throw Exception('فشل في تحميل الصورة من الإنترنت');
    }
  }

  static Future<void> onBackgroundMessage(RemoteMessage message) async {
    debugPrint('notification message: ${message.toMap()}');
    final String title = message.data['title'];
    final String body = message.data['body'];
    final String? imageUrl = message.data['image'];
    final bigPictureStyleInformation = await _loadImageFromNetwork(imageUrl, title, body);

    flutterLocalNotificationsPlugin.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'channelId',
          'channelName',
          styleInformation: bigPictureStyleInformation,
        ),
      ),
    );
  }

  static void onDidReceiveNotificationResponse(
      NotificationResponse notificationResponse) async {
    final String? payload = notificationResponse.payload;
    if (notificationResponse.payload != null) {
      debugPrint('notification payload: $payload');
    }
  }
}
