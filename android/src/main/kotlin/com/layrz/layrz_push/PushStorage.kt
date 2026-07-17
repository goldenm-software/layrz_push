package com.layrz.layrz_push

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import org.json.JSONObject
import java.nio.ByteBuffer
import java.security.KeyStore
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Manages persistent storage for push credentials, device IDs, and topic subscriptions.
 *
 * ## Storage Tiers
 *
 * **Encrypted Storage (AndroidKeyStore)**:
 * - Device ID: Encrypted with AES-256-GCM using a key stored in AndroidKeyStore (alias: `layrz_push_key`).
 *   The key never leaves the Keystore. Prefs store only the base64-encoded ciphertext and IV.
 *   If decryption fails (e.g., Auto Backup restored prefs on a new install without the Keystore key),
 *   [getDeviceId] returns null gracefully.
 *
 * **Plain SharedPreferences** (by design):
 * - Credentials: Firebase config (API key, app ID, project ID, messaging sender ID, storage bucket).
 * - Subscriptions: List of subscribed topic names.
 *   These are stored unencrypted because [LayrzPushMessagingService] must read credentials on cold
 *   start (before Dart code runs), and these values are not secret-grade in a multi-tenant system.
 *
 * ## Device ID Lifecycle
 *
 * [saveDeviceId] encrypts and persists a device ID. [getDeviceId] decrypts and returns it.
 * If the AndroidKeyStore key is unavailable (e.g., Auto Backup scenario), [getDeviceId] returns null,
 * causing [subscribe] to fail. Calling [setDeviceId] again re-creates the key and re-encrypts
 * the device ID.
 *
 * ## Subscription Tracking
 *
 * [addSubscription] and [removeSubscription] manage a local set of subscribed topics,
 * updated after successful FCM subscription/unsubscription. This list may diverge from
 * actual FCM state if the device is offline or if credentials change.
 */
class PushStorage(context: Context) {
  private val prefs: SharedPreferences = context.getSharedPreferences(
    "com.layrz.layrz_push.storage",
    Context.MODE_PRIVATE
  )

  private val keyStore: KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

  companion object {
    private const val PREFS_CREDENTIALS = "credentials"
    private const val PREFS_DEVICE_ID_ENC = "device_id_enc"
    private const val PREFS_DEVICE_ID_IV = "device_id_iv"
    private const val PREFS_SUBSCRIPTIONS = "subscriptions"
    private const val KEY_ALIAS = "layrz_push_key"
    private const val GCM_TAG_LENGTH = 128
  }

  /**
   * Persists Firebase credentials as a JSON string in SharedPreferences.
   *
   * Stores the API key, app ID, project ID, messaging sender ID, and optional storage bucket.
   * These are stored unencrypted and must be read on cold start by [LayrzPushMessagingService]
   * before the Dart layer initializes [LayrzPushPlugin].
   *
   * @param credentials [AndroidPushCredentials] containing Firebase configuration.
   */
  fun saveCredentials(credentials: AndroidPushCredentials) {
    val json = JSONObject().apply {
      put("apiKey", credentials.apiKey)
      put("appId", credentials.appId)
      put("projectId", credentials.projectId)
      put("messagingSenderId", credentials.messagingSenderId)
      credentials.storageBucket?.let { put("storageBucket", it) }
    }
    prefs.edit().putString(PREFS_CREDENTIALS, json.toString()).apply()
  }

  /**
   * Retrieves persisted Firebase credentials.
   *
   * Parses the stored JSON string and reconstructs an [AndroidPushCredentials] object.
   * Returns null if no credentials are stored or if JSON parsing fails.
   *
   * Used by [LayrzPushPlugin.ensureFirebase] to re-initialize Firebase on cold start.
   *
   * @return [AndroidPushCredentials] if found and valid, null otherwise.
   */
  fun getCredentials(): AndroidPushCredentials? {
    val json = prefs.getString(PREFS_CREDENTIALS, null) ?: return null
    return try {
      val obj = JSONObject(json)
      AndroidPushCredentials(
        apiKey = obj.getString("apiKey"),
        appId = obj.getString("appId"),
        projectId = obj.getString("projectId"),
        messagingSenderId = obj.getString("messagingSenderId"),
        storageBucket = if (obj.has("storageBucket")) obj.getString("storageBucket") else null
      )
    } catch (e: Exception) {
      null
    }
  }

  /**
   * Encrypts and persists a device ID using AES-256-GCM.
   *
   * Encryption details:
   * 1. Retrieves or generates a SecretKey stored in AndroidKeyStore (alias: `layrz_push_key`).
   *    The key never leaves the Keystore.
   * 2. Initializes an AES/GCM cipher in encrypt mode. GCM automatically generates and
   *    prepends the IV (initialization vector).
   * 3. Encrypts the device ID bytes. The IV is extracted from the cipher.
   * 4. Base64-encodes both the IV and ciphertext and stores them in SharedPreferences.
   *
   * The IV is stored unencrypted (required to decrypt later), but the ciphertext is
   * authenticated by the GCM tag.
   *
   * @param deviceId The device ID string to encrypt and persist.
   */
  fun saveDeviceId(deviceId: String) {
    val key = getOrCreateKey()
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.ENCRYPT_MODE, key)

    val iv = cipher.iv
    val encryptedData = cipher.doFinal(deviceId.toByteArray())

