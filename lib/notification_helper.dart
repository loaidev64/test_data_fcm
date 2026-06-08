import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'device_registration_service.dart';
import 'fcm_message_router.dart';
import 'firebase_options.dart';

/// Top-level handler required for background/terminated FCM delivery on Android.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await NotificationHelper.ensureLocalNotificationsReady();
  await FcmMessageRouter.handle(message, isBackground: true);
}

class NotificationHelper {
  static final flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'my_channel_id_labib';
  static const _channelName = 'my_channel_id_labib_channel';

  static const _initializationSettingsAndroid =
      AndroidInitializationSettings('ic_launcher');

  static const _androidChannel = AndroidNotificationChannel(
    _channelId,
    _channelName,
    description: 'FCM data message notifications',
    importance: Importance.max,
  );

  static const _actionIds = <String>['approve_something', 'cancel'];

  static bool _localNotificationsReady = false;

  static Future<void> initialize() async {
    await ensureLocalNotificationsReady();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await _requestPermissions();
    await FirebaseMessaging.instance.subscribeToTopic('all');

    FirebaseMessaging.onMessage.listen(onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp
        .listen(FcmMessageRouter.handleNotificationOpen);

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      FcmMessageRouter.handleNotificationOpen(initialMessage);
    }

    await DeviceRegistrationService.registerCurrentDevice();
    DeviceRegistrationService.listenForTokenRefresh();
  }

  static Future<void> ensureLocalNotificationsReady() async {
    if (_localNotificationsReady) return;

    final darwinNotificationCategories = <DarwinNotificationCategory>[
      DarwinNotificationCategory(
        'default_actions',
        actions: _actionIds
            .map(
              (id) => DarwinNotificationAction.plain(
                id,
                _labelForAction(id),
                options: <DarwinNotificationActionOption>{
                  DarwinNotificationActionOption.foreground,
                },
              ),
            )
            .toList(),
      ),
    ];

    final initializationSettings = InitializationSettings(
      android: _initializationSettingsAndroid,
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestSoundPermission: true,
        requestBadgePermission: true,
        notificationCategories: darwinNotificationCategories,
      ),
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    _localNotificationsReady = true;
  }

  static Future<void> _requestPermissions() async {
    await FirebaseMessaging.instance.requestPermission();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static String _labelForAction(String actionId) {
    switch (actionId) {
      case 'approve_something':
        return 'Approve';
      case 'cancel':
        return 'Cancel';
      default:
        return actionId;
    }
  }

  static AndroidNotificationSound? _resolveAndroidSound(String? sound) {
    if (sound == null || sound.isEmpty) return null;
    if (sound.startsWith('http://') || sound.startsWith('https://')) {
      return UriAndroidNotificationSound(sound);
    }
    return RawResourceAndroidNotificationSound(sound);
  }

  static Future<
          ({ByteArrayAndroidBitmap bitmap, BigPictureStyleInformation style})?>
      _loadImageAssets(
    String? imageUrl,
    String title,
    String body,
  ) async {
    if (imageUrl == null || imageUrl.isEmpty) return null;

    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        final bitmap = ByteArrayAndroidBitmap(response.bodyBytes);
        return (
          bitmap: bitmap,
          style: BigPictureStyleInformation(
            bitmap,
            largeIcon: bitmap,
            contentTitle: title,
            summaryText: body,
            hideExpandedLargeIcon: true,
          ),
        );
      }
    } catch (_) {
      // Fallback to plain notification if image fails to load.
    }
    return null;
  }

  static List<String>? _parseActionIds(dynamic actionsValue) {
    if (actionsValue == null) return null;
    if (actionsValue is String && actionsValue.isNotEmpty) {
      return (jsonDecode(actionsValue) as List).cast<String>();
    }
    if (actionsValue is List) {
      return actionsValue.cast<String>();
    }
    return null;
  }

  static Future<void> showFromMessage(RemoteMessage message) async {
    final data = message.data;
    final String title = data['title'] ?? '';
    final String body = data['body'] ?? '';
    final String? imageUrl = data['image'];
    final String? sound = data['sound'];

    final imageAssets = await _loadImageAssets(imageUrl, title, body);

    final actionIds = _parseActionIds(data['actions']);

    final androidActions = actionIds
            ?.map(
              (id) => AndroidNotificationAction(
                id,
                _labelForAction(id),
                showsUserInterface: true,
              ),
            )
            .toList() ??
        <AndroidNotificationAction>[];

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _androidChannel.description,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: _resolveAndroidSound(sound),
      largeIcon: imageAssets?.bitmap,
      styleInformation: imageAssets?.style,
      actions: androidActions.isNotEmpty ? androidActions : null,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: sound,
      categoryIdentifier:
          actionIds != null && actionIds.isNotEmpty ? 'default_actions' : null,
    );

    await flutterLocalNotificationsPlugin.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: jsonEncode(data),
    );
  }

  /// Fallback for pre-migration notification-only payloads (no `data.title`/`data.body`).
  static Future<void> showFromLegacyNotification(RemoteMessage message) async {
    final notification = message.notification!;
    final title = notification.title ?? '';
    final body = notification.body ?? '';
    final imageUrl =
        notification.android?.imageUrl ?? notification.apple?.imageUrl;

    final imageAssets = await _loadImageAssets(imageUrl, title, body);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _androidChannel.description,
      importance: Importance.max,
      priority: Priority.high,
      largeIcon: imageAssets?.bitmap,
      styleInformation: imageAssets?.style,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await flutterLocalNotificationsPlugin.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: message.data.isNotEmpty ? jsonEncode(message.data) : null,
    );
  }

  static Future<void> onForegroundMessage(RemoteMessage message) async {
    await FcmMessageRouter.handle(message, isBackground: false);
  }

  static void onDidReceiveNotificationResponse(
    NotificationResponse notificationResponse,
  ) {
    final String? payload = notificationResponse.payload;
    if (payload != null) {
      debugPrint('notification payload: $payload');
    }
  }
}
