import 'dart:async';

import 'package:layrz_push/src/layrz_push_pigeon/layrz_push.g.dart';

/// Abstract interface for the Layrz Push plugin's platform implementation.
///
/// This class defines the contract that all platform implementations must follow.
/// It uses the "platform interface" pattern, common in Flutter plugins, to allow:
///
/// 1. **Production usage**: The default implementation [LayrzPushPigeonChannel]
///    uses Pigeon-generated method channels to communicate with native code.
///
/// 2. **Testing**: Tests and mock implementations can override [LayrzPush.setInstance]
///    with a test double (fake, mock, or stub) that implements this interface
///    without calling native code.
///
/// The pattern works by having [LayrzPush] delegate all method calls to a
/// static instance of [LayrzPushPlatform]. The default is the Pigeon
/// implementation, but tests can swap it out.
///
/// Methods throw [UnimplementedError] by default, allowing subclasses to
/// override only what they need while catching accidental missing overrides
/// at compile-time (warnings) or runtime.
abstract class LayrzPushPlatform {
  /// Stream of push notifications received while the app is in foreground.
  ///
  /// Subclasses must return a stream that emits [PushNotification] objects
  /// when notifications arrive in the foreground, and never emits when the
  /// app is in the background or terminated.
  Stream<PushNotification> get onPush =>
      throw UnimplementedError('onPush has not been implemented.');

  /// Injects (or replaces) the Firebase credentials at runtime.
  ///
  /// Subclasses must implement credential injection and, if needed, Firebase
  /// app re-initialization. Supports multi-tenant scenarios by allowing
  /// hot-swap of credentials.
  Future<bool> setCredentials({required PushCredentials credentials}) =>
      throw UnimplementedError('setCredentials() has not been implemented.');

  /// Persists the Layrz device ID securely on the device.
  ///
  /// Subclasses must implement secure storage (Keystore/Keychain) and ensure
  /// the ID survives app restarts. The ID is used to construct the FCM topic.
  Future<bool> setDeviceId({required String deviceId}) =>
      throw UnimplementedError('setDeviceId() has not been implemented.');

  /// Retrieves the persisted Layrz device ID from secure storage.
  ///
  /// Subclasses must implement retrieval from secure storage (Keystore/Keychain).
  /// Returns null if the device ID has never been set or if retrieval fails.
  Future<String?> getDeviceId() =>
      throw UnimplementedError('getDeviceId() has not been implemented.');

  /// Subscribes to the `device_{deviceId}` FCM topic.
  ///
  /// Subclasses must implement FCM subscription logic, handling potential
  /// first-time slowness (FCM token fetch) and tracking subscriptions locally.
  Future<bool> subscribe() =>
      throw UnimplementedError('subscribe() has not been implemented.');

  /// Unsubscribes from the `device_{deviceId}` FCM topic.
  ///
  /// Subclasses must implement FCM unsubscription logic and update the local
  /// subscription tracking list.
  Future<bool> unsubscribe() =>
      throw UnimplementedError('unsubscribe() has not been implemented.');

  /// Returns the list of currently subscribed FCM topics.
  ///
  /// Subclasses must return the locally-tracked list of subscribed topics.
  /// FCM does not provide a native API for this, so implementations must
  /// maintain their own list.
  Future<List<String>> getSubscriptions() =>
      throw UnimplementedError('getSubscriptions() has not been implemented.');
}
