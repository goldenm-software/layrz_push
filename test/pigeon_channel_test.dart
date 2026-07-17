import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layrz_push/src/layrz_push_pigeon/layrz_push.g.dart';
import 'package:layrz_push/src/layrz_push_pigeon/pigeon_channel.dart';
import 'package:layrz_push/src/platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Group 1: Codec serialization', () {
    // ============ PushCredentials Tests ============

    test('PushCredentials: encode/decode with android only', () {
      final android = AndroidPushCredentials(
        apiKey: 'android-key',
        appId: 'android-app-id',
        projectId: 'project-123',
        messagingSenderId: 'sender-123',
        storageBucket: 'bucket.appspot.com',
      );
      final original = PushCredentials(android: android, ios: null);

      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final encoded = codec.encodeMessage(original);
      expect(encoded, isNotNull);

      final decoded = codec.decodeMessage(encoded) as PushCredentials;
      expect(decoded, equals(original));
      expect(decoded.hashCode, equals(original.hashCode));
    });

    test('PushCredentials: encode/decode with iOS only', () {
      final ios = IosPushCredentials(
        apiKey: 'ios-key',
        appId: 'ios-app-id',
        projectId: 'project-456',
        messagingSenderId: 'sender-456',
      );
      final original = PushCredentials(android: null, ios: ios);

      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final encoded = codec.encodeMessage(original);
      final decoded = codec.decodeMessage(encoded) as PushCredentials;

      expect(decoded, equals(original));
      expect(decoded.hashCode, equals(original.hashCode));
    });

    test('PushCredentials: encode/decode with both platforms', () {
      final android = AndroidPushCredentials(
        apiKey: 'android-key',
        appId: 'android-app-id',
        projectId: 'project-789',
        messagingSenderId: 'sender-789',
      );
      final ios = IosPushCredentials(
        apiKey: 'ios-key',
        appId: 'ios-app-id',
        projectId: 'project-789',
        messagingSenderId: 'sender-789',
      );
      final original = PushCredentials(android: android, ios: ios);

      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final encoded = codec.encodeMessage(original);
      final decoded = codec.decodeMessage(encoded) as PushCredentials;

      expect(decoded, equals(original));
      expect(decoded.hashCode, equals(original.hashCode));
    });

    test('PushCredentials: encode/decode with all nulls', () {
      final original = PushCredentials(android: null, ios: null);

      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final encoded = codec.encodeMessage(original);
      final decoded = codec.decodeMessage(encoded) as PushCredentials;

      expect(decoded, equals(original));
      expect(decoded.hashCode, equals(original.hashCode));
    });

    test('PushCredentials: inequality with different runtimeType', () {
      final creds1 = PushCredentials(android: null, ios: null);
      final creds2 = PushCredentials(
        android: AndroidPushCredentials(
          apiKey: 'key',
          appId: 'app',
          projectId: 'proj',
          messagingSenderId: 'sender',
        ),
        ios: null,
      );

      expect(creds1 == creds2, isFalse);
    });

    test('PushCredentials: inequality with different field values', () {
      final android1 = AndroidPushCredentials(
        apiKey: 'key1',
        appId: 'app1',
        projectId: 'proj1',
        messagingSenderId: 'sender1',
      );
      final android2 = AndroidPushCredentials(
        apiKey: 'key2',
        appId: 'app2',
        projectId: 'proj2',
        messagingSenderId: 'sender2',
      );

      final creds1 = PushCredentials(android: android1, ios: null);
      final creds2 = PushCredentials(android: android2, ios: null);

      expect(creds1 == creds2, isFalse);
    });

    test('PushCredentials: same input produces same bytes (consistency)', () {
      final android = AndroidPushCredentials(
        apiKey: 'key',
        appId: 'app',
        projectId: 'proj',
        messagingSenderId: 'sender',
      );
      final original = PushCredentials(android: android, ios: null);

      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final bytes1 = codec.encodeMessage(original);
      final bytes2 = codec.encodeMessage(original);

      // Verify both decode to equal values
      final decoded1 = codec.decodeMessage(bytes1) as PushCredentials;
      final decoded2 = codec.decodeMessage(bytes2) as PushCredentials;
      expect(decoded1, equals(decoded2));
    });

    // ============ AndroidPushCredentials Tests ============

    test('AndroidPushCredentials: encode/decode with storageBucket present', () {
      final original = AndroidPushCredentials(
        apiKey: 'api-key',
        appId: 'app-id',
        projectId: 'project-id',
        messagingSenderId: 'sender-id',
        storageBucket: 'bucket.appspot.com',
      );

      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final encoded = codec.encodeMessage(original);
      final decoded = codec.decodeMessage(encoded) as AndroidPushCredentials;

      expect(decoded, equals(original));
      expect(decoded.hashCode, equals(original.hashCode));
    });

    test('AndroidPushCredentials: encode/decode with storageBucket null', () {
      final original = AndroidPushCredentials(
        apiKey: 'api-key',
        appId: 'app-id',
        projectId: 'project-id',
        messagingSenderId: 'sender-id',
      );

      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final encoded = codec.encodeMessage(original);
      final decoded = codec.decodeMessage(encoded) as AndroidPushCredentials;

      expect(decoded, equals(original));
      expect(decoded.storageBucket, isNull);
    });

    test('AndroidPushCredentials: all 5 fields equality', () {
      final creds1 = AndroidPushCredentials(
        apiKey: 'key',
        appId: 'app',
        projectId: 'proj',
        messagingSenderId: 'sender',
        storageBucket: 'bucket',
      );
      final creds2 = AndroidPushCredentials(
        apiKey: 'key',
        appId: 'app',
        projectId: 'proj',
        messagingSenderId: 'sender',
        storageBucket: 'bucket',
      );

      expect(creds1, equals(creds2));
      expect(creds1.hashCode, equals(creds2.hashCode));
    });

    test('AndroidPushCredentials: inequality with different field values', () {
      final creds1 = AndroidPushCredentials(
        apiKey: 'key1',
        appId: 'app1',
        projectId: 'proj1',
        messagingSenderId: 'sender1',
      );
      final creds2 = AndroidPushCredentials(
        apiKey: 'key2',
        appId: 'app2',
        projectId: 'proj2',
        messagingSenderId: 'sender2',
      );

      expect(creds1 == creds2, isFalse);
    });

    // ============ IosPushCredentials Tests ============

    test('IosPushCredentials: encode/decode with storageBucket present', () {
      final original = IosPushCredentials(
        apiKey: 'ios-api-key',
        appId: 'ios-app-id',
        projectId: 'ios-project-id',
        messagingSenderId: 'ios-sender-id',
        storageBucket: 'ios-bucket.appspot.com',
      );

      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final encoded = codec.encodeMessage(original);
      final decoded = codec.decodeMessage(encoded) as IosPushCredentials;

      expect(decoded, equals(original));
      expect(decoded.hashCode, equals(original.hashCode));
    });

    test('IosPushCredentials: encode/decode with storageBucket null', () {
      final original = IosPushCredentials(
        apiKey: 'ios-api-key',
        appId: 'ios-app-id',
        projectId: 'ios-project-id',
        messagingSenderId: 'ios-sender-id',
      );

      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final encoded = codec.encodeMessage(original);
      final decoded = codec.decodeMessage(encoded) as IosPushCredentials;

      expect(decoded, equals(original));
      expect(decoded.storageBucket, isNull);
    });

    test('IosPushCredentials: all 5 fields equality', () {
      final creds1 = IosPushCredentials(
        apiKey: 'key',
        appId: 'app',
        projectId: 'proj',
        messagingSenderId: 'sender',
        storageBucket: 'bucket',
      );
      final creds2 = IosPushCredentials(
        apiKey: 'key',
        appId: 'app',
        projectId: 'proj',
        messagingSenderId: 'sender',
        storageBucket: 'bucket',
      );

      expect(creds1, equals(creds2));
      expect(creds1.hashCode, equals(creds2.hashCode));
    });

    test('IosPushCredentials: inequality with different field values', () {
      final creds1 = IosPushCredentials(
        apiKey: 'key1',
        appId: 'app1',
        projectId: 'proj1',
        messagingSenderId: 'sender1',
      );
      final creds2 = IosPushCredentials(
        apiKey: 'key2',
        appId: 'app2',
        projectId: 'proj2',
        messagingSenderId: 'sender2',
      );

      expect(creds1 == creds2, isFalse);
    });

    // ============ PushNotification Tests ============

    test('PushNotification: encode/decode with title and body', () {
      final original = PushNotification(
        title: 'Test Title',
        body: 'Test Body',
        data: {'key': 'value'},
      );

      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final encoded = codec.encodeMessage(original);
      final decoded = codec.decodeMessage(encoded) as PushNotification;

      expect(decoded, equals(original));
      expect(decoded.hashCode, equals(original.hashCode));
    });

    test('PushNotification: encode/decode without title', () {
      final original = PushNotification(
        title: null,
        body: 'Test Body',
        data: {'key': 'value'},
      );

      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final encoded = codec.encodeMessage(original);
      final decoded = codec.decodeMessage(encoded) as PushNotification;

      expect(decoded, equals(original));
      expect(decoded.title, isNull);
    });

    test('PushNotification: encode/decode without body', () {
      final original = PushNotification(
        title: 'Test Title',
        body: null,
        data: {'key': 'value'},
      );

      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final encoded = codec.encodeMessage(original);
      final decoded = codec.decodeMessage(encoded) as PushNotification;

      expect(decoded, equals(original));
      expect(decoded.body, isNull);
    });

    test('PushNotification: encode/decode without title and body', () {
      final original = PushNotification(
        title: null,
        body: null,
        data: {'key': 'value'},
      );

      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final encoded = codec.encodeMessage(original);
      final decoded = codec.decodeMessage(encoded) as PushNotification;

      expect(decoded, equals(original));
    });

    test('PushNotification: encode/decode with empty data map', () {
      final original = PushNotification(
        title: 'Title',
        body: 'Body',
        data: {},
      );

      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final encoded = codec.encodeMessage(original);
      final decoded = codec.decodeMessage(encoded) as PushNotification;

      expect(decoded, equals(original));
      expect(decoded.data, isEmpty);
    });

    test('PushNotification: encode/decode with populated data map', () {
      final original = PushNotification(
        title: 'Title',
        body: 'Body',
        data: {
          'key1': 'value1',
          'key2': 'value2',
          'nested_key': 'nested_value',
        },
      );

      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final encoded = codec.encodeMessage(original);
      final decoded = codec.decodeMessage(encoded) as PushNotification;

      expect(decoded, equals(original));
      expect(decoded.data, hasLength(3));
    });

    test('PushNotification: all 3 fields equality', () {
      final notif1 = PushNotification(
        title: 'Title',
        body: 'Body',
        data: {'key': 'value'},
      );
      final notif2 = PushNotification(
        title: 'Title',
        body: 'Body',
        data: {'key': 'value'},
      );

      expect(notif1, equals(notif2));
      expect(notif1.hashCode, equals(notif2.hashCode));
    });

    test('PushNotification: inequality with different field values', () {
      final notif1 = PushNotification(
        title: 'Title1',
        body: 'Body1',
        data: {'key': 'value1'},
      );
      final notif2 = PushNotification(
        title: 'Title2',
        body: 'Body2',
        data: {'key': 'value2'},
      );

      expect(notif1 == notif2, isFalse);
    });
  });

  group('Group 2: LayrzPushPlatformChannel happy paths', () {
    final binding = TestDefaultBinaryMessengerBinding.instance;

    tearDown(() {
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.setCredentials',
        null,
      );
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.setDeviceId',
        null,
      );
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.subscribe',
        null,
      );
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.unsubscribe',
        null,
      );
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.getSubscriptions',
        null,
      );
    });

    // ============ setCredentials Tests ============

    test('setCredentials: singleton returns true', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.setCredentials',
        (message) async {
          // Decode incoming message to verify argument structure
          final decoded = codec.decodeMessage(message) as List<Object?>;
          expect(decoded, hasLength(1));
          expect(decoded[0], isA<PushCredentials>());
          // Reply with success envelope
          return codec.encodeMessage([true]);
        },
      );

      final android = AndroidPushCredentials(
        apiKey: 'key',
        appId: 'app',
        projectId: 'proj',
        messagingSenderId: 'sender',
      );
      final credentials = PushCredentials(android: android, ios: null);

      final result = await LayrzPushPigeonChannel.instance.setCredentials(
        credentials: credentials,
      );

      expect(result, isTrue);
    });

    test('setCredentials: non-singleton instance works', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.setCredentials',
        (message) async {
          return codec.encodeMessage([true]);
        },
      );

      final android = AndroidPushCredentials(
        apiKey: 'key',
        appId: 'app',
        projectId: 'proj',
        messagingSenderId: 'sender',
      );
      final credentials = PushCredentials(android: android, ios: null);

      final channel = LayrzPushPlatformChannel();
      final result = await channel.setCredentials(credentials: credentials);

      expect(result, isTrue);
    });

    // ============ setDeviceId Tests ============

    test('setDeviceId: singleton returns true', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.setDeviceId',
        (message) async {
          final decoded = codec.decodeMessage(message) as List<Object?>;
          expect(decoded, hasLength(1));
          expect(decoded[0], equals('device-123'));
          return codec.encodeMessage([true]);
        },
      );

      final result = await LayrzPushPigeonChannel.instance.setDeviceId(
        deviceId: 'device-123',
      );

      expect(result, isTrue);
    });

    test('setDeviceId: non-singleton instance works', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.setDeviceId',
        (message) async {
          return codec.encodeMessage([true]);
        },
      );

      final channel = LayrzPushPlatformChannel();
      final result = await channel.setDeviceId(deviceId: 'device-456');

      expect(result, isTrue);
    });

    // ============ subscribe Tests ============

    test('subscribe: singleton returns true', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.subscribe',
        (message) async {
          return codec.encodeMessage([true]);
        },
      );

      final result = await LayrzPushPigeonChannel.instance.subscribe();

      expect(result, isTrue);
    });

    test('subscribe: non-singleton instance works', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.subscribe',
        (message) async {
          return codec.encodeMessage([true]);
        },
      );

      final channel = LayrzPushPlatformChannel();
      final result = await channel.subscribe();

      expect(result, isTrue);
    });

    // ============ unsubscribe Tests ============

    test('unsubscribe: singleton returns true', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.unsubscribe',
        (message) async {
          return codec.encodeMessage([true]);
        },
      );

      final result = await LayrzPushPigeonChannel.instance.unsubscribe();

      expect(result, isTrue);
    });

    test('unsubscribe: non-singleton instance works', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.unsubscribe',
        (message) async {
          return codec.encodeMessage([true]);
        },
      );

      final channel = LayrzPushPlatformChannel();
      final result = await channel.unsubscribe();

      expect(result, isTrue);
    });

    // ============ getSubscriptions Tests ============

    test('getSubscriptions: singleton returns list', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.getSubscriptions',
        (message) async {
          return codec.encodeMessage([
            ['device_123', 'device_456'],
          ]);
        },
      );

      final result = await LayrzPushPigeonChannel.instance.getSubscriptions();

      expect(result, isA<List<String>>());
      expect(result, equals(['device_123', 'device_456']));
    });

    test('getSubscriptions: non-singleton instance works', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.getSubscriptions',
        (message) async {
          return codec.encodeMessage([
            ['device_789'],
          ]);
        },
      );

      final channel = LayrzPushPlatformChannel();
      final result = await channel.getSubscriptions();

      expect(result, equals(['device_789']));
    });

    test('getSubscriptions: returns empty list', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.getSubscriptions',
        (message) async {
          return codec.encodeMessage([[]]);
        },
      );

      final result = await LayrzPushPigeonChannel.instance.getSubscriptions();

      expect(result, isEmpty);
    });
  });

  group('Group 3: LayrzPushPlatformChannel error paths', () {
    final binding = TestDefaultBinaryMessengerBinding.instance;

    tearDown(() {
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.setCredentials',
        null,
      );
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.setDeviceId',
        null,
      );
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.subscribe',
        null,
      );
    });

    // ============ PlatformException Error Envelope Tests ============

    test('setCredentials: error envelope with auth-failed code', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.setCredentials',
        (message) async {
          // Return error envelope: [code, message, details]
          return codec.encodeMessage([
            'auth-failed',
            'Authentication failed',
            null,
          ]);
        },
      );

      final android = AndroidPushCredentials(
        apiKey: 'bad-key',
        appId: 'app',
        projectId: 'proj',
        messagingSenderId: 'sender',
      );

      expect(
        () => LayrzPushPigeonChannel.instance.setCredentials(
          credentials: PushCredentials(android: android, ios: null),
        ),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', equals('auth-failed'))
              .having(
                (e) => e.message,
                'message',
                equals('Authentication failed'),
              ),
        ),
      );
    });

    test('setDeviceId: error envelope with network-error code', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.setDeviceId',
        (message) async {
          return codec.encodeMessage([
            'network-error',
            'Network connection failed',
            'details_object',
          ]);
        },
      );

      expect(
        () => LayrzPushPigeonChannel.instance.setDeviceId(
          deviceId: 'device-bad',
        ),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', equals('network-error'))
              .having(
                (e) => e.details,
                'details',
                equals('details_object'),
              ),
        ),
      );
    });

    test('subscribe: error envelope with invalid-credentials code', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.subscribe',
        (message) async {
          return codec.encodeMessage([
            'invalid-credentials',
            'Credentials not set',
            null,
          ]);
        },
      );

      expect(
        () => LayrzPushPigeonChannel.instance.subscribe(),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', equals('invalid-credentials')),
        ),
      );
    });

    // ============ Connection Error (null reply) Tests ============

    test('setCredentials: null reply triggers channel-error', () async {
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.setCredentials',
        (message) async {
          // Return null to simulate connection failure
          return null;
        },
      );

      final android = AndroidPushCredentials(
        apiKey: 'key',
        appId: 'app',
        projectId: 'proj',
        messagingSenderId: 'sender',
      );

      expect(
        () => LayrzPushPigeonChannel.instance.setCredentials(
          credentials: PushCredentials(android: android, ios: null),
        ),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', equals('channel-error')),
        ),
      );
    });

    test('setDeviceId: null reply triggers channel-error', () async {
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.setDeviceId',
        (message) async {
          return null;
        },
      );

      expect(
        () => LayrzPushPigeonChannel.instance.setDeviceId(
          deviceId: 'device-123',
        ),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', equals('channel-error')),
        ),
      );
    });

    test('subscribe: null reply triggers channel-error', () async {
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.layrz_push.LayrzPushPlatformChannel.subscribe',
        (message) async {
          return null;
        },
      );

      expect(
        () => LayrzPushPigeonChannel.instance.subscribe(),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', equals('channel-error')),
        ),
      );
    });
  });

  group('Group 4: LayrzPushCallbackChannel.onPush', () {
    final binding = TestDefaultBinaryMessengerBinding.instance;

    setUp(() {
      // Reset singleton for each test to avoid state pollution
      // Note: We're testing the instance's stream behavior
    });

    test('onPush: stream emits notification with title and body', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final notification = PushNotification(
        title: 'Test Title',
        body: 'Test Body',
        data: {'key': 'value'},
      );

      final onPushFuture = LayrzPushPigeonChannel.instance.onPush.first;

      // Encode notification as Pigeon expects: [notification]
      final encoded = codec.encodeMessage([notification]);

      // Simulate native code sending the notification via the callback channel
      binding.defaultBinaryMessenger.handlePlatformMessage(
        'dev.flutter.pigeon.layrz_push.LayrzPushCallbackChannel.onPush',
        encoded,
        (_) {},
      );

      final emitted = await onPushFuture;

      expect(emitted, equals(notification));
      expect(emitted.title, equals('Test Title'));
      expect(emitted.body, equals('Test Body'));
    });

    test('onPush: stream emits notification without title', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final notification = PushNotification(
        title: null,
        body: 'Body Only',
        data: {},
      );

      final onPushFuture = LayrzPushPigeonChannel.instance.onPush.first;

      final encoded = codec.encodeMessage([notification]);
      binding.defaultBinaryMessenger.handlePlatformMessage(
        'dev.flutter.pigeon.layrz_push.LayrzPushCallbackChannel.onPush',
        encoded,
        (_) {},
      );

      final emitted = await onPushFuture;

      expect(emitted.title, isNull);
      expect(emitted.body, equals('Body Only'));
    });

    test('onPush: stream emits notification without body', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final notification = PushNotification(
        title: 'Title Only',
        body: null,
        data: {},
      );

      final onPushFuture = LayrzPushPigeonChannel.instance.onPush.first;

      final encoded = codec.encodeMessage([notification]);
      binding.defaultBinaryMessenger.handlePlatformMessage(
        'dev.flutter.pigeon.layrz_push.LayrzPushCallbackChannel.onPush',
        encoded,
        (_) {},
      );

      final emitted = await onPushFuture;

      expect(emitted.title, equals('Title Only'));
      expect(emitted.body, isNull);
    });

    test('onPush: stream emits notification with complex data payload', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final notification = PushNotification(
        title: 'Complex',
        body: 'Data',
        data: {
          'nested_key': 'nested_value',
          'another_key': 'another_value',
          'number_string': '12345',
        },
      );

      final onPushFuture = LayrzPushPigeonChannel.instance.onPush.first;

      final encoded = codec.encodeMessage([notification]);
      binding.defaultBinaryMessenger.handlePlatformMessage(
        'dev.flutter.pigeon.layrz_push.LayrzPushCallbackChannel.onPush',
        encoded,
        (_) {},
      );

      final emitted = await onPushFuture;

      expect(emitted.data, hasLength(3));
      expect(emitted.data['nested_key'], equals('nested_value'));
    });

    test('onPush: stream emits multiple messages in sequence', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final notif1 = PushNotification(
        title: 'First',
        body: 'Message 1',
        data: {},
      );
      final notif2 = PushNotification(
        title: 'Second',
        body: 'Message 2',
        data: {},
      );
      final notif3 = PushNotification(
        title: 'Third',
        body: 'Message 3',
        data: {},
      );

      final stream = LayrzPushPigeonChannel.instance.onPush;
      final subscription = stream.take(3).toList();

      // Emit three notifications in sequence
      final encoded1 = codec.encodeMessage([notif1]);
      binding.defaultBinaryMessenger.handlePlatformMessage(
        'dev.flutter.pigeon.layrz_push.LayrzPushCallbackChannel.onPush',
        encoded1,
        (_) {},
      );

      final encoded2 = codec.encodeMessage([notif2]);
      binding.defaultBinaryMessenger.handlePlatformMessage(
        'dev.flutter.pigeon.layrz_push.LayrzPushCallbackChannel.onPush',
        encoded2,
        (_) {},
      );

      final encoded3 = codec.encodeMessage([notif3]);
      binding.defaultBinaryMessenger.handlePlatformMessage(
        'dev.flutter.pigeon.layrz_push.LayrzPushCallbackChannel.onPush',
        encoded3,
        (_) {},
      );

      final emitted = await subscription;

      expect(emitted, hasLength(3));
      expect(emitted[0], equals(notif1));
      expect(emitted[1], equals(notif2));
      expect(emitted[2], equals(notif3));
    });

    test('onPush: multiple listeners can subscribe to broadcast stream', () async {
      final codec = LayrzPushPlatformChannel.pigeonChannelCodec;
      final notification = PushNotification(
        title: 'Broadcast',
        body: 'Test',
        data: {},
      );

      final stream = LayrzPushPigeonChannel.instance.onPush;
      final listener1Future = stream.first;
      final listener2Future = stream.first;

      final encoded = codec.encodeMessage([notification]);
      binding.defaultBinaryMessenger.handlePlatformMessage(
        'dev.flutter.pigeon.layrz_push.LayrzPushCallbackChannel.onPush',
        encoded,
        (_) {},
      );

      final emitted1 = await listener1Future;
      final emitted2 = await listener2Future;

      expect(emitted1, equals(notification));
      expect(emitted2, equals(notification));
    });
  });

  group('Group 5: LayrzPushPlatform defaults', () {
    test('bare subclass throws UnimplementedError for onPush getter', () {
      final platform = _BareLayrzPushPlatform();

      expect(
        () => platform.onPush,
        throwsA(
          isA<UnimplementedError>()
              .having(
                (e) => e.message,
                'message',
                contains('onPush'),
              ),
        ),
      );
    });

    test('bare subclass throws UnimplementedError for setCredentials', () {
      final platform = _BareLayrzPushPlatform();
      final android = AndroidPushCredentials(
        apiKey: 'key',
        appId: 'app',
        projectId: 'proj',
        messagingSenderId: 'sender',
      );

      expect(
        () => platform.setCredentials(
          credentials: PushCredentials(android: android, ios: null),
        ),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('bare subclass throws UnimplementedError for setDeviceId', () {
      final platform = _BareLayrzPushPlatform();

      expect(
        () => platform.setDeviceId(deviceId: 'device-123'),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('bare subclass throws UnimplementedError for subscribe', () {
      final platform = _BareLayrzPushPlatform();

      expect(
        () => platform.subscribe(),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('bare subclass throws UnimplementedError for unsubscribe', () {
      final platform = _BareLayrzPushPlatform();

      expect(
        () => platform.unsubscribe(),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('bare subclass throws UnimplementedError for getSubscriptions', () {
      final platform = _BareLayrzPushPlatform();

      expect(
        () => platform.getSubscriptions(),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('all 6 abstract members throw UnimplementedError', () {
      final platform = _BareLayrzPushPlatform();
      final members = [
        () => platform.onPush,
        () => platform.setCredentials(
          credentials: PushCredentials(android: null, ios: null),
        ),
        () => platform.setDeviceId(deviceId: ''),
        () => platform.subscribe(),
        () => platform.unsubscribe(),
        () => platform.getSubscriptions(),
      ];

      for (final member in members) {
        expect(
          member,
          throwsA(isA<UnimplementedError>()),
          reason: 'Member should throw UnimplementedError',
        );
      }
    });
  });
}

/// Bare implementation of LayrzPushPlatform overriding nothing.
/// Used for testing that abstract members throw UnimplementedError.
class _BareLayrzPushPlatform extends LayrzPushPlatform {}
