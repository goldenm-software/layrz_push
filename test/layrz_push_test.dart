import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:layrz_push/layrz_push.dart';

class MockLayrzPushPlatform extends LayrzPushPlatform {
  PushCredentials? credentials;
  String? deviceId;
  final List<String> topics = [];
  final StreamController<PushNotification> pushController = StreamController<PushNotification>.broadcast();

  @override
  Stream<PushNotification> get onPush => pushController.stream;

  @override
  Future<bool> setCredentials({required PushCredentials credentials}) async {
    this.credentials = credentials;
    return credentials.android != null || credentials.ios != null;
  }

  @override
  Future<bool> setDeviceId({required String deviceId}) async {
    this.deviceId = deviceId;
    return true;
  }

  @override
  Future<bool> subscribe() async {
    if (credentials == null || deviceId == null) return false;
    topics.add('device_$deviceId');
    return true;
  }

  @override
  Future<bool> unsubscribe() async {
    if (deviceId == null) return false;
    return topics.remove('device_$deviceId');
  }

  @override
  Future<List<String>> getSubscriptions() async => List.of(topics);
}

void main() {
  late LayrzPush plugin;
  late MockLayrzPushPlatform platform;

  final credentials = PushCredentials(
    android: AndroidPushCredentials(
      apiKey: 'api-key',
      appId: 'app-id',
      projectId: 'project-id',
      messagingSenderId: 'sender-id',
    ),
  );

  setUp(() {
    plugin = LayrzPush();
    platform = MockLayrzPushPlatform();
    LayrzPush.setInstance(platform);
  });

  test('setCredentials delegates to the platform', () async {
    expect(await plugin.setCredentials(credentials: credentials), isTrue);
    expect(platform.credentials, credentials);

    expect(await plugin.setCredentials(credentials: PushCredentials()), isFalse);
  });

  test('setDeviceId delegates to the platform', () async {
    expect(await plugin.setDeviceId(deviceId: 'my-device'), isTrue);
    expect(platform.deviceId, 'my-device');
  });

  test('subscribe requires credentials and device id', () async {
    expect(await plugin.subscribe(), isFalse);

    await plugin.setCredentials(credentials: credentials);
    await plugin.setDeviceId(deviceId: 'my-device');

    expect(await plugin.subscribe(), isTrue);
    expect(await plugin.getSubscriptions(), ['device_my-device']);
  });

  test('unsubscribe removes the topic', () async {
    await plugin.setCredentials(credentials: credentials);
    await plugin.setDeviceId(deviceId: 'my-device');
    await plugin.subscribe();

    expect(await plugin.unsubscribe(), isTrue);
    expect(await plugin.getSubscriptions(), isEmpty);
  });

  test('onPush emits notifications from the platform', () async {
    final notification = PushNotification(title: 'Hello', body: 'World', data: {'key': 'value'});

    final future = plugin.onPush.first;
    platform.pushController.add(notification);

    expect(await future, notification);
  });
}