    val ivB64 = Base64.getEncoder().encodeToString(iv)
    val encB64 = Base64.getEncoder().encodeToString(encryptedData)

    prefs.edit()
      .putString(PREFS_DEVICE_ID_IV, ivB64)
      .putString(PREFS_DEVICE_ID_ENC, encB64)
      .apply()
  }

  /**
   * Decrypts and retrieves the persisted device ID.
   *
   * Decryption details:
   * 1. Retrieves the base64-encoded IV and ciphertext from SharedPreferences.
   *    Returns null if either is missing.
   * 2. Retrieves the SecretKey from AndroidKeyStore using the stored alias.
   *    If the key is unavailable (e.g., Auto Backup restored prefs on a new install),
   *    decryption fails and null is returned.
   * 3. Initializes an AES/GCM cipher in decrypt mode with the stored IV.
   * 4. Decrypts the ciphertext and returns the device ID string.
   *
   * Returns null if:
   * - No encrypted device ID is stored.
   * - The AndroidKeyStore key is unavailable (e.g., new device after Auto Backup).
   * - Decryption fails due to authentication failure or other errors.
   *
   * @return The decrypted device ID string, or null if not found or decryption fails.
   */
  fun getDeviceId(): String? {
    val encB64 = prefs.getString(PREFS_DEVICE_ID_ENC, null) ?: return null
    val ivB64 = prefs.getString(PREFS_DEVICE_ID_IV, null) ?: return null

    return try {
      val key = keyStore.getKey(KEY_ALIAS, null) as SecretKey
      val cipher = Cipher.getInstance("AES/GCM/NoPadding")
      val spec = GCMParameterSpec(GCM_TAG_LENGTH, Base64.getDecoder().decode(ivB64))
      cipher.init(Cipher.DECRYPT_MODE, key, spec)

      val encData = Base64.getDecoder().decode(encB64)
      String(cipher.doFinal(encData))
    } catch (e: Exception) {
      null
    }
  }

  /**
   * Adds a topic to the set of subscribed topics.
   *
   * Called after a successful FCM subscription (in [LayrzPushPlugin.subscribe]).
   * The list is used to persist subscription state across process restarts and
   * as a fallback if subscription status diverges from actual FCM state.
   *
   * @param topic The FCM topic name to add (e.g., `device_{deviceId}`).
   */
  fun addSubscription(topic: String) {
    val subs = getSubscriptions().toMutableSet()
    subs.add(topic)
    prefs.edit().putStringSet(PREFS_SUBSCRIPTIONS, subs).apply()
  }

  /**
   * Removes a topic from the set of subscribed topics.
   *
   * Called after a successful FCM unsubscription (in [LayrzPushPlugin.unsubscribe]).
   *
   * @param topic The FCM topic name to remove.
   */
  fun removeSubscription(topic: String) {
    val subs = getSubscriptions().toMutableSet()
    subs.remove(topic)
    prefs.edit().putStringSet(PREFS_SUBSCRIPTIONS, subs).apply()
  }

  /**
   * Retrieves the list of currently subscribed topics.
   *
   * Returns the topics stored locally, which are updated after each successful
   * FCM subscription or unsubscription. Note: this list may diverge from actual
   * FCM state if the device is offline or if credentials change.
   *
   * @return A list of subscribed topic names, or an empty list if none are stored.
   */
  fun getSubscriptions(): List<String> {
    return prefs.getStringSet(PREFS_SUBSCRIPTIONS, emptySet())?.toList() ?: emptyList()
  }

  /**
   * Clears all subscriptions from local storage.
   *
   * Does not unsubscribe from FCM; use [LayrzPushPlugin.unsubscribe] for that.
   * This is provided for testing or emergency cleanup scenarios.
   */
  fun clearSubscriptions() {
    prefs.edit().remove(PREFS_SUBSCRIPTIONS).apply()
  }

  /**
   * Retrieves an existing AES key from AndroidKeyStore, or generates a new one if it doesn't exist.
   *
   * Key generation details:
   * - Algorithm: AES (128-bit key generated by AndroidKeyStore).
   * - Block mode: GCM (Galois/Counter Mode) for authenticated encryption.
   * - Padding: None (GCM handles padding).
   * - Purpose: Both encryption and decryption.
   * - User authentication: Not required (Android API level S+). Older versions default to false.
   *
   * The key is stored securely in AndroidKeyStore and never exported. If the Keystore
   * entry is lost (e.g., after factory reset or Auto Backup restore on a different device),
   * a new key is generated on next access.
   *
   * @return The AES SecretKey for encryption/decryption of the device ID.
   */
  private fun getOrCreateKey(): SecretKey {
    val existing = keyStore.getKey(KEY_ALIAS, null)
    if (existing is SecretKey) {
      return existing
    }

    val keyGen = KeyGenerator.getInstance(
      KeyProperties.KEY_ALGORITHM_AES,
      "AndroidKeyStore"
    )

    val spec = KeyGenParameterSpec.Builder(
      KEY_ALIAS,
      KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
    ).apply {
      setBlockModes(KeyProperties.BLOCK_MODE_GCM)
      setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        setUserAuthenticationRequired(false)
      }
    }.build()

    keyGen.init(spec)
    return keyGen.generateKey()
  }
}
