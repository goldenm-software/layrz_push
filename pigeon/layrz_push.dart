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
/// Host API from Flutter to Native (via platform channels).
///
/// Provides the primary interface for managing Firebase Cloud Messaging (FCM)
/// credentials and subscriptions on native platforms. All methods are async
/// and communicate with native code through Pigeon-generated platform channels.
@HostApi()
abstract class LayrzPushPlatformChannel {
  /// Injects (or replaces) the Firebase credentials at runtime.
  ///
  /// This method allows hot-swapping between different Firebase projects without
  /// restarting the app, enabling multi-tenant support. Each platform reads only
  /// its own credentials object (Android reads [PushCredentials.android], iOS reads
  /// [PushCredentials.ios]) and ignores the other.
  ///
  /// **Idempotency**: If the incoming credentials match the previously stored credentials
  /// (all fields: apiKey, appId, projectId, messagingSenderId, storageBucket) and a
  /// Firebase app is already initialized, this method returns immediately without deleting
  /// or re-initializing Firebase. This prevents unnecessary FCM registration-token invalidation
  /// and avoids GMS/APNs re-registration delays, which is critical for apps that call
  /// [setCredentials] at every boot.
  ///
  /// **Multi-tenant hot-swap**: When credentials DIFFER, the existing Firebase app is deleted
  /// and re-initialized with the new credentials, exactly as before. This ensures the app stays
  /// connected to the correct FCM backend for the current tenant.
  ///
  /// Returns `true` if credentials were successfully applied or remained unchanged, `false` otherwise.
  @async
  bool setCredentials({required PushCredentials credentials});

  /// Persists the Layrz device ID securely on the device.
  ///
  /// On Android, the device ID is encrypted using AES-GCM and stored in
  /// SharedPreferences backed by Android Keystore. On iOS, it is stored in
  /// Keychain (which survives app uninstall).
  ///
  /// The device ID defines the FCM topic that [subscribe] and [unsubscribe]
  /// will target, following the format `device_{deviceId}`.
  ///
  /// Must be called before [subscribe] and [unsubscribe]; they will return
  /// `false` if no device ID is set.
  ///
  /// Returns `true` if the device ID was successfully persisted, `false` otherwise.
  @async
  bool setDeviceId({required String deviceId});

  /// Retrieves the persisted Layrz device ID from secure storage.
  ///
  /// On Android, the device ID is decrypted from AES-GCM-encrypted
  /// SharedPreferences (backed by Android Keystore). On iOS, it is retrieved
  /// from Keychain.
  ///
  /// Returns the device ID string if it was previously persisted via [setDeviceId].
  /// Returns null if no device ID has been set, if decryption fails (e.g., Android
  /// Auto Backup restored prefs on a new install without the Keystore key), or if
  /// the Keychain item is unavailable (e.g., on a different iOS device after backup).
  @async
  String? getDeviceId();

  /// Subscribes to the `device_{deviceId}` FCM topic.
  ///
  /// Requires both [setCredentials] and [setDeviceId] to have been called
  /// successfully first. If either is missing, this method returns `false`.
  ///
  /// On first subscribe after app install, FCM must fetch its registration token
  /// from Google Mobile Services (GMS). This can take a considerable time (observed
  /// up to 75 seconds) due to GMS communication and potential transient error
  /// retries. The returned Future completes once FCM finishes initialization.
  ///
  /// The subscription list is tracked locally; subsequent calls to [getSubscriptions]
  /// will reflect the newly added topic.
  ///
  /// Returns `true` if the subscription succeeded, `false` if credentials or device
  /// ID are missing, or if the native subscribe operation failed.
  @async
  bool subscribe();

  /// Unsubscribes from the `device_{deviceId}` FCM topic.
  ///
  /// Requires [setDeviceId] to have been called first. Returns `false` if no
  /// device ID is set or if the unsubscribe operation fails.
  ///
  /// The subscription list is tracked locally; subsequent calls to [getSubscriptions]
  /// will reflect the removal of the topic.
  ///
  /// Returns `true` if the unsubscription succeeded, `false` otherwise.
  @async
  bool unsubscribe();

  /// Returns the list of currently subscribed FCM topics.
  ///
  /// FCM does not provide a native API to query the full list of subscribed topics,
  /// so this plugin maintains a local list that is updated on each [subscribe] and
  /// [unsubscribe] call. This method returns that locally-tracked list.
  ///
  /// The list should contain topic strings like `device_12345` for subscribed topics.
  /// If no subscriptions exist, an empty list is returned.
  @async
  List<String> getSubscriptions();
}

/// Flutter API from Native to Flutter (via platform channels).
///
/// Provides a callback interface for the native platform to invoke Flutter
/// when events occur. This is implemented and set up by the Dart platform
/// implementation to receive foreground push notifications.
@FlutterApi()
abstract class LayrzPushCallbackChannel {
  /// Called when a push notification arrives while the app is in foreground.
  ///
  /// This callback fires only when the app is actively running and visible to
  /// the user. When the app is in the background or terminated, the system will
  /// display the notification directly (with a system banner) and this callback
  /// will not be invoked.
  ///
  /// The [notification] contains the title, body, and custom data payload sent
  /// by the FCM backend.
  void onPush(PushNotification notification);
}

