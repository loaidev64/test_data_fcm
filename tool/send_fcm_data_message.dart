// Developer-only CLI for sending data-only FCM messages via HTTP v1 API.
//
// Prerequisites:
//   1. Download service account JSON from Firebase Console (helpful-loai project).
//   2. Save as service-account.json at repo root (or pass --credentials).
//   3. Get device token from the app (tap FAB, check debug console).
//
// Usage:
//   dart run tool/send_fcm_data_message.dart --token <DEVICE_TOKEN> --scenario full
//   dart run tool/send_fcm_data_message.dart --token <TOKEN> --scenario basic --credentials .\service-account.json

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

const _defaultProjectId = 'helpful-loai';
const _fcmScope = 'https://www.googleapis.com/auth/firebase.messaging';

/// Preset payloads mapped to fcm-data-message-migration.md Testing Plan.
enum DataMessageScenario {
  basic,
  withImage,
  withSoundResource,
  withSoundUrl,
  withActions,
  full,
  dualPayload,
  notificationOnly,
}

extension DataMessageScenarioX on DataMessageScenario {
  static DataMessageScenario fromName(String name) {
    return DataMessageScenario.values.firstWhere(
      (s) => s.name == name,
      orElse: () => throw ArgumentError(
        'Unknown scenario "$name". '
        'Valid: ${DataMessageScenario.values.map((s) => s.name).join(', ')}',
      ),
    );
  }

  /// Base data fields shared across most scenarios.
  Map<String, String> get _baseData => {
        'title': 'FCM API test',
        'body': 'This is the body of the notification.',
      };

  /// Full data payload from the migration doc sample.
  Map<String, String> get _fullData => {
        ..._baseData,
        'image': 'https://cat.10515.net/1.jpg',
        // 'sound': 'labib_audio',
        'actions': jsonEncode(['approve_something', 'cancel']),
        'ticketId': '42',
        'link': 'https://labib-edu.com',
      };

  /// Returns the FCM `data` map (all values must be strings).
  Map<String, String> buildData() {
    switch (this) {
      case DataMessageScenario.basic:
        return _baseData;
      case DataMessageScenario.withImage:
        return {
          ..._baseData,
          'image': 'https://cat.10515.net/1.jpg',
        };
      case DataMessageScenario.withSoundResource:
        return {
          ..._baseData,
          'sound': 'labib_audio',
        };
      case DataMessageScenario.withSoundUrl:
        return {
          ..._baseData,
          'sound':
              'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
        };
      case DataMessageScenario.withActions:
        return {
          ..._baseData,
          'actions': jsonEncode(['approve_something', 'cancel']),
        };
      case DataMessageScenario.full:
      case DataMessageScenario.dualPayload:
        return _fullData;
      case DataMessageScenario.notificationOnly:
        // Routing metadata only — no title/body in data (legacy app path).
        return {'ticketId': '42', 'link': 'https://labib-edu.com'};
    }
  }

  /// Whether this scenario also includes a legacy `notification` block.
  bool get includesNotification =>
      this == DataMessageScenario.dualPayload ||
      this == DataMessageScenario.notificationOnly;
}

class FcmDataMessageSender {
  FcmDataMessageSender({
    required this.projectId,
    required this.credentialsPath,
  });

  final String projectId;
  final String credentialsPath;

  Future<void> send({
    required String token,
    required DataMessageScenario scenario,
  }) async {
    final credentialsFile = File(credentialsPath);
    if (!credentialsFile.existsSync()) {
      throw StateError(
        'Service account file not found: $credentialsPath\n'
        'Download from Firebase Console → Project Settings → Service accounts.',
      );
    }

    final accountJson =
        jsonDecode(credentialsFile.readAsStringSync()) as Map<String, dynamic>;
    final accountCredentials = ServiceAccountCredentials.fromJson(accountJson);

    final client = await clientViaServiceAccount(
      accountCredentials,
      [_fcmScope],
    );

    try {
      final accessToken = client.credentials.accessToken.data;
      final url = Uri.parse(
        'https://fcm.googleapis.com/v1/projects/$projectId/messages:send',
      );
      final body = _buildRequestBody(token: token, scenario: scenario);

      stdout.writeln('Sending scenario: ${scenario.name}');
      stdout.writeln('Project: $projectId');
      stdout.writeln(
          'Payload:\n${const JsonEncoder.withIndent('  ').convert(body)}');

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        stdout.writeln('\nSuccess! Message name: ${result['name']}');
      } else {
        stderr.writeln('\nFCM request failed (${response.statusCode}):');
        stderr.writeln(response.body);
        exitCode = 1;
      }
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> _buildRequestBody({
    required String token,
    required DataMessageScenario scenario,
  }) {
    final data = scenario.buildData();

    final message = <String, dynamic>{
      'token': token,
      'data': data,
      'android': {
        'priority': 'HIGH',
        'direct_boot_ok': true,
      },
      'apns': {
        'headers': {'apns-priority': '10'},
        'payload': {
          'aps': {'content-available': 1},
        },
      },
    };

    if (scenario.includesNotification) {
      message['notification'] = switch (scenario) {
        DataMessageScenario.notificationOnly => {
            'title': 'FCM API test',
            'body': 'This is the body of the notification.',
            'image': 'https://cat.10515.net/1.jpg',
          },
        _ => {
            'title': data['title'],
            'body': data['body'],
            if (data.containsKey('image')) 'image': data['image'],
          },
      };
    }

    return {'message': message};
  }
}

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'token',
      abbr: 't',
      help: 'FCM device registration token (required)',
      mandatory: true,
    )
    ..addOption(
      'scenario',
      abbr: 's',
      help: 'Test scenario preset',
      defaultsTo: DataMessageScenario.full.name,
    )
    ..addOption(
      'credentials',
      abbr: 'c',
      help: 'Path to Firebase service account JSON',
    )
    ..addOption(
      'project-id',
      abbr: 'p',
      help: 'Firebase project ID',
      defaultsTo: _defaultProjectId,
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage');

  late final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr
        .writeln('\nUsage: dart run tool/send_fcm_data_message.dart [options]');
    stderr.writeln(parser.usage);
    exitCode = 1;
    return;
  }

  if (results['help'] as bool) {
    stdout.writeln('Send data-only FCM test messages via HTTP v1 API.\n');
    stdout.writeln('Usage: dart run tool/send_fcm_data_message.dart [options]');
    stdout.writeln(parser.usage);
    stdout.writeln('\nScenarios:');
    for (final scenario in DataMessageScenario.values) {
      stdout.writeln('  ${scenario.name}');
    }
    return;
  }

  final credentialsPath = results['credentials'] as String? ??
      Platform.environment['FCM_SERVICE_ACCOUNT'] ??
      'service-account.json';

  late final DataMessageScenario scenario;
  try {
    scenario = DataMessageScenarioX.fromName(results['scenario'] as String);
  } on ArgumentError catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
    return;
  }

  final sender = FcmDataMessageSender(
    projectId: results['project-id'] as String,
    credentialsPath: credentialsPath,
  );

  try {
    await sender.send(
      token: results['token'] as String,
      scenario: scenario,
    );
  } catch (e) {
    stderr.writeln('Error: $e');
    exitCode = 1;
  }
}
