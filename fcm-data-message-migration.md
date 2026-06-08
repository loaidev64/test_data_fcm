# FCM Data-Message Migration

## Overview

Migrate from FCM **notification** messages to **data-only** messages so the Flutter app has full control over how notifications are displayed, including custom sounds, images, and action buttons. In the old approach the OS automatically rendered the system tray notification from the `notification` block; in the new approach the app receives only key-value pairs inside `data` and is responsible for showing the local notification via `flutter_local_notifications`.

## Backend Payload Contract

### Old Payload (notification message)

```json
{
  "message": {
    "token": "REGISTRATION_TOKEN",
    "notification": {
      "title": "FCM API test",
      "body": "This is the body of the notification.",
      "image": "https://cat.10515.net/1.jpg"
    }
  }
}
```

### New Payload (data-only message)

```json
{
  "message": {
    "token": "bk3RNwTe3H0:CI2k_HHwgIpoDKCIZvvDMExUdFQ3P1...",
    "data": {
      "title": "FCM API test",
      "body": "This is the body of the notification.",
      "image": "https://cat.10515.net/1.jpg",
      "sound": "labib_audio",
      "actions": ["approve_something", "cancel"],
      "ticketId": "42",
      "link": "https://labib-edu.com"
    }
  }
}
```

### Field Mapping

| Field | Required | Old Location | New Location (`data.*`) | Notes |
|---|---|---|---|---|
| `title` | Yes | `notification.title` | `data.title` | Notification title |
| `body` | Yes | `notification.body` | `data.body` | Notification body |
| `image` | No | `notification.image` | `data.image` | Image URL for rich notification |
| `sound` | No | `notification.android.sound` | `data.sound` | Bundled resource name or remote URL |
| `actions` | No | — | `data.actions` | `List<String>` of action IDs (fixed set) |
| `ticketId`, `quizId`, `link`, etc. | No | `data.*` | `data.*` | Unchanged — already in `data` |

## Adjusted Sample Code

The snippet below is based on the provided sample and adapted to:

- Read every field from `message.data`.
- Handle **sound as a resource name or a remote URL**.
- Download notification images via **Dio** (`responseType: ResponseType.bytes`); do not use the `http` package for image bytes.
- Support **iOS** via `DarwinInitializationSettings` and pre-registered notification categories.
- Map action IDs to localized labels via ARB translations.
- Encode `message.data` as the notification payload so tap handlers retain all routing metadata.

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:dio/dio.dart';

import 'firebase_options.dart';

class NotificationHelper {
  static final flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const _initializationSettingsAndroid =
      AndroidInitializationSettings('ic_launcher');

