library;

import 'package:layrz_push/src/layrz_push_pigeon/layrz_push.g.dart';
import 'package:layrz_push/src/layrz_push_pigeon/pigeon_channel.dart';
import 'package:layrz_push/src/platform_interface.dart';

export 'package:layrz_push/src/layrz_push_pigeon/layrz_push.g.dart'
    show PushCredentials, AndroidPushCredentials, IosPushCredentials, PushNotification;
export 'package:layrz_push/src/platform_interface.dart' show LayrzPushPlatform;

/// Main facade for the Layrz Push plugin.
///
/// Provides a singleton-based API for managing Firebase Cloud Messaging (FCM)
/// subscriptions and handling foreground push notifications. All methods are
/// delegated to the underlying platform interface (usually [LayrzPushPigeonChannel],
/// but can be overridden for testing).
///
/// The plugin is designed for multi-tenant support: different Layrz clients
/// can inject their own Firebase credentials at runtime via [setCredentials],
/// enabling hot-swap between different Firebase projects without app restart.
///
/// Typical usage flow:
/// 1. Request notification permission from the user
/// 2. Call [setCredentials] with your Firebase credentials
/// 3. Call [setDeviceId] with your Layrz device ID
/// 4. Call [subscribe] to start receiving notifications for `device_{deviceId}`
/// 5. Listen to [onPush] to handle foreground notifications
/// 6. Call [unsubscribe] when no longer needed (e.g., on logout)
class LayrzPush {
  /// The platform interface instance used by this facade.
  ///
  /// Defaults to [LayrzPushPigeonChannel.instance] for production use.
  /// Can be replaced via [setInstance] for testing with mock implementations.
  static LayrzPushPlatform _platform = LayrzPushPigeonChannel.instance;

  /// Sets a custom platform interface implementation.
  ///
  /// Primarily used for testing with mock or fake implementations.
  /// In production, the default [LayrzPushPigeonChannel] is used.
  ///
  /// Example (for testing):
  /// ```dart
  /// LayrzPush.setInstance(MyMockLayrzPushPlatform());
  /// ```
  static void setInstance(LayrzPushPlatform instance) => _platform = instance;

  /// Stream of push notifications received while the app is in foreground.
  ///
  /// Emits [PushNotification] objects when the app is actively running and
  /// a push notification arrives. Does NOT fire when the app is in the
  /// background or terminated — in those cases, the system displays the
  /// notification directly.
  ///
  /// No system banner is shown in the foreground on either Android or iOS
  /// (parity with background behavior where the system displays the banner).
  ///
  /// This is a broadcast stream, so multiple listeners are supported.
  Stream<PushNotification> get onPush => _platform.onPush;

  /// Injects (or replaces) the Firebase credentials at runtime.
  ///
  /// Enables hot-swapping between different Firebase projects, supporting
  /// multi-tenant scenarios. Each platform (Android/iOS) reads only its own
  /// credential object and ignores the other.
  ///
  /// If Firebase is already configured, it is deleted and re-initialized
  /// with the new credentials.
  ///
  /// Parameters:
  ///   - [credentials]: A [PushCredentials] object containing platform-specific
  ///     Firebase credentials from `google-services.json` (Android) and/or
  ///     `GoogleService-Info.plist` (iOS).
  ///
  /// Returns `true` if credentials were successfully applied, `false` otherwise.
  ///
  /// Note: Credentials typically do not change during app runtime, but the
  /// ability to update them at runtime is essential for multi-tenant support.
  Future<bool> setCredentials({required PushCredentials credentials}) {
    return _platform.setCredentials(credentials: credentials);
  }

  /// Persists the Layrz device ID securely on the device.
  ///
  /// The device ID is used to construct the FCM topic name for subscriptions:
  /// `device_{deviceId}`. Must be called before [subscribe] and [unsubscribe].
  ///
  /// Storage details:
  ///   - Android: AES-GCM encrypted in SharedPreferences (via Android Keystore)
  ///   - iOS: Stored in Keychain (survives app uninstall)
  ///
  /// Parameters:
  ///   - [deviceId]: The Layrz device ID (typically a UUID or alphanumeric string).
  ///
  /// Returns `true` if the device ID was successfully persisted, `false` otherwise.
  ///
  /// Note: On iOS, the persisted device ID survives app uninstall due to
  /// Keychain behavior. Ensure this is the desired behavior for your use case.
  Future<bool> setDeviceId({required String deviceId}) {
    return _platform.setDeviceId(deviceId: deviceId);
  }

  /// Subscribes to the `device_{deviceId}` FCM topic.
  ///
  /// Registers the device with FCM to receive messages sent to the topic
  /// `device_{deviceId}`. Requires both [setCredentials] and [setDeviceId]
  /// to have been called successfully.
  ///
  /// On the first subscription after a fresh install, FCM must obtain its
  /// registration token from Google Mobile Services (GMS). This can be slow:
  ///   - Typical: 1-5 seconds
  ///   - With transient GMS errors and retries: up to 75 seconds observed
  ///
  /// The returned Future completes once FCM finishes initialization.
  ///
  /// The subscription is tracked locally; subsequent calls to [getSubscriptions]
  /// will include the new topic.
  ///
  /// Returns `true` if the subscription succeeded, `false` if:
  ///   - Credentials are not set (call [setCredentials] first)
  ///   - Device ID is not set (call [setDeviceId] first)
  ///   - The native subscribe operation failed
  ///
  /// Precondition: Call [setCredentials] and [setDeviceId] first.
  Future<bool> subscribe() {
    return _platform.subscribe();
  }

  /// Unsubscribes from the `device_{deviceId}` FCM topic.
  ///
  /// Removes the device from the FCM topic `device_{deviceId}`. Requires
  /// [setDeviceId] to have been called first.
  ///
  /// The subscription is tracked locally; subsequent calls to [getSubscriptions]
  /// will not include the unsubscribed topic.
  ///
  /// Returns `true` if the unsubscription succeeded, `false` if:
  ///   - Device ID is not set (call [setDeviceId] first)
  ///   - The native unsubscribe operation failed
  ///
  /// Precondition: Call [setDeviceId] first.
  Future<bool> unsubscribe() {
    return _platform.unsubscribe();
  }

  /// Returns the list of currently subscribed FCM topics.
  ///
  /// FCM does not provide a native API to query subscribed topics, so this
  /// plugin maintains a local list that is updated on each [subscribe] and
  /// [unsubscribe] call. This method returns that locally-tracked list.
  ///
  /// Returns a list of topic strings (e.g., `['device_12345']`), or an empty
  /// list if no topics are subscribed.
  ///
  /// Note: This reflects only the subscriptions tracked by this plugin instance.
  /// If subscriptions were made in another app instance or on another device
  /// with the same device ID, they will not appear in this list.
  Future<List<String>> getSubscriptions() {
    return _platform.getSubscriptions();
  }
}
