package com.layrz.layrz_push

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger

class LayrzPushPlugin : LayrzPushPlatformChannel, FlutterPlugin {
  private var callbackChannel: LayrzPushCallbackChannel? = null
  private var mainLooper: Handler? = null
  private var storage: PushStorage? = null
  private lateinit var context: Context

  companion object {
    private const val TAG = "LayrzPushPlugin/Android"
    var instance: LayrzPushPlugin? = null
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    storage = PushStorage(context)
    mainLooper = Handler(Looper.getMainLooper())
    callbackChannel = LayrzPushCallbackChannel(binding.binaryMessenger)

    LayrzPushPlatformChannel.setUp(binding.binaryMessenger, this)
    instance = this
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    LayrzPushPlatformChannel.setUp(binding.binaryMessenger, null)
    callbackChannel = null
    mainLooper = null
    storage = null
    instance = null
  }

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

  override fun setDeviceId(deviceId: String, callback: (Result<Boolean>) -> Unit) {
    storage?.saveDeviceId(deviceId)
    Log.d(TAG, "Device ID saved securely")
    callback(Result.success(true))
  }

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

  override fun getSubscriptions(callback: (Result<List<String>>) -> Unit) {
    val subs = storage?.getSubscriptions() ?: emptyList()
    callback(Result.success(subs))
  }

  fun emitPush(notification: PushNotification) {
    Log.d(TAG, "Emitting push notification: ${notification.title}")
    callbackChannel?.onPush(notification) { result ->
      result.exceptionOrNull()?.let {
        Log.e(TAG, "Error sending push to Dart", it)
      }
    }
  }

  private fun ensureFirebase(): Boolean {
    if (FirebaseApp.getApps(context).isNotEmpty()) {
      return true
    }

    val creds = storage?.getCredentials()
    if (creds == null) {
      Log.d(TAG, "No stored credentials to re-initialize Firebase")
      return false
    }

    return try {
      val options = FirebaseOptions.Builder()
        .setApiKey(creds.apiKey)
        .setApplicationId(creds.appId)
        .setProjectId(creds.projectId)
        .setGcmSenderId(creds.messagingSenderId)
        .apply {
          creds.storageBucket?.let { setStorageBucket(it) }
        }
        .build()

      FirebaseApp.initializeApp(context, options)
      Log.d(TAG, "Re-initialized Firebase from stored credentials")
      true
    } catch (e: Throwable) {
      Log.e(TAG, "Failed to re-initialize Firebase", e)
      false
    }
  }
}
