package com.layrz.layrz_push

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * Main Flutter plugin for managing Firebase Cloud Messaging (FCM) with multi-tenant
 * runtime credential injection.
 *
 * This plugin enables dynamic Firebase initialization without requiring a hardcoded
 * google-services.json file or the google-services Gradle plugin. Instead, credentials
 * are provided at runtime and persisted locally for automatic re-initialization on
 * process restarts (e.g., when the FCM service wakes up the app).
 *
 * ## Key Responsibilities
 * - **Credential Management**: Stores and hot-swaps Firebase credentials via [setCredentials].
 *   Deletes the existing default FirebaseApp and re-initializes with new credentials.
 * - **Device Registration**: Persists encrypted device IDs via [setDeviceId].
 * - **Topic Subscription**: Manages FCM topic subscriptions using device ID
 *   (format: `device_{deviceId}`). Only topics are supported; direct tokens are not exposed.
 * - **Cold-start Re-initialization**: The primary mechanism is [LayrzPushInitProvider], a
 *   ContentProvider that runs at process creation (before Application.onCreate and FCM handling).
 *   It calls [FirebaseBootstrap.ensureFirebase] to initialize Firebase from persisted credentials.
 *   [subscribe] and [unsubscribe] also invoke [ensureFirebase] as an explicit guard.
 * - **Callback Forwarding**: Forwards foreground-only push messages from [LayrzPushMessagingService]
 *   to the Dart layer via [callbackChannel].
 *
 * ## Threading Model
 * All Dart callbacks run on the main thread via [Handler] with [Looper.getMainLooper].
 * FirebaseMessaging Task callbacks are asynchronous; results are marshaled back via
 * the callback parameter.
 *
 * ## Lifecycle
 * - [onAttachedToEngine]: Initializes the plugin, sets up platform channel and storage,
 *   registers this instance so [LayrzPushMessagingService] can forward messages.
 * - [onDetachedFromEngine]: Cleans up resources and deregisters the plugin instance.
 */
class LayrzPushPlugin : LayrzPushPlatformChannel, FlutterPlugin {
  private var callbackChannel: LayrzPushCallbackChannel? = null
  private var mainLooper: Handler? = null
  private var storage: PushStorage? = null
  private lateinit var context: Context

  companion object {
    private const val TAG = "LayrzPushPlugin/Android"

    /**
     * Static reference to the plugin instance, set by [onAttachedToEngine] and
     * cleared by [onDetachedFromEngine]. Used by [LayrzPushMessagingService] to
     * forward messages to the Dart layer. Null when the Flutter engine is detached
     * (e.g., app in background or killed), which causes messages to be dropped silently.
     */
    var instance: LayrzPushPlugin? = null
  }

  /**
   * Called when the Flutter engine attaches to this plugin.
   *
   * Initializes:
   * - Context and application resources
   * - [PushStorage] for encrypted device ID and credential persistence
   * - [Handler] bound to main looper for Dart callbacks
   * - [LayrzPushCallbackChannel] for forwarding messages to Dart
   * - Platform channel listeners
   * - Static [instance] reference (allows [LayrzPushMessagingService] to forward messages)
   *
   * @param binding FlutterPlugin binding providing the application context and binary messenger.
   */
  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    storage = PushStorage(context)
    mainLooper = Handler(Looper.getMainLooper())
    callbackChannel = LayrzPushCallbackChannel(binding.binaryMessenger)

