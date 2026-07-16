import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:layrz_icons/layrz_icons.dart';
import 'package:layrz_push/layrz_push.dart';
import 'package:layrz_theme/layrz_theme.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Layrz Push Lab',
      theme: generateLightTheme(),
      darkTheme: generateDarkTheme(),
      themeMode: .system,
      builder: (context, child) {
        return ThemedSnackbarMessenger(child: child ?? const SizedBox());
      },
      home: const HomeView(),
    );
  }
}

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final _plugin = LayrzPush();

  bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  String _apiKey = '';
  String _appId = '';
  String _projectId = '';
  String _messagingSenderId = '';
  String _storageBucket = '';
  String _deviceId = '';

  StreamSubscription<PushNotification>? _subscription;
  final List<PushNotification> _notifications = [];
  List<String> _topics = [];
  PermissionStatus? _permissionStatus;
  bool _secretsLoaded = false;

  @override
  void initState() {
    super.initState();
    _subscription = _plugin.onPush.listen((notification) {
      setState(() => _notifications.insert(0, notification));
    });
    _loadSecrets();
    _checkPermission();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// The credentials are plain text fields by default, but they can be
  /// overriden by an `assets/secrets.json` file (gitignored), see
  /// `assets/secrets.example.json` for the expected format.
  Future<void> _loadSecrets() async {
    String raw;
    try {
      raw = await rootBundle.loadString('assets/secrets.json');
    } catch (_) {
      // No secrets.json bundled, keep the plain text fields.
      return;
    }

    try {
      final secrets = jsonDecode(raw) as Map<String, dynamic>;
      final platform = secrets[_isIos ? 'ios' : 'android'] as Map<String, dynamic>?;

      setState(() {
        _deviceId = secrets['deviceId'] as String? ?? '';
        _apiKey = platform?['apiKey'] as String? ?? '';
        _appId = platform?['appId'] as String? ?? '';
        _projectId = platform?['projectId'] as String? ?? '';
        _messagingSenderId = platform?['messagingSenderId'] as String? ?? '';
        _storageBucket = platform?['storageBucket'] as String? ?? '';
        _secretsLoaded = true;
      });
    } catch (e) {
      debugPrint('Invalid secrets.json: $e');
    }
  }

  Future<void> _checkPermission() async {
    final status = await Permission.notification.status;
    setState(() => _permissionStatus = status);
  }

  Future<void> _requestPermission() async {
    final status = await Permission.notification.request();
    setState(() => _permissionStatus = status);
  }

  void _showResult(String action, bool result) {
    if (!mounted) return;
    ThemedSnackbarMessenger.of(context).showSnackbar(
      ThemedSnackbar(
        message: '$action: ${result ? 'success' : 'failed'}',
        color: result ? Colors.green : Colors.red,
        icon: result ? LayrzIcons.solarOutlineCheckSquare : LayrzIcons.solarOutlineCloseSquare,
      ),
    );
  }

  Future<void> _setCredentials() async {
    final storageBucket = _storageBucket.isEmpty ? null : _storageBucket;

    final credentials = PushCredentials(
      android: _isIos
          ? null
          : AndroidPushCredentials(
              apiKey: _apiKey,
              appId: _appId,
              projectId: _projectId,
              messagingSenderId: _messagingSenderId,
              storageBucket: storageBucket,
            ),
      ios: _isIos
          ? IosPushCredentials(
              apiKey: _apiKey,
              appId: _appId,
              projectId: _projectId,
              messagingSenderId: _messagingSenderId,
              storageBucket: storageBucket,
            )
          : null,
    );

    final result = await _plugin.setCredentials(credentials: credentials);
    _showResult('setCredentials', result);
  }

  Future<void> _setDeviceId() async {
    final result = await _plugin.setDeviceId(deviceId: _deviceId);
    _showResult('setDeviceId', result);
  }

  Future<void> _subscribe() async {
    final result = await _plugin.subscribe();
    _showResult('subscribe', result);
    await _getSubscriptions();
  }

  Future<void> _unsubscribe() async {
    final result = await _plugin.unsubscribe();
    _showResult('unsubscribe', result);
    await _getSubscriptions();
  }

  Future<void> _getSubscriptions() async {
    final topics = await _plugin.getSubscriptions();
    setState(() => _topics = topics);
  }

  @override
  Widget build(BuildContext context) {
    final platformName = _isIos ? 'iOS' : 'Android';

    return Scaffold(
      appBar: AppBar(title: const Text('Layrz Push Lab')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(context, 'Notification permission'),
          Row(
            children: [
              Expanded(child: Text('Status: ${_permissionStatus?.name ?? 'unknown'}')),
              ThemedButton(
                labelText: 'Request',
                icon: LayrzIcons.solarOutlineInfoCircle,
                onTap: _requestPermission,
              ),
            ],
          ),
          const Divider(height: 32),
          _section(context, '$platformName credentials'),
          if (_secretsLoaded)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Loaded from assets/secrets.json', style: TextStyle(fontStyle: FontStyle.italic)),
            ),
          ThemedTextInput(
            labelText: 'API Key',
            value: _apiKey,
            onChanged: (value) => _apiKey = value,
          ),
          const SizedBox(height: 10),
          ThemedTextInput(
            labelText: 'App ID',
            value: _appId,
            onChanged: (value) => _appId = value,
          ),
          const SizedBox(height: 10),
          ThemedTextInput(
            labelText: 'Project ID',
            value: _projectId,
            onChanged: (value) => _projectId = value,
          ),
          const SizedBox(height: 10),
          ThemedTextInput(
            labelText: 'Messaging Sender ID',
            value: _messagingSenderId,
            onChanged: (value) => _messagingSenderId = value,
          ),
          const SizedBox(height: 10),
          ThemedTextInput(
            labelText: 'Storage Bucket (optional)',
            value: _storageBucket,
            onChanged: (value) => _storageBucket = value,
          ),
          const SizedBox(height: 10),
          ThemedTextInput(
            labelText: 'Device ID',
            value: _deviceId,
            onChanged: (value) => _deviceId = value,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ThemedButton.save(
                labelText: 'Set credentials',
                onTap: _setCredentials,
              ),
              ThemedButton(
                labelText: 'Set device ID',
                onTap: _setDeviceId,
              ),
              ThemedButton(
                labelText: 'Subscribe',
                onTap: _subscribe,
              ),
              ThemedButton(
                labelText: 'Unsubscribe',
                onTap: _unsubscribe,
              ),
              ThemedButton.show(
                labelText: 'Get subscriptions',
                onTap: _getSubscriptions,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Subscribed topics: ${_topics.isEmpty ? 'none' : _topics.join(', ')}'),
          const Divider(height: 32),
          _section(context, 'Received notifications (foreground)'),
          if (_notifications.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('None yet')),
          for (final notification in _notifications)
            ListTile(
              title: Text(notification.title ?? 'No title'),
              subtitle: Text('${notification.body ?? 'No body'}\n${notification.data}'),
              isThreeLine: true,
            ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
