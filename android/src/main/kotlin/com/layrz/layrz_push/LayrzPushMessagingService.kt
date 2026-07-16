package com.layrz.layrz_push

import android.os.Handler
import android.os.Looper
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import io.flutter.Log

class LayrzPushMessagingService : FirebaseMessagingService() {
  companion object {
    private const val TAG = "LayrzPushMessagingService/Android"
  }

  override fun onMessageReceived(message: RemoteMessage) {
    super.onMessageReceived(message)

    val notification = PushNotification(
      title = message.notification?.title,
      body = message.notification?.body,
      data = message.data
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

  override fun onNewToken(token: String) {
    super.onNewToken(token)
    Log.d(TAG, "New FCM token received (ignored for topic-only mode)")
  }
}
