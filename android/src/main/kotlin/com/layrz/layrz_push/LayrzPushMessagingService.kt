package com.layrz.layrz_push

import android.os.Handler
import android.os.Looper
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import io.flutter.Log

/**
 * Firebase Cloud Messaging (FCM) service that receives push notifications from FCM
 * and forwards them to the Flutter plugin for delivery to the Dart layer.
 *
 * ## Key Design Points
 *
 * **Foreground-only delivery**: [onMessageReceived] is invoked ONLY when the app is
 * foregrounded. When the app is backgrounded or killed:
 * - Notification-type FCM messages go directly to the system notification tray (handled by the system).
 * - Data-only messages are dropped (not delivered to the app unless the app is running).
 *
 * This service is instantiated by the system, not by the plugin, so it uses the static
 * [LayrzPushPlugin.instance] reference to forward messages. If the plugin has not
 * attached (or has detached), [instance] is null → messages are silently dropped,
 * which is correct for the foreground-only contract.
 *
 * **Threading**: All calls to [LayrzPushPlugin.emitPush] are posted to the main thread
 * via [Handler] with [Looper.getMainLooper] to ensure Dart callbacks execute on the UI thread.
 *
 * **Token handling**: [onNewToken] is deliberately a no-op. The FCM registration token
 * is not exposed; the plugin is topics-only (format: `device_{deviceId}`).
 */
class LayrzPushMessagingService : FirebaseMessagingService() {
  companion object {
    private const val TAG = "LayrzPushMessagingService/Android"
  }

  /**
   * Called when the service is created (e.g., when the system instantiates it to handle
   * an incoming FCM message).
   *
   * This is a redundant safety guard: Firebase should already be initialized by
   * [LayrzPushInitProvider.onCreate] at process startup. However, this guard ensures
   * Firebase is initialized even if the provider path changes or fails for unexpected
   * reasons. Never throws; logs errors without propagation.
   */
  override fun onCreate() {
    super.onCreate()
    runCatching {
      FirebaseBootstrap.ensureFirebase(applicationContext)
    }.onFailure { e ->
      Log.e(TAG, "Error ensuring Firebase in service onCreate", e)
    }
  }

  /**
   * Receives a push notification from FCM when the app is in the foreground.
   *
   * Foreground semantics:
   * - When the app is foregrounded, this callback is invoked for notification-type
   *   FCM messages AND data-only messages.
   * - When the app is backgrounded or killed, this callback is NOT invoked.
   *   Notification-type messages go to the system tray; data-only messages are dropped.
   *
   * The method:
   * 1. Extracts the title, body, and data payload from the [RemoteMessage].
   * 2. Checks if [LayrzPushPlugin.instance] is attached (non-null).
   *    - If null, the plugin is not attached or has detached (e.g., engine destroyed).
   *      Silently drops the message, which is correct for the foreground-only contract.
   * 3. Posts the message delivery to the main thread via [Handler] and [Looper.getMainLooper]
   *    to ensure all Dart callbacks run on the UI thread.
   * 4. Calls [LayrzPushPlugin.emitPush] to forward the notification to Dart.
   *
   * @param message The [RemoteMessage] from FCM containing notification and data payloads.
   */
  override fun onMessageReceived(message: RemoteMessage) {
    super.onMessageReceived(message)

    val notification = PushNotification(
      title = message.notification?.title,
      body = message.notification?.body,
      data = message.data,
    )

    val instance = LayrzPushPlugin.instance
    if (instance == null) {
      Log.d(TAG, "Plugin instance not attached, dropping notification")
      return
    }

    Handler(Looper.getMainLooper()).post {
      instance.emitPush(notification)
    }
  }

  /**
   * Called when a new FCM registration token is generated or refreshed.
   *
   * This is deliberately a no-op. The plugin is topics-only (subscribing to topics
   * like `device_{deviceId}`), and the FCM registration token is not exposed to
   * the Dart layer or persisted. Topic subscriptions manage device routing.
   *
   * @param token The new FCM registration token (ignored).
   */
  override fun onNewToken(token: String) {
    super.onNewToken(token)
    Log.d(TAG, "New FCM token received (ignored for topic-only mode)")
  }
}
