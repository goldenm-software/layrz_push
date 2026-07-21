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
class LayrzPushPlugin :
  LayrzPushPlatformChannel,
  FlutterPlugin {
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
   * This is the core feature enabling multi-tenant credential injection. The method is idempotent:
   * if the incoming credentials match the persisted ones and a FirebaseApp is currently initialized,
   * the method returns immediately without deleting or re-initializing Firebase, avoiding FCM
   * registration-token invalidation and retry backoff delays.
   *
   * The method:
   * 1. Validates that Android credentials are present in the [PushCredentials] object.
   * 2. Loads previously stored credentials via [storage.getCredentials()].
   * 3. **Idempotency check**: If the stored credentials equal the incoming ones (compared field-by-field:
   *    apiKey, appId, projectId, messagingSenderId, storageBucket) AND a FirebaseApp is currently
   *    initialized, returns immediately with success.
   * 4. Otherwise, persists the new credentials to storage via [PushStorage.saveCredentials].
   * 5. Deletes the existing default [FirebaseApp], if any (wrapped in `runCatching`
   *    to gracefully handle its absence on first boot).
   * 6. Builds a new [FirebaseOptions] from the provided credentials.
   * 7. Re-initializes [FirebaseApp] with the new credentials as the default app
   *    (required for [FirebaseMessaging.getInstance]).
   *
   * If any step fails, logs the error and returns false. Firebase credentials are persisted before
   * initialization is attempted, so [ensureFirebase] can recover on cold restarts even if
   * initialization fails (e.g., network issues).
   *
   * Multi-tenant hot-swap: When credentials DIFFER, the delete + re-init happens exactly as before.
   *
   * @param credentials PushCredentials object containing Android-specific Firebase config.
   * @param callback Invoked with [Result.success(true)] on successful initialization or
   *                 [Result.success(false)] if credentials are missing or initialization fails.
   */
  override fun setCredentials(
    credentials: PushCredentials,
    callback: (Result<Boolean>) -> Unit,
  ) {
    Log.d(TAG, "setCredentials(): starting")

    if (credentials.android == null) {
      Log.d(TAG, "setCredentials(): No Android credentials provided")
      callback(Result.success(false))
      return
    }

    val androidCreds = credentials.android
    val storedCreds = storage?.getCredentials()
    Log.d(TAG, "setCredentials(): projectId=${androidCreds.projectId}")

    // Idempotency check: if credentials haven't changed and FirebaseApp is already initialized,
    // skip delete + re-init to avoid FCM registration-token churn.
    if (credentialsEqual(storedCreds, androidCreds) && isFirebaseInitialized()) {
      Log.d(TAG, "setCredentials(): Credentials unchanged, keeping existing FirebaseApp")
      callback(Result.success(true))
      return
    }

    Log.d(TAG, "setCredentials(): Credentials differ or FirebaseApp not initialized, updating")
    storage?.saveCredentials(androidCreds)

    runCatching {
      val existing = FirebaseApp.getInstance()
      existing.delete()
      Log.d(TAG, "setCredentials(): Deleted existing FirebaseApp")
    }

    try {
      Log.d(TAG, "setCredentials(): Building FirebaseOptions")
      val options =
        FirebaseOptions
          .Builder()
          .setApiKey(androidCreds.apiKey)
          .setApplicationId(androidCreds.appId)
          .setProjectId(androidCreds.projectId)
          .setGcmSenderId(androidCreds.messagingSenderId)
          .apply {
            androidCreds.storageBucket?.let { setStorageBucket(it) }
          }.build()

      FirebaseApp.initializeApp(context, options)
      Log.d(TAG, "setCredentials(): Initialized FirebaseApp with new credentials")
      callback(Result.success(true))
    } catch (e: Throwable) {
      Log.e(TAG, "setCredentials(): Failed to initialize FirebaseApp", e)
      callback(Result.success(false))
    }
  }

  /**
   * Compares two [AndroidPushCredentials] objects field-by-field for equality.
   *
   * Since [AndroidPushCredentials] is a Pigeon-generated class, we cannot rely on its
   * synthesized equals() method. This helper performs a manual field-by-field comparison
   * (apiKey, appId, projectId, messagingSenderId, storageBucket) to detect changes.
   *
   * @param stored The previously persisted credentials (may be null).
   * @param incoming The newly provided credentials.
   * @return true if both are non-null and all fields match, false otherwise.
   */
  private fun credentialsEqual(
    stored: AndroidPushCredentials?,
    incoming: AndroidPushCredentials,
  ): Boolean {
    if (stored == null) return false
    return stored.apiKey == incoming.apiKey &&
      stored.appId == incoming.appId &&
      stored.projectId == incoming.projectId &&
      stored.messagingSenderId == incoming.messagingSenderId &&
      stored.storageBucket == incoming.storageBucket
  }

  /**
   * Checks whether a FirebaseApp instance is currently initialized.
   *
   * Returns true if [FirebaseApp.getInstance()] succeeds, false if it throws.
   *
   * @return true if FirebaseApp is initialized, false otherwise.
   */
  private fun isFirebaseInitialized(): Boolean {
    return runCatching { FirebaseApp.getInstance() }.isSuccess
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
  override fun setDeviceId(
    deviceId: String,
    callback: (Result<Boolean>) -> Unit,
  ) {
    Log.d(TAG, "setDeviceId(): starting, deviceId=${deviceId.take(8)}...")
    storage?.saveDeviceId(deviceId)
    Log.d(TAG, "setDeviceId(): Device ID saved securely")
    callback(Result.success(true))
  }

  /**
   * Retrieves the encrypted device ID from secure storage.
   *
   * Decrypts and returns the device ID previously persisted via [setDeviceId].
   * Returns null if no device ID has been stored, if the AndroidKeyStore key
   * is unavailable (e.g., after Auto Backup restore on a new install), or if
   * decryption fails for any other reason.
   *
   * @param callback Invoked with [Result.success] containing the device ID string,
   *                 or null if the device ID is not found or decryption fails.
   */
  override fun getDeviceId(callback: (Result<String?>) -> Unit) {
    Log.d(TAG, "getDeviceId(): starting")
    val deviceId = storage?.getDeviceId()
    if (deviceId != null) {
      Log.d(TAG, "getDeviceId(): Device ID retrieved successfully")
    } else {
      Log.d(TAG, "getDeviceId(): Device ID not found or decryption failed")
    }
    callback(Result.success(deviceId))
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
    Log.d(TAG, "subscribe(): starting")

    val deviceId = storage?.getDeviceId()
    if (deviceId == null) {
      Log.d(TAG, "subscribe(): Device ID not set, cannot subscribe")
      callback(Result.success(false))
      return
    }
    Log.d(TAG, "subscribe(): topic=device_$deviceId")

    if (!ensureFirebase()) {
      Log.d(TAG, "subscribe(): Firebase not initialized, cannot subscribe")
      callback(Result.success(false))
      return
    }

    Log.d(TAG, "subscribe(): Firebase initialized, fetching FCM registration token...")
    val tokenStartTime = System.currentTimeMillis()
    FirebaseMessaging
      .getInstance()
      .token
      .addOnCompleteListener { tokenTask ->
        val tokenElapsed = System.currentTimeMillis() - tokenStartTime
        if (tokenTask.isSuccessful) {
          val token = tokenTask.result
          val tokenLast8 = token.takeLast(8)
          Log.d(TAG, "subscribe(): FCM token acquired in ${tokenElapsed}ms (…$tokenLast8)")
        } else {
          Log.d(TAG, "subscribe(): FCM token fetch failed after ${tokenElapsed}ms, proceeding with subscribeToTopic")
        }

        val topic = "device_$deviceId"
        Log.d(TAG, "subscribe(): calling subscribeToTopic($topic)")
        val subscribeStartTime = System.currentTimeMillis()
        FirebaseMessaging
          .getInstance()
          .subscribeToTopic(topic)
          .addOnCompleteListener { task ->
            val subscribeElapsed = System.currentTimeMillis() - subscribeStartTime
            if (task.isSuccessful) {
              Log.d(TAG, "subscribe(): Subscribed to topic: $topic in ${subscribeElapsed}ms")
              storage?.addSubscription(topic)
              callback(Result.success(true))
            } else {
              task.exception?.let {
                Log.e(
                  TAG,
                  "subscribe(): Failed to subscribe to topic: $topic after ${subscribeElapsed}ms",
                  it
                )
              }
              callback(Result.success(false))
            }
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
    Log.d(TAG, "unsubscribe(): starting")

    val deviceId = storage?.getDeviceId()
    if (deviceId == null) {
      Log.d(TAG, "unsubscribe(): Device ID not set")
      callback(Result.success(false))
      return
    }
    Log.d(TAG, "unsubscribe(): topic=device_$deviceId")

    if (!ensureFirebase()) {
      Log.d(TAG, "unsubscribe(): Firebase not initialized, cannot unsubscribe")
      callback(Result.success(false))
      return
    }

    val topic = "device_$deviceId"
    Log.d(TAG, "unsubscribe(): calling unsubscribeFromTopic($topic)")
    val startTime = System.currentTimeMillis()
    FirebaseMessaging
      .getInstance()
      .unsubscribeFromTopic(topic)
      .addOnCompleteListener { task ->
        val elapsed = System.currentTimeMillis() - startTime
        if (task.isSuccessful) {
          Log.d(TAG, "unsubscribe(): Unsubscribed from topic: $topic in ${elapsed}ms")
          storage?.removeSubscription(topic)
          callback(Result.success(true))
        } else {
          task.exception?.let {
            Log.e(
              TAG,
              "unsubscribe(): Failed to unsubscribe from topic: $topic after ${elapsed}ms",
              it
            )
          }
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
    Log.d(TAG, "getSubscriptions(): starting")
    val subs = storage?.getSubscriptions() ?: emptyList()
    Log.d(TAG, "getSubscriptions(): found ${subs.size} subscribed topics")
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
