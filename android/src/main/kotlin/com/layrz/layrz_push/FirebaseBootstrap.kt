package com.layrz.layrz_push

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import io.flutter.Log

/**
 * Singleton utility for bootstrapping Firebase initialization with runtime credentials.
 *
 * This object provides a single entry point for ensuring Firebase is initialized across
 * multiple initialization paths (plugin attachment, cold-start FCM service, content provider).
 *
 * ## Why This Exists
 *
 * **Cold-start initialization challenge**: When the system wakes up the app process to handle
 * an incoming FCM message (e.g., after a reboot), the app process starts from scratch.
 * The default [FirebaseApp] is not initialized yet, but [LayrzPushMessagingService] immediately
 * needs to access Firebase to handle the message. Without this bootstrap, calling
 * [FirebaseMessaging.getInstance()] throws [IllegalStateException].
 *
 * **Multi-path initialization**: Firebase must be initialized via multiple paths:
 * 1. [LayrzPushInitProvider] — runs at process creation, before Application.onCreate and FCM handling.
 * 2. [LayrzPushMessagingService.onCreate] — redundant guard for the FCM service.
 * 3. [LayrzPushPlugin.subscribe] / [unsubscribe] — explicit Dart-initiated operations.
 *
 * Extracting the logic here ensures all paths use identical logic and the responsibility
 * is centralized.
 *
 * ## Credentials Persistence
 *
 * Credentials are provided via [setCredentials] in [LayrzPushPlugin] and persisted
 * securely via [PushStorage]. This object reads persisted credentials and re-initializes
 * Firebase if it is not yet initialized.
 */
object FirebaseBootstrap {
  private const val TAG = "LayrzPushBootstrap/Android"

  /**
   * Ensures Firebase is initialized; re-initializes from persisted credentials if needed.
   *
   * This is a cold-start guard: when the process is killed and restarted by the system
   * (e.g., the FCM service waking up the app), the default [FirebaseApp] does not exist
   * yet. Calling [FirebaseMessaging.getInstance()] without an initialized default app
   * throws [IllegalStateException]. This method checks if any FirebaseApp is registered
   * and returns true immediately if so. Otherwise, it retrieves persisted credentials
   * from [PushStorage] and re-initializes Firebase.
   *
   * Used by:
   * - [LayrzPushInitProvider.onCreate] — the primary cold-start hook at process creation.
   * - [LayrzPushMessagingService.onCreate] — a redundant guard for the FCM service.
   * - [LayrzPushPlugin.subscribe] / [unsubscribe] — explicit Dart-initiated operations.
   *
   * @param context Application context for accessing SharedPreferences and Firebase APIs.
   * @return true if Firebase is already initialized or re-initialization succeeds;
   *         false if no persisted credentials are found or re-initialization fails.
   */
  fun ensureFirebase(context: Context): Boolean {
    if (FirebaseApp.getApps(context).isNotEmpty()) {
      return true
    }

    val creds = PushStorage(context).getCredentials()
    if (creds == null) {
      Log.d(TAG, "No stored credentials to re-initialize Firebase")
      return false
    }

    return try {
      val options =
        FirebaseOptions
          .Builder()
          .setApiKey(creds.apiKey)
          .setApplicationId(creds.appId)
          .setProjectId(creds.projectId)
          .setGcmSenderId(creds.messagingSenderId)
          .apply {
            creds.storageBucket?.let { setStorageBucket(it) }
          }.build()

      FirebaseApp.initializeApp(context, options)
      Log.d(TAG, "Re-initialized Firebase from stored credentials")
      true
    } catch (e: Throwable) {
      Log.e(TAG, "Failed to re-initialize Firebase", e)
      false
    }
  }
}
