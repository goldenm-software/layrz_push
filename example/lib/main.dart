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
  String? _busyAction;

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

  /// Loads Firebase credentials and device ID from an optional `assets/secrets.json`.
  ///
  /// If present, the file can override the plain text form fields with pre-populated
  /// values. This is useful for development and testing. The file is gitignored.
  ///
  /// Expected format (see `assets/secrets.example.json`):
  /// ```json
  /// {
  ///   "deviceId": "my-device-uuid",
  ///   "android": {
  ///     "apiKey": "...",
  ///     "appId": "...",
  ///     "projectId": "...",
  ///     "messagingSenderId": "...",
  ///     "storageBucket": "..."
  ///   },
  ///   "ios": {
  ///     "apiKey": "...",
  ///     "appId": "...",
  ///     "projectId": "...",
  ///     "messagingSenderId": "...",
  ///     "storageBucket": "..."
  ///   }
  /// }
  /// ```
  ///
  /// If no secrets file is found, or if parsing fails, the method silently returns
  /// and leaves the form fields as their default (empty or pre-set) values.
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
      final platform =
          secrets[_isIos ? 'ios' : 'android'] as Map<String, dynamic>?;

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
        icon: result
            ? LayrzIcons.solarOutlineCheckSquare
            : LayrzIcons.solarOutlineCloseSquare,
      ),
    );
  }

  /// Builds credentials for the current platform and injects them into the plugin.
  ///
  /// Demonstrates platform-aware credential building: only the credentials for
  /// the current platform (Android or iOS) are populated; the other platform's
  /// field is set to null. The native side reads its own field and ignores the
  /// other, so sending both is safe.
  ///
  /// The `storageBucket` field is optional (nullable), so empty strings are
  /// converted to null before creating the credential objects.
  Future<void> _setCredentials() async {
    if (_busyAction != null) return;
    setState(() => _busyAction = 'setCredentials');
    try {
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
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _setDeviceId() async {
    if (_busyAction != null) return;
    setState(() => _busyAction = 'setDeviceId');
    try {
      final result = await _plugin.setDeviceId(deviceId: _deviceId);
      _showResult('setDeviceId', result);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _subscribe() async {
    if (_busyAction != null) return;
    setState(() => _busyAction = 'subscribe');
    try {
      final result = await _plugin.subscribe();
      _showResult('subscribe', result);
      await _getSubscriptions();
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _unsubscribe() async {
    if (_busyAction != null) return;
    setState(() => _busyAction = 'unsubscribe');
    try {
      final result = await _plugin.unsubscribe();
      _showResult('unsubscribe', result);
      await _getSubscriptions();
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _getSubscriptions() async {
    if (_busyAction != null) return;
    setState(() => _busyAction = 'getSubscriptions');
    try {
      final topics = await _plugin.getSubscriptions();
      setState(() => _topics = topics);
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
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
              Expanded(
                child: Text('Status: ${_permissionStatus?.name ?? 'unknown'}'),
              ),
              ThemedButton(
                labelText: 'Request',
                icon: LayrzIcons.solarOutlineInfoCircle,
                onTap: _requestPermission,
              ),
            ],
          ),
          const Divider(height: 32),
          _section(context, '$platformName credentials'),
          // Display a note if credentials were loaded from secrets.json
          if (_secretsLoaded)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Loaded from assets/secrets.json',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
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
                isLoading: _busyAction == 'setCredentials',
                isDisabled:
                    _busyAction != null && _busyAction != 'setCredentials',
              ),
              ThemedButton(
                labelText: 'Set device ID',
                onTap: _setDeviceId,
                isLoading: _busyAction == 'setDeviceId',
                isDisabled: _busyAction != null && _busyAction != 'setDeviceId',
              ),
              ThemedButton(
                labelText: 'Subscribe',
                onTap: _subscribe,
                isLoading: _busyAction == 'subscribe',
                isDisabled: _busyAction != null && _busyAction != 'subscribe',
              ),
              ThemedButton(
                labelText: 'Unsubscribe',
                onTap: _unsubscribe,
                isLoading: _busyAction == 'unsubscribe',
                isDisabled: _busyAction != null && _busyAction != 'unsubscribe',
              ),
              ThemedButton.show(
                labelText: 'Get subscriptions',
                onTap: _getSubscriptions,
                isLoading: _busyAction == 'getSubscriptions',
                isDisabled:
                    _busyAction != null && _busyAction != 'getSubscriptions',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Subscribed topics: ${_topics.isEmpty ? 'none' : _topics.join(', ')}',
          ),
          const Divider(height: 32),
          // This section only shows notifications received while the app was in foreground.
          // Notifications arriving in the background or when the app is killed are
          // displayed by the system directly and do not appear here.
          _section(context, 'Received notifications (foreground)'),
          if (_notifications.isEmpty)
            const Padding(padding: EdgeInsets.all(8), child: Text('None yet')),
          for (final notification in _notifications)
            ListTile(
              title: Text(notification.title ?? 'No title'),
              subtitle: Text(
                '${notification.body ?? 'No body'}\n${notification.data}',
              ),
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
