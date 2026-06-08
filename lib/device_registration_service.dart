import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'fcm_rollout_config.dart';

/// Phase 2: registers FCM token + app version so the backend can target payloads.
class DeviceRegistrationService {
  static Future<void> registerCurrentDevice() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) {
      debugPrint('device registration skipped: no FCM token');
      return;
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    final payload = {
      'fcmToken': token,
      'appVersion': appVersion,
    };

    if (FcmRolloutConfig.deviceRegistrationUrl.isEmpty) {
      debugPrint('device registration (local only): $payload');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(FcmRolloutConfig.deviceRegistrationUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      debugPrint(
        'device registration ${response.statusCode}: ${response.body}',
      );
    } catch (e) {
      debugPrint('device registration failed: $e');
    }
  }

  static void listenForTokenRefresh() {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      debugPrint('FCM token refreshed, re-registering device');
      await registerCurrentDevice();
    });
  }
}
