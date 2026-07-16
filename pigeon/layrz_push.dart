import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'layrz_push',
    dartOptions: DartOptions(),
    dartOut: 'lib/src/layrz_push_pigeon/layrz_push.g.dart',
    kotlinOptions: KotlinOptions(package: 'com.layrz.layrz_push'),
    kotlinOut: 'android/src/main/kotlin/com/layrz/layrz_push/LayrzPush.g.kt',
    swiftOptions: SwiftOptions(),
    swiftOut: 'ios/layrz_push/Sources/layrz_push/LayrzPush.g.swift',
    debugGenerators: true,
  ),
)

// Host API from Flutter to Native
@HostApi()
abstract class LayrzPushPlatformChannel {
  /// Injects (or replaces) the Firebase credentials at runtime.
  ///
  /// Each platform reads its own sub-object and ignores the other one.
  /// If a Firebase app is already configured, it's deleted and re-created
  /// with the new options.
  @async
  bool setCredentials({required PushCredentials credentials});

  /// Persists the Layrz device ID securely on the device.
  ///
  /// The device ID defines the FCM topic used by [subscribe] and
  /// [unsubscribe], following the format `device_{deviceId}`.
  @async
  bool setDeviceId({required String deviceId});

  /// Subscribes to the `device_{deviceId}` FCM topic.
  ///
  /// Requires [setCredentials] and [setDeviceId] to be called first.
  @async
  bool subscribe();

  /// Unsubscribes from the `device_{deviceId}` FCM topic.
  @async
  bool unsubscribe();

  /// Returns the list of currently subscribed topics.
  ///
  /// FCM does not provide a native API for this, so the list is tracked
  /// locally on each subscribe/unsubscribe call.
  @async
  List<String> getSubscriptions();
}

// Flutter API from Native to Flutter
@FlutterApi()
abstract class LayrzPushCallbackChannel {
  /// Called when a push notification arrives while the app is in foreground.
  void onPush(PushNotification notification);
}

/// Firebase credentials for both platforms. Each platform is optional,
/// the native side picks its own.
class PushCredentials {
  final AndroidPushCredentials? android;
  final IosPushCredentials? ios;

  const PushCredentials({
    this.android,
    this.ios,
  });
}

/// Firebase credentials for Android, equivalent to the values found in
/// `google-services.json`.
class AndroidPushCredentials {
  /// `client[].api_key[].current_key` in google-services.json
  final String apiKey;

  /// `client[].client_info.mobilesdk_app_id` in google-services.json
  final String appId;

  /// `project_info.project_id` in google-services.json
  final String projectId;

  /// `project_info.project_number` in google-services.json
  final String messagingSenderId;

  /// `project_info.storage_bucket` in google-services.json
  final String? storageBucket;

  const AndroidPushCredentials({
    required this.apiKey,
    required this.appId,
    required this.projectId,
    required this.messagingSenderId,
    this.storageBucket,
  });
}

/// Firebase credentials for iOS, equivalent to the values found in
/// `GoogleService-Info.plist`.
class IosPushCredentials {
  /// `API_KEY` in GoogleService-Info.plist
  final String apiKey;

  /// `GOOGLE_APP_ID` in GoogleService-Info.plist
  final String appId;

  /// `PROJECT_ID` in GoogleService-Info.plist
  final String projectId;

  /// `GCM_SENDER_ID` in GoogleService-Info.plist
  final String messagingSenderId;

  /// `STORAGE_BUCKET` in GoogleService-Info.plist
  final String? storageBucket;

  const IosPushCredentials({
    required this.apiKey,
    required this.appId,
    required this.projectId,
    required this.messagingSenderId,
    this.storageBucket,
  });
}

/// A push notification received while the app is in foreground.
class PushNotification {
  /// Title of the notification, if any.
  final String? title;

  /// Body of the notification, if any.
  final String? body;

  /// Custom data payload attached to the notification.
  final Map<String, String> data;

  const PushNotification({
    this.title,
    this.body,
    this.data = const {},
  });
}
