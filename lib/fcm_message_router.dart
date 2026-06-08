import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_helper.dart';

/// Routes incoming FCM messages during rollout.
///
/// When `data.title` and `data.body` are present the app **always** builds the
/// tray notification from `data`, even if `message.notification` is also set.
/// Legacy fallback is only used when the payload has a `notification` block but
/// no displayable `data.title`/`data.body`.
class FcmMessageRouter {
  static bool hasDataTitleAndBody(RemoteMessage message) {
    final title = message.data['title'];
    final body = message.data['body'];
    return title != null &&
        body != null &&
        title.toString().isNotEmpty &&
        body.toString().isNotEmpty;
  }

  static bool isDualPayload(RemoteMessage message) {
    return message.notification != null && hasDataTitleAndBody(message);
  }

  static Future<void> handle(
    RemoteMessage message, {
    required bool isBackground,
  }) async {
    debugPrint(
      'fcm route (${isBackground ? 'background' : 'foreground'}): '
      '${message.toMap()}',
    );

    if (hasDataTitleAndBody(message)) {
      if (isDualPayload(message)) {
        _logAnalytics('notification_received_dual_payload');
      } else {
        _logAnalytics('notification_received_data_only');
      }
      await NotificationHelper.showFromMessage(message);
      return;
    }

    if (message.notification != null) {
      if (isBackground) {
        _logAnalytics('notification_deferred_to_system');
        debugPrint(
          'deferred to system tray (notification block, no data title/body)',
        );
        return;
      }

      _logAnalytics('notification_received_legacy');
      await NotificationHelper.showFromLegacyNotification(message);
      return;
    }

    debugPrint('fcm message ignored: no displayable payload');
  }

  static void handleNotificationOpen(RemoteMessage message) {
    debugPrint('notification opened, routing data: ${message.data}');
    if (message.data.isNotEmpty) {
      debugPrint('notification payload: ${message.data}');
    }
  }

  static void _logAnalytics(String event) {
    debugPrint('analytics: $event');
  }
}