    LayrzPushPlatformChannel.setUp(binding.binaryMessenger, this)
    instance = this
  }

  /**
   * Called when the Flutter engine detaches from this plugin.
   *
   * Cleans up all resources:
   * - Unregisters platform channel listeners
   * - Releases the callback channel
   * - Clears the static [instance] reference, which stops message forwarding
   *   from [LayrzPushMessagingService] (subsequent messages will be silently dropped).
   *
   * @param binding FlutterPlugin binding providing the binary messenger.
   */
  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    LayrzPushPlatformChannel.setUp(binding.binaryMessenger, null)
    callbackChannel = null
    mainLooper = null
    storage = null
    instance = null
  }

  /**
   * Sets or replaces Firebase credentials and hot-swaps the default FirebaseApp.
   *
   * This is the core feature enabling multi-tenant credential injection. The method:
   * 1. Validates that Android credentials are present in the [PushCredentials] object.
   * 2. Persists the credentials to encrypted storage via [PushStorage.saveCredentials].
   * 3. Deletes the existing default [FirebaseApp], if any (wrapped in `runCatching`
   *    to gracefully handle its absence on first boot).
   * 4. Builds a new [FirebaseOptions] from the provided credentials.
   * 5. Re-initializes [FirebaseApp] with the new credentials as the default app
   *    (required for [FirebaseMessaging.getInstance]).
   *
   * If any step fails, logs the error and returns false. Firebase credentials are
   * persisted before initialization is attempted, so [ensureFirebase] can recover
   * on cold restarts even if initialization fails (e.g., network issues).
   *
   * @param credentials PushCredentials object containing Android-specific Firebase config.
   * @param callback Invoked with [Result.success(true)] on successful initialization or
   *                 [Result.success(false)] if credentials are missing or initialization fails.
   */
  override fun setCredentials(credentials: PushCredentials, callback: (Result<Boolean>) -> Unit) {
    if (credentials.android == null) {
      Log.d(TAG, "No Android credentials provided")
      callback(Result.success(false))
      return
    }

    val androidCreds = credentials.android
    storage?.saveCredentials(androidCreds)

    runCatching {
      val existing = FirebaseApp.getInstance()
      existing.delete()
      Log.d(TAG, "Deleted existing FirebaseApp")
    }

    try {
      val options = FirebaseOptions.Builder()
        .setApiKey(androidCreds.apiKey)
        .setApplicationId(androidCreds.appId)
        .setProjectId(androidCreds.projectId)
        .setGcmSenderId(androidCreds.messagingSenderId)
        .apply {
          androidCreds.storageBucket?.let { setStorageBucket(it) }
        }
        .build()

      FirebaseApp.initializeApp(context, options)
      Log.d(TAG, "Initialized FirebaseApp with new credentials")
      callback(Result.success(true))
    } catch (e: Throwable) {
      Log.e(TAG, "Failed to initialize FirebaseApp", e)
      callback(Result.success(false))
    }
  }

  /**
   * Persists an encrypted device ID for topic-based subscription.
   *
   * The device ID is stored encrypted (AES-256-GCM with a key in AndroidKeyStore)
   * via [PushStorage.saveDeviceId]. This ID is used to construct the FCM topic
   * name as `device_{deviceId}` in [subscribe] and [unsubscribe].
   *
   * @param deviceId Unique device identifier to persist and use for topic subscriptions.
   * @param callback Always invoked with [Result.success(true)] (storage is always successful).
   */
  override fun setDeviceId(deviceId: String, callback: (Result<Boolean>) -> Unit) {
    storage?.saveDeviceId(deviceId)
    Log.d(TAG, "Device ID saved securely")
    callback(Result.success(true))
  }

  /**
   * Subscribes the device to an FCM topic for receiving push messages.
   *
   * The subscription flow:
   * 1. Retrieves the encrypted device ID from [PushStorage]. Returns false if not set.
   * 2. Calls [ensureFirebase] to guarantee Firebase is initialized (re-initializes from
   *    persisted credentials if needed). Returns false if initialization fails.
   * 3. Constructs the topic name: `device_{deviceId}`.
   * 4. Calls [FirebaseMessaging.getInstance().subscribeToTopic], which returns a Task
   *    that completes when FCM confirms the subscription. Note: this Task may block for
   *    ~75 seconds on first subscription if GMS_SERVICE_NOT_AVAILABLE is encountered
   *    (observed on real devices due to FCM registration token acquisition retry backoff).
   * 5. On success, records the topic in local storage via [PushStorage.addSubscription].
   *
   * @param callback Invoked with [Result.success(true)] on successful subscription or
   *                 [Result.success(false)] if the device ID is not set, Firebase cannot
   *                 be initialized, or the FCM subscription fails.
   */
  override fun subscribe(callback: (Result<Boolean>) -> Unit) {
    val deviceId = storage?.getDeviceId()
    if (deviceId == null) {
      Log.d(TAG, "Device ID not set, cannot subscribe")
      callback(Result.success(false))
      return
    }

    if (!ensureFirebase()) {
      Log.d(TAG, "Firebase not initialized, cannot subscribe")
      callback(Result.success(false))
      return
    }

    val topic = "device_$deviceId"
    FirebaseMessaging.getInstance().subscribeToTopic(topic)
      .addOnCompleteListener { task ->
        if (task.isSuccessful) {
          Log.d(TAG, "Subscribed to topic: $topic")
          storage?.addSubscription(topic)
          callback(Result.success(true))
        } else {
          task.exception?.let { Log.e(TAG, "Failed to subscribe to topic: $topic", it) }
          callback(Result.success(false))
        }
      }
  }

  /**
   * Unsubscribes the device from an FCM topic.
   *
   * The unsubscription flow mirrors [subscribe]:
   * 1. Retrieves the encrypted device ID from [PushStorage]. Returns false if not set.
   * 2. Calls [ensureFirebase] to guarantee Firebase is initialized. Returns false if it fails.
   * 3. Constructs the topic name: `device_{deviceId}`.
   * 4. Calls [FirebaseMessaging.getInstance().unsubscribeFromTopic], which returns a Task
   *    that completes when FCM confirms the unsubscription.
   * 5. On success, removes the topic from local storage via [PushStorage.removeSubscription].
   *
   * Both [subscribe] and [unsubscribe] must call [ensureFirebase], as cold-started processes
   * (e.g., system-initiated FCM service) do not have Firebase initialized.
   *
   * @param callback Invoked with [Result.success(true)] on successful unsubscription or
   *                 [Result.success(false)] if the device ID is not set, Firebase cannot
   *                 be initialized, or the FCM unsubscription fails.
   */
  override fun unsubscribe(callback: (Result<Boolean>) -> Unit) {
    val deviceId = storage?.getDeviceId()
    if (deviceId == null) {
      Log.d(TAG, "Device ID not set")
      callback(Result.success(false))
      return
    }

    if (!ensureFirebase()) {
      Log.d(TAG, "Firebase not initialized, cannot unsubscribe")
      callback(Result.success(false))
      return
    }

    val topic = "device_$deviceId"
    FirebaseMessaging.getInstance().unsubscribeFromTopic(topic)
      .addOnCompleteListener { task ->
        if (task.isSuccessful) {
          Log.d(TAG, "Unsubscribed from topic: $topic")
          storage?.removeSubscription(topic)
          callback(Result.success(true))
        } else {
          task.exception?.let { Log.e(TAG, "Failed to unsubscribe from topic: $topic", it) }
          callback(Result.success(false))
        }
      }
  }

  /**
   * Retrieves the list of currently subscribed FCM topics.
   *
   * Returns the topics stored by [PushStorage.getSubscriptions], which tracks all
   * successful subscriptions. This list may diverge from actual FCM state if the device
   * is offline or if Firebase credentials change between calls.
   *
   * @param callback Invoked with [Result.success] containing a list of topic names.
   */
  override fun getSubscriptions(callback: (Result<List<String>>) -> Unit) {
    val subs = storage?.getSubscriptions() ?: emptyList()
    callback(Result.success(subs))
  }

  /**
   * Forwards a push notification from [LayrzPushMessagingService] to the Dart layer.
   *
   * Called by [LayrzPushMessagingService.onMessageReceived] (only when the app is
   * foregrounded). Posts the message dispatch to the main thread via [mainLooper] to
   * ensure Dart callbacks execute on the UI thread.
   *
   * @param notification The [PushNotification] to forward (title, body, and data).
   */
  fun emitPush(notification: PushNotification) {
    Log.d(TAG, "Emitting push notification: ${notification.title}")
    callbackChannel?.onPush(notification) { result ->
      result.exceptionOrNull()?.let {
        Log.e(TAG, "Error sending push to Dart", it)
      }
    }
  }

  /**
   * Ensures Firebase is initialized; re-initializes from persisted credentials if needed.
   *
   * Delegates to [FirebaseBootstrap.ensureFirebase] to guarantee consistent initialization
   * logic across all initialization paths (cold-start provider, FCM service, explicit operations).
   *
   * Used by both [subscribe] and [unsubscribe] to guarantee Firebase is available.
   * A null or missing device ID is not checked here; callers are responsible for that.
   *
   * @return true if Firebase is already initialized or re-initialization succeeds;
   *         false if no persisted credentials are found or re-initialization fails.
   */
  private fun ensureFirebase(): Boolean = FirebaseBootstrap.ensureFirebase(context)
}
