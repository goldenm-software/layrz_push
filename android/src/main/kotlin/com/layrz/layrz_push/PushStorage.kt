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

  fun addSubscription(topic: String) {
    val subs = getSubscriptions().toMutableSet()
    subs.add(topic)
    prefs.edit().putStringSet(PREFS_SUBSCRIPTIONS, subs).apply()
  }

  fun removeSubscription(topic: String) {
    val subs = getSubscriptions().toMutableSet()
    subs.remove(topic)
    prefs.edit().putStringSet(PREFS_SUBSCRIPTIONS, subs).apply()
  }

  fun getSubscriptions(): List<String> {
    return prefs.getStringSet(PREFS_SUBSCRIPTIONS, emptySet())?.toList() ?: emptyList()
  }

  fun clearSubscriptions() {
    prefs.edit().remove(PREFS_SUBSCRIPTIONS).apply()
  }

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