  static const _initializationSettingsIos = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestSoundPermission: true,
    requestBadgePermission: true,
  );

  /// Fixed action IDs that the backend can send.
  static const _actionIds = <String>['approve_something', 'cancel'];

  static Future<void> initialize() async {
    // --- iOS categories (must be registered before plugin.initialize) ---
    final darwinNotificationCategories = <DarwinNotificationCategory>[
      DarwinNotificationCategory(
        'default_actions',
        actions: _actionIds
            .map(
              (id) => DarwinNotificationAction.plain(
                id,
                _labelForAction(id), // mapped to ARB key / translation
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

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await FirebaseMessaging.instance.requestPermission();

    FirebaseMessaging.onBackgroundMessage(onBackgroundMessage);
    FirebaseMessaging.onMessage.listen(onForegroundMessage);
  }

  static String _labelForAction(String actionId) {
    // TODO: replace with AppLocale.translation.approve_something / cancel
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

  static Future<BigPictureStyleInformation?> _loadImageFromNetwork(
    String? imageUrl,
    String title,
    String body,
  ) async {
    if (imageUrl == null || imageUrl.isEmpty) return null;

    try {
      final response = await Dio().get<List<int>>(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.statusCode == 200 && response.data != null) {
        final bigPicture = ByteArrayAndroidBitmap(Uint8List.fromList(response.data!));
        return BigPictureStyleInformation(
          bigPicture,
          contentTitle: title,
          summaryText: body,
        );
      }
    } catch (_) {
      // Fallback to plain notification if image fails to load.
    }
    return null;
  }

  static Future<void> _showNotification(RemoteMessage message) async {
    final data = message.data;
    final String title = data['title'] ?? '';
    final String body = data['body'] ?? '';
    final String? imageUrl = data['image'];
    final String? sound = data['sound'];
    final dynamic actionsValue = data['actions'];

    final bigPictureStyleInformation =
        await _loadImageFromNetwork(imageUrl, title, body);

    final List<String>? actionIds = actionsValue != null && actionsValue is String && actionsValue.isNotEmpty
        ? (jsonDecode(actionsValue) as List).cast<String>()
        : null;

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
      'my_channel_id_labib',
      'my_channel_id_labib_channel',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: _resolveAndroidSound(sound),
      styleInformation: bigPictureStyleInformation,
      actions: androidActions.isNotEmpty ? androidActions : null,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: sound,
      categoryIdentifier: actionIds != null && actionIds.isNotEmpty
          ? 'default_actions'
          : null,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      message.hashCode,
      title,
      body,
      notificationDetails,
      payload: jsonEncode(data),
    );
  }

  static Future<void> onForegroundMessage(RemoteMessage message) async {
    debugPrint('foreground message: ${message.toMap()}');
    await _showNotification(message);
  }

  static Future<void> onBackgroundMessage(RemoteMessage message) async {
    debugPrint('background message: ${message.toMap()}');
    await _showNotification(message);
  }

  static void onDidReceiveNotificationResponse(
    NotificationResponse notificationResponse,
  ) {
    final String? payload = notificationResponse.payload;
    if (payload != null) {
      debugPrint('notification payload: $payload');
      // TODO: parse payload and route to the correct screen
      // (ticketId, quizId, link, course_id, etc.)
    }
  }
}
```

## Integration Guide

### `lib/notification/messaging_service.dart`

1. Replace the current `onMessage` listener and `_firebaseMessagingBackgroundHandler` with the unified `_showNotification` logic.
2. Remove all branches that read from `message.notification` (e.g., `message.notification?.android?.imageUrl`, `message.notification?.android?.sound`).
3. Continue to use `message.data` for navigation metadata (`ticketId`, `quizId`, `questionId`, `link`, etc.) because those keys already live in `data`.
4. Keep `countNotificationUnread` increment logic in the foreground listener.

### `lib/notification/notification_core.dart`

1. Update `showLocalNotification` and `showLocalNotificationWithImage` signatures to optionally accept `List<String>? actions`.
2. Add the `_resolveAndroidSound` branching logic (resource name vs. remote URL).
3. In `initialize()`, register the fixed iOS notification categories before calling `flutterLocalNotifications.initialize(...)`.
4. Encode the full `message.data` map as JSON and pass it as `payload` to `flutterLocalNotifications.show(...)`.

### Existing Navigation Logic

Navigation based on `message.data` keys (`ticketId`, `quizId`, `questionId`, `link`, `course`, `course_id`) does **not** need to change because those fields are already in `data`. The only change is the source of `title`, `body`, `image`, and `sound`.

## Potential Issues & Mitigations

| Issue | Severity | Description | Mitigation |
|---|---|---|---|
| **Backward compatibility during rollout** | High | If the backend switches to data-only before all users update, old app versions won't display any notifications (they expect `message.notification`). | Coordinate a hard cutover, or implement a backend feature flag that sends both `notification` and `data` during a transition window. |
| **Testing complexity** | Medium | Firebase Console test messages typically send `notification` payloads. Testing data-only messages requires custom API calls or backend integration. | Provide backend team with a cURL example. Set up a staging endpoint for QA to trigger test data-only messages. |
| **Duplicate notifications** | Low | If both `notification` and `data` are sent during a transition, or if the background and foreground handlers both trigger, the user might see duplicates. | Ensure only one handler shows the local notification. During transition, old app versions should ignore duplicate `data` if `notification` is present. |
| **iOS background/terminated delivery** | High | Data-only FCM messages on iOS do **not** wake the app unless the backend includes `"aps": {"content-available": true}` in the APNs payload. Without this, users in background/terminated states will never see the notification. | Document the backend requirement to add `content-available: true` to the APNs payload. Test on physical iOS devices in both states. |
| **Message handling inconsistency** | High | Current code branches on `message.notification?.android?.imageUrl` and `message.notification?.android?.sound`. After migration, these will be `null`, causing all notifications to fall through to the text-only path and lose images/sounds. | Audit all references to `message.notification` in `messaging_service.dart` and `notification_core.dart`; replace with `message.data` extraction. |
| **Image loading failures** | Medium | Previously FCM SDK handled image downloading. Now the app downloads via HTTP. Network failure, timeout, or large images can cause the notification to fail or delay. | Add timeout to the Dio request, catch exceptions gracefully, and fallback to text-only notification if the image fails to load. |
| **Sound format mismatch** | Medium | If the backend sends a resource name but the app treats it as a URL (or vice versa), the notification will be silent or crash. | Implement robust detection: check if `sound` starts with `http://` or `https://`. Document the expected format clearly for the backend team. |
| **Action label missing** | Medium | If the backend sends a new action ID not mapped in the app, the button label will show the raw ID string instead of a localized label. | Maintain a strict allow-list of action IDs in the app. Reject unknown IDs or fallback to the ID string with a warning log. |
| **iOS action inflexibility** | Medium | iOS notification categories must be pre-registered at plugin initialization. Adding a new action ID requires an app update. | Keep the action set fixed and documented. If new actions are needed, they must go through an app release cycle. |
| **FCM data payload size limit** | Low | Data payloads have a 4KB limit. Moving all fields (including long image URLs and metadata) into `data` could approach this. | Keep image URLs short (use CDN with short paths). Monitor payload size during testing. |
| **Badge count on iOS** | Low | Previously FCM could manage the app badge automatically via `notification.badge`. With data-only, badge management is entirely manual. | Implement manual badge updates in the local notification details or via a separate push if needed. |

## Backward Compatibility During Rollout

### The Problem

Old app versions (pre-migration) expect `message.notification` to contain `title`, `body`, and `image`. If the backend switches to data-only payloads, these old versions will receive `message.notification == null` and will **not display any notification** to the user. This creates a silent failure where millions of users on older builds stop receiving push notifications entirely.

### Solution 1: Dual-Payload Transition Window (Recommended)

**Concept**: The backend sends **both** `notification` and `data` in the same FCM message for a defined transition period.

```json
{
  "message": {
    "token": "...",
    "notification": {
      "title": "FCM API test",
      "body": "This is the body of the notification.",
      "image": "https://cat.10515.net/1.jpg"
    },
    "data": {
      "title": "FCM API test",
      "body": "This is the body of the notification.",
      "image": "https://cat.10515.net/1.jpg",
      "sound": "labib_audio",
      "actions": ["approve_something", "cancel"],
      "ticketId": "42",
      "link": "https://labib-edu.com"
    }
  }
}
```

**How it works**:
- **Old app versions**: FCM SDK automatically displays the notification from the `notification` block. The app ignores `data` or uses it only for routing.
- **New app versions**: The app explicitly ignores `message.notification` and builds the local notification from `message.data`, giving full control over images, sounds, and actions.

**App-side handling to prevent duplicates**:

```dart
FirebaseMessaging.onMessage.listen((RemoteMessage message) {
  // New app: always prefer data-only path.
  // If both notification and data exist, still use data.
  if (message.data.containsKey('title') && message.data.containsKey('body')) {
    _showNotification(message); // data-only path
    return;
  }

  // Fallback for true legacy notification-only messages.
  if (message.notification != null) {
    // legacy fallback — can be removed after cutover
  }
});
```

**Pros**:
- Zero downtime for users.
- No backend logic needed to segment by app version.
- Simple to implement and rollback.

**Cons**:
- Slightly larger payload (duplicate title/body/image).
- FCM data payload limit (4KB) still applies to the combined payload.
- Old versions cannot benefit from new features (actions, custom sounds).

**Transition window duration**: Typically 2–4 weeks, or until app update adoption reaches >90% of active devices.

---

### Solution 2: App-Version-Aware Backend Targeting

**Concept**: The backend sends `notification` payloads to old app versions and `data` payloads to new app versions, based on a version identifier stored in the backend per device token.

**Implementation**:

1. **App sends version on token registration**:
   ```dart
   // During FCM token registration / update
   final packageInfo = await PackageInfo.fromPlatform();
   final version = '${packageInfo.version}+${packageInfo.buildNumber}';
   // POST /api/devices with { fcmToken, appVersion: version }
   ```

2. **Backend segments tokens by version**:
   - Query devices table for tokens where `appVersion >= '2.3.0'` → send `data`-only payload.
   - Query devices table for tokens where `appVersion < '2.3.0'` → send `notification` payload.

3. **Version cutoff**: Define a minimum version (e.g., `2.3.0`) that supports the new data-only handler.

**Pros**:
- Clean separation; no duplicate payload fields.
- Old users get exactly what they expect; new users get full features.

**Cons**:
- Requires backend schema change (`appVersion` column on devices table).
- Requires maintenance of version cutoff logic.
- Users who sideload or skip updates may still receive `notification` payloads indefinitely unless you enforce a hard deadline.

---

### Solution 3: Silent Data-Only + Legacy Notification Push (Hybrid)

**Concept**: Send a data-only message first. If the backend detects that the device has not acknowledged receipt within a timeout (or via a delivery report), send a follow-up legacy `notification` message.

**How it works**:
1. Backend sends `data`-only payload.
2. New app versions process it and optionally call an API to confirm receipt.
3. If no confirmation after X seconds, backend sends a second message with `notification` block.

**Pros**:
- Optimizes payload size for most users.
- Graceful degradation.

**Cons**:
- Complex backend logic with retries and state tracking.
- Increased FCM send volume and cost.
- Delayed delivery for old users.
- Not recommended unless cost/payload size is a critical constraint.

---

### Solution 4: Hard Cutover with In-App Banner

**Concept**: Stop sending `notification` payloads on a specific date. For old app versions, display an in-app banner urging them to update the app, because they will no longer receive push notifications.

**How it works**:
1. Backend switches exclusively to `data`.
2. Old app versions do not show notifications, but the next time the user opens the app, an API call returns a flag `requiresUpdate: true`.
3. App shows a blocking or non-blocking update dialog.

**Pros**:
- Cleanest backend payload; no dual fields or version logic.
- Forces user base to update quickly.

**Cons**:
- Users who do not open the app will never know they are missing notifications.
- Poor user experience; risk of user churn.
- Should only be used if the user base is small and highly engaged.

---

### Recommended Hybrid Approach

For the Labib app, the recommended rollout is **Solution 1 (Dual-Payload)** combined with **Solution 2 (Version Targeting)** as a later optimization:

1. **Phase 1 — Dual Payload (Weeks 1–4)**:
   - Backend sends both `notification` and `data` for **all** tokens.
   - New app version released to stores.
   - Monitor crashlytics and notification engagement.

2. **Phase 2 — Version Targeting (Week 5+)**:
   - Backend adds `appVersion` to the devices table.
   - New app versions start sending `appVersion` with token registration.
   - Backend begins sending `data`-only to known updated devices.
   - Devices without a registered version continue to receive dual payloads.

3. **Phase 3 — Hard Cutover (Week 8+)**:
   - Once >95% of active devices are on the new version, backend stops sending `notification`.
   - Remaining old versions fall back to the in-app update banner (Solution 4).

### App-Side Checklist for Dual-Payload Safety

- [ ] Ensure `FirebaseMessaging.onMessage` does **not** display a local notification when `message.notification` is present but `message.data['title']` is missing (avoids double notifications during transition).
- [ ] Ensure background handler (`FirebaseMessaging.onBackgroundMessage`) also checks for `message.data['title']` before showing a local notification.
- [ ] If both `notification` and `data` are present, the new app must **only** use the `data` path.
- [ ] Log an analytics event (`notification_received_data_only`) to verify the new path is being hit in production.

## Testing Plan

| Test | Expected Result |
|---|---|
| Foreground data-only message (no image, no sound) | Local notification displayed with title and body |
| Foreground data-only message with image | Local notification displayed with `BigPictureStyleInformation` |
| Foreground data-only message with sound (resource name) | Notification plays bundled sound |
| Foreground data-only message with sound (URL) | Notification plays remote sound (Android only) |
| Foreground data-only message with actions | Action buttons appear; tapping triggers `onDidReceiveNotificationResponse` |
| Background data-only message (Android) | Local notification displayed after app is backgrounded |
| Terminated state + tap notification (Android) | App launches and routes correctly based on payload |
| iOS background/terminated with `content-available: true` | Notification shown; without it, no notification |
| Missing optional fields (`image`, `sound`, `actions`) | Notification falls back gracefully to text-only, default sound, no actions |
| Payload size > 4KB | Backend should fail or truncate; test with realistic payload sizes |

## Rollout

1. **Backend**: add a feature flag to send either the old `notification` payload, the new `data` payload, or both.
2. **App**: release a version that can handle data-only messages (this document).
3. **Transition window**: send both `notification` and `data` so old and new app versions both work.
4. **Cutover**: once adoption is high, disable the `notification` block on the backend and rely solely on `data`.
