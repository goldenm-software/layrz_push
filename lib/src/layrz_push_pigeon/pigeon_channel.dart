import 'dart:async';

import 'package:layrz_push/src/layrz_push_pigeon/layrz_push.g.dart';
import 'package:layrz_push/src/platform_interface.dart';

/// Production implementation of [LayrzPushPlatform] using Pigeon-generated channels.
///
/// This is a lazy singleton that manages:
/// 1. Communication with native code via Pigeon platform channels
/// 2. A broadcast StreamController for foreground push notifications
/// 3. A callback handler that receives native callbacks and feeds them into the stream
///
/// Initialization happens in the constructor: it sets up the Flutter-side callback
/// handler via [LayrzPushCallbackChannel.setUp], which allows native code to invoke
/// the [_LayrzPushCallbackHandler.onPush] method when notifications arrive.
///
/// All platform method calls ([setCredentials], [setDeviceId], etc.) are delegated
/// to the Pigeon-generated [LayrzPushPlatformChannel], which routes them to native code.
class LayrzPushPigeonChannel extends LayrzPushPlatform {
  /// Lazy singleton instance.
  ///
  /// Initialized on first access via the [instance] getter. Ensures only one
  /// callback handler is registered and only one stream controller is created.
  static LayrzPushPigeonChannel? _instance;

  /// Returns the singleton instance, creating it if necessary.
  static LayrzPushPigeonChannel get instance =>
      _instance ??= LayrzPushPigeonChannel._();

  /// StreamController for broadcasting foreground push notifications.
  ///
  /// Created as a broadcast stream to allow multiple simultaneous listeners.
  /// New listeners will not receive notifications that arrived before they subscribed
  /// (unlike a regular stream controller).
  final StreamController<PushNotification> _pushController =
      StreamController<PushNotification>.broadcast();

  /// Public stream of foreground push notifications.
  ///
  /// Emits [PushNotification] objects when the app is in the foreground and a
  /// notification arrives. The backing stream controller is a broadcast stream,
  /// so multiple listeners are supported.
  @override
  Stream<PushNotification> get onPush => _pushController.stream;

  /// Creates the singleton instance and sets up the native callback handler.
  ///
  /// The constructor is private; use [instance] to access the singleton.
  /// During construction:
  /// 1. [_pushController] is created
  /// 2. [LayrzPushCallbackChannel.setUp] is called with a [_LayrzPushCallbackHandler]
  ///    to register the Flutter-side callback that receives native notifications
  LayrzPushPigeonChannel._() {
    LayrzPushCallbackChannel.setUp(
      _LayrzPushCallbackHandler(pushController: _pushController),
    );
  }

  /// Pigeon-generated platform channel for calling native methods.
  ///
  /// This channel handles serialization/deserialization of method calls and
  /// responses across the Dart-native boundary.
  final _channel = LayrzPushPlatformChannel();

  @override
  Future<bool> setCredentials({required PushCredentials credentials}) =>
      _channel.setCredentials(credentials: credentials);

  @override
  Future<bool> setDeviceId({required String deviceId}) =>
      _channel.setDeviceId(deviceId: deviceId);

  @override
  Future<String?> getDeviceId() => _channel.getDeviceId();

  @override
  Future<bool> subscribe() => _channel.subscribe();

  @override
  Future<bool> unsubscribe() => _channel.unsubscribe();

  @override
  Future<List<String>> getSubscriptions() => _channel.getSubscriptions();
}

/// Private callback handler for receiving native push notifications.
///
/// This class is registered with the Pigeon-generated [LayrzPushCallbackChannel]
/// to handle callbacks from native code. The separation into a private handler
/// class avoids a naming collision: the Pigeon-generated [LayrzPushCallbackChannel]
/// has an abstract method `onPush(PushNotification notification)`, but
/// [LayrzPushPigeonChannel] exposes a getter `Stream<PushNotification> get onPush`.
/// A single class cannot have both a method and a getter with the same name,
/// so this handler is split out.
///
/// When native code invokes the Flutter callback, it routes to this handler's
/// [onPush] method, which adds the notification to the stream controller.
class _LayrzPushCallbackHandler extends LayrzPushCallbackChannel {
  /// Reference to the StreamController that feeds notifications to listeners.
  final StreamController<PushNotification> pushController;

  /// Creates the handler with a reference to the notification stream controller.
  _LayrzPushCallbackHandler({required this.pushController});

  /// Called by native code when a foreground push notification arrives.
  ///
  /// Adds the [notification] to the broadcast stream so all listeners to
  /// [LayrzPushPigeonChannel.onPush] receive it.
  @override
  void onPush(PushNotification notification) {
    pushController.add(notification);
  }
}
