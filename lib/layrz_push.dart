library;

import 'package:layrz_push/src/layrz_push_pigeon/layrz_push.g.dart';
import 'package:layrz_push/src/layrz_push_pigeon/pigeon_channel.dart';
import 'package:layrz_push/src/platform_interface.dart';

export 'package:layrz_push/src/layrz_push_pigeon/layrz_push.g.dart'
    show PushCredentials, AndroidPushCredentials, IosPushCredentials, PushNotification;
export 'package:layrz_push/src/platform_interface.dart' show LayrzPushPlatform;

class LayrzPush {
  /// [_platform] is the platform interface for the LayrzPush plugin.
  static LayrzPushPlatform _platform = LayrzPushPigeonChannel.instance;

  /// [setInstance] is used to set the platform interface for the LayrzPush plugin.
  static void setInstance(LayrzPushPlatform instance) => _platform = instance;

  /// [onPush] is a stream of push notifications received while the app is in foreground.
  ///
  /// When the app is in background or terminated, notifications are displayed
  /// by the system and never reach this stream.
  Stream<PushNotification> get onPush => _platform.onPush;

  /// [setCredentials] injects (or replaces) the Firebase credentials at runtime.
  ///
  /// Each platform reads its own sub-object of [PushCredentials] and ignores
  /// the other one. If a Firebase app is already configured, it's deleted and
  /// re-created with the new options, allowing hot-swap between tenants.
  Future<bool> setCredentials({required PushCredentials credentials}) {
    return _platform.setCredentials(credentials: credentials);
  }

  /// [setDeviceId] persists the Layrz device ID securely on the device.
  ///
  /// The device ID defines the FCM topic used by [subscribe] and
  /// [unsubscribe], following the format `device_{deviceId}`.
  Future<bool> setDeviceId({required String deviceId}) {
    return _platform.setDeviceId(deviceId: deviceId);
  }

  /// [subscribe] subscribes to the `device_{deviceId}` FCM topic.
  ///
  /// Requires [setCredentials] and [setDeviceId] to be called first,
  /// otherwise it returns `false`.
  Future<bool> subscribe() {
    return _platform.subscribe();
  }

  /// [unsubscribe] unsubscribes from the `device_{deviceId}` FCM topic.
  Future<bool> unsubscribe() {
    return _platform.unsubscribe();
  }

  /// [getSubscriptions] returns the list of currently subscribed topics.
  ///
  /// FCM does not provide a native API for this, so the list is tracked
  /// locally on each subscribe/unsubscribe call.
  Future<List<String>> getSubscriptions() {
    return _platform.getSubscriptions();
  }
}
