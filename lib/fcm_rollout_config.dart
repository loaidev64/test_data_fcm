/// Rollout configuration for the FCM data-message migration.
///
/// Phase 1: backend sends dual payload (notification + data) — app routing handles it.
/// Phase 2: set [deviceRegistrationUrl] so the app reports `appVersion` per token.
/// Phase 3: set [appUpdateCheckUrl] so outdated clients see an update prompt.
class FcmRolloutConfig {
  /// First app version that supports the data-only notification handler.
  static const minimumDataCapableVersion = '1.0.0';

  /// POST `{ fcmToken, appVersion }` — empty skips network (logs locally).
  static const deviceRegistrationUrl = String.fromEnvironment(
    'DEVICE_REGISTRATION_URL',
    defaultValue: '',
  );

  /// GET `?appVersion=` expecting `{ "requiresUpdate": bool }` — empty skips.
  static const appUpdateCheckUrl = String.fromEnvironment(
    'APP_UPDATE_CHECK_URL',
    defaultValue: '',
  );
}
