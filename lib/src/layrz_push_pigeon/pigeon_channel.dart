import 'dart:async';

import 'package:layrz_push/src/layrz_push_pigeon/layrz_push.g.dart';
import 'package:layrz_push/src/platform_interface.dart';

class LayrzPushPigeonChannel extends LayrzPushPlatform {
  static LayrzPushPigeonChannel? _instance;
  static LayrzPushPigeonChannel get instance => _instance ??= LayrzPushPigeonChannel._();

  final StreamController<PushNotification> _pushController = StreamController<PushNotification>.broadcast();

  @override
  Stream<PushNotification> get onPush => _pushController.stream;

  LayrzPushPigeonChannel._() {
    LayrzPushCallbackChannel.setUp(_LayrzPushCallbackHandler(pushController: _pushController));
  }

  final _channel = LayrzPushPlatformChannel();

  @override
  Future<bool> setCredentials({required PushCredentials credentials}) =>
      _channel.setCredentials(credentials: credentials);

  @override
  Future<bool> setDeviceId({required String deviceId}) => _channel.setDeviceId(deviceId: deviceId);

  @override
  Future<bool> subscribe() => _channel.subscribe();

  @override
  Future<bool> unsubscribe() => _channel.unsubscribe();

  @override
  Future<List<String>> getSubscriptions() => _channel.getSubscriptions();
}

class _LayrzPushCallbackHandler extends LayrzPushCallbackChannel {
  final StreamController<PushNotification> pushController;

  _LayrzPushCallbackHandler({required this.pushController});

  @override
  void onPush(PushNotification notification) {
    pushController.add(notification);
  }
}
