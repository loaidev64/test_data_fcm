import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:test_fcm/app_update_service.dart';
import 'package:test_fcm/notification_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Must be a top-level handler, registered before other async setup.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await NotificationHelper.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FCM Test',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'FCM Data Message Test'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  bool _requiresUpdate = false;

  @override
  void initState() {
    super.initState();
    _checkForRequiredUpdate();
  }

  Future<void> _checkForRequiredUpdate() async {
    final requiresUpdate = await AppUpdateService.checkRequiresUpdate();
    if (!mounted) return;
    if (requiresUpdate) {
      setState(() => _requiresUpdate = true);
    }
  }

  void _incrementCounter() async {
    final token = await FirebaseMessaging.instance.getToken();
    debugPrint('the token is: $token');
    setState(() => _counter++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          if (_requiresUpdate)
            MaterialBanner(
              content: const Text(
                'Please update the app to continue receiving push notifications.',
              ),
              leading: const Icon(Icons.system_update),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _requiresUpdate = false),
                  child: const Text('DISMISS'),
                ),
              ],
            ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Text('You have pushed the button this many times:'),
                  Text(
                    '$_counter',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Tap + to print FCM token.\n'
                      'Test rollout scenarios with:\n'
                      'dart run tool/send_fcm_data_message.dart --scenario dualPayload',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Print FCM token',
        child: const Icon(Icons.add),
      ),
    );
  }
}
