import 'dart:async';

import 'package:layrz_push/src/layrz_push_pigeon/layrz_push.g.dart';

abstract class LayrzPushPlatform {
  /// [onPush] is a stream of push notifications received while the app
  /// is in foreground.
  Stream<PushNotification> get onPush => throw UnimplementedError('onPush has not been implemented.');

  /// [setCredentials] injects (or replaces) the Firebase credentials at runtime.
  Future<bool> setCredentials({required PushCredentials credentials}) =>
      throw UnimplementedError('setCredentials() has not been implemented.');

  /// [setDeviceId] persists the Layrz device ID securely on the device.
  Future<bool> setDeviceId({required String deviceId}) =>
      throw UnimplementedError('setDeviceId() has not been implemented.');

  /// [subscribe] subscribes to the `device_{deviceId}` FCM topic.
  Future<bool> subscribe() => throw UnimplementedError('subscribe() has not been implemented.');

  /// [unsubscribe] unsubscribes from the `device_{deviceId}` FCM topic.
  Future<bool> unsubscribe() => throw UnimplementedError('unsubscribe() has not been implemented.');

  /// [getSubscriptions] returns the list of currently subscribed topics.
  Future<List<String>> getSubscriptions() => throw UnimplementedError('getSubscriptions() has not been implemented.');
}
