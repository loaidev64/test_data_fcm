import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'fcm_rollout_config.dart';

/// Phase 3: checks whether this build should prompt the user to update.
class AppUpdateService {
  static Future<bool> checkRequiresUpdate() async {
    if (FcmRolloutConfig.appUpdateCheckUrl.isEmpty) {
      return false;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final uri = Uri.parse(FcmRolloutConfig.appUpdateCheckUrl).replace(
        queryParameters: {'appVersion': packageInfo.version},
      );

      final response = await http.get(uri);
      if (response.statusCode != 200) {
        debugPrint('update check failed: ${response.statusCode}');
        return false;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['requiresUpdate'] == true;
    } catch (e) {
      debugPrint('update check error: $e');
      return false;
    }
  }
}