/// Container for Firebase credentials on both Android and iOS platforms.
///
/// This class wraps platform-specific credential objects. Each platform reads
/// only its own credential object and ignores the other, allowing a single
/// [PushCredentials] instance to carry credentials for both platforms at once.
///
/// This design enables multi-tenant scenarios where different Layrz clients
/// can inject their own Firebase project credentials at runtime. Credentials
/// can be hot-swapped by calling [LayrzPushPlatformChannel.setCredentials]
/// multiple times with different [PushCredentials] instances.
class PushCredentials {
  /// Firebase credentials for Android, extracted from `google-services.json`.
  final AndroidPushCredentials? android;

  /// Firebase credentials for iOS, extracted from `GoogleService-Info.plist`.
  final IosPushCredentials? ios;

  const PushCredentials({this.android, this.ios});
}

/// Firebase credentials for Android, extracted from `google-services.json`.
///
/// These values must be obtained from the Firebase Console and bundled in
/// the app's `google-services.json` file during normal Firebase setup. However,
/// this plugin allows injecting credentials at runtime for multi-tenant support.
///
/// All required fields must be present for Firebase initialization to succeed
/// on the native Android side.
class AndroidPushCredentials {
  /// API key for the Android client.
  ///
  /// Found in `google-services.json` at `client[].api_key[].current_key`.
  final String apiKey;

  /// Mobile SDK app ID for the Android client.
  ///
  /// Found in `google-services.json` at `client[].client_info.mobilesdk_app_id`.
  final String appId;

  /// Firebase project ID.
  ///
  /// Found in `google-services.json` at `project_info.project_id`.
  /// This ID is shared across all platforms within the same Firebase project.
  final String projectId;

  /// GCM (Google Cloud Messaging) sender ID, also known as the project number.
  ///
  /// Found in `google-services.json` at `project_info.project_number`.
  /// Used by FCM to identify the project when sending messages.
  final String messagingSenderId;

  /// Cloud Storage bucket URL (optional).
  ///
  /// Found in `google-services.json` at `project_info.storage_bucket`.
  /// This field is optional and may be null.
  final String? storageBucket;

  const AndroidPushCredentials({
    required this.apiKey,
    required this.appId,
    required this.projectId,
    required this.messagingSenderId,
    this.storageBucket,
  });
}

/// Firebase credentials for iOS, extracted from `GoogleService-Info.plist`.
///
/// These values must be obtained from the Firebase Console and bundled in
/// the app's `GoogleService-Info.plist` file during normal Firebase setup. However,
/// this plugin allows injecting credentials at runtime for multi-tenant support.
///
/// All required fields must be present for Firebase initialization to succeed
/// on the native iOS side.
class IosPushCredentials {
  /// API key for the iOS client.
  ///
  /// Found in `GoogleService-Info.plist` with the key `API_KEY`.
  final String apiKey;

  /// Firebase app ID for the iOS client.
  ///
  /// Found in `GoogleService-Info.plist` with the key `GOOGLE_APP_ID`.
  final String appId;

  /// Firebase project ID.
  ///
  /// Found in `GoogleService-Info.plist` with the key `PROJECT_ID`.
  /// This ID is shared across all platforms within the same Firebase project.
  final String projectId;

  /// GCM (Google Cloud Messaging) sender ID, also known as the project number.
  ///
  /// Found in `GoogleService-Info.plist` with the key `GCM_SENDER_ID`.
  /// Used by FCM to identify the project when sending messages.
  final String messagingSenderId;

  /// Cloud Storage bucket URL (optional).
  ///
  /// Found in `GoogleService-Info.plist` with the key `STORAGE_BUCKET`.
  /// This field is optional and may be null.
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
///
/// This object is passed to the [LayrzPushCallbackChannel.onPush] callback
/// when a notification arrives while the app is actively running. Notifications
/// received in the background or when the app is terminated are displayed by
/// the system directly and do not produce instances of this class.
///
/// The data payload is provided as a flat map of key-value string pairs, as
/// received from FCM.
class PushNotification {
  /// Title of the notification, if provided by the FCM message.
  ///
  /// May be null if no title was set on the upstream message.
  final String? title;

  /// Body of the notification, if provided by the FCM message.
  ///
  /// May be null if no body was set on the upstream message.
  final String? body;

  /// Custom data payload attached to the notification.
  ///
  /// This is a flat map of key-value pairs set by the application server
  /// or backend when sending the FCM message. Defaults to an empty map
  /// if no data was provided.
  final Map<String, String> data;

  const PushNotification({this.title, this.body, this.data = const {}});
}
