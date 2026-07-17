package com.layrz.layrz_push

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.Before
import org.junit.Ignore
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Unit tests for [PushStorage], covering credentials persistence, subscriptions,
 * and graceful error handling.
 *
 * These tests use Robolectric to simulate the Android environment without
 * requiring a real device or emulator. AndroidKeyStore operations that require
 * actual Android hardware are marked @Ignore and tested via field testing.
 */
@RunWith(RobolectricTestRunner::class)
class PushStorageTest {
  private lateinit var context: Context
  private lateinit var storage: PushStorage

  @Before
  fun setUp() {
    context = ApplicationProvider.getApplicationContext()
    storage = PushStorage(context)
  }

  /**
   * Tests credentials roundtrip with all fields including storageBucket.
   *
   * Verifies that [PushStorage.saveCredentials] persists Firebase configuration
   * (apiKey, appId, projectId, messagingSenderId, storageBucket) to SharedPreferences,
   * and [PushStorage.getCredentials] reconstructs the object correctly.
   */
  @Test
  fun credentialsRoundtripWithStorageBucket() {
    val credentials = AndroidPushCredentials(
      apiKey = "test-api-key-123",
      appId = "com.test.app:android:abc123def456",
      projectId = "test-project-id",
      messagingSenderId = "123456789012",
      storageBucket = "test-project-id.appspot.com"
    )

    storage.saveCredentials(credentials)
    val retrieved = storage.getCredentials()

    assertEquals(credentials.apiKey, retrieved?.apiKey)
    assertEquals(credentials.appId, retrieved?.appId)
    assertEquals(credentials.projectId, retrieved?.projectId)
    assertEquals(credentials.messagingSenderId, retrieved?.messagingSenderId)
    assertEquals(credentials.storageBucket, retrieved?.storageBucket)
  }

  /**
   * Tests credentials roundtrip without storageBucket field.
   *
   * Verifies that [PushStorage.saveCredentials] handles null storageBucket correctly
   * (omitting it from the JSON), and [PushStorage.getCredentials] reconstructs the
   * object with storageBucket = null.
   */
  @Test
  fun credentialsRoundtripWithoutStorageBucket() {
    val credentials = AndroidPushCredentials(
      apiKey = "test-api-key-456",
      appId = "com.test.app:android:xyz789uvw012",
      projectId = "test-project-2",
      messagingSenderId = "987654321098",
      storageBucket = null
    )

    storage.saveCredentials(credentials)
    val retrieved = storage.getCredentials()

    assertEquals(credentials.apiKey, retrieved?.apiKey)
    assertEquals(credentials.appId, retrieved?.appId)
    assertEquals(credentials.projectId, retrieved?.projectId)
    assertEquals(credentials.messagingSenderId, retrieved?.messagingSenderId)
    assertNull(retrieved?.storageBucket)
  }

  /**
   * Tests that [getCredentials] returns null when storage is empty.
   *
   * Verifies the guard case: if no credentials have been saved (e.g., cold start
   * before the Dart layer calls [setCredentials]), [PushStorage.getCredentials]
   * returns null, allowing [FirebaseBootstrap.ensureFirebase] to skip initialization.
   */
  @Test
  fun nullCredentialsOnEmptyStorage() {
    val retrieved = storage.getCredentials()
    assertNull(retrieved)
  }

  /**
   * Tests that corrupted JSON in SharedPreferences is handled gracefully.
   *
   * Verifies the exception-safety contract: if corrupted or malformed JSON is
   * stored directly via SharedPreferences (e.g., by a bug or data corruption),
   * [PushStorage.getCredentials] catches the JSONException and returns null
   * instead of propagating the error. This allows the plugin to recover gracefully.
   */
  @Test
  fun corruptedJsonHandling() {
    // Write garbage JSON directly to SharedPreferences using raw preferences.
    val prefs = context.getSharedPreferences(
      "com.layrz.layrz_push.storage",
      Context.MODE_PRIVATE
    )
    prefs.edit().putString("credentials", "{invalid json garbage}").apply()

    val retrieved = storage.getCredentials()
    assertNull(retrieved)
  }

  /**
   * Tests adding and removing subscriptions from local storage.
   *
   * Verifies the subscription lifecycle:
   * 1. [addSubscription] persists a topic name to SharedPreferences.
   * 2. [getSubscriptions] returns the list of persisted topics.
   * 3. Adding the same topic twice results in only one copy (set semantics).
   * 4. [removeSubscription] removes a topic from the list.
   * 5. [getSubscriptions] returns an empty list after removal.
   */
  @Test
  fun subscriptionsAddRemoveGet() {
    // Initially empty.
    var subs = storage.getSubscriptions()
    assertTrue(subs.isEmpty())

    // Add first subscription.
    storage.addSubscription("topic_a")
    subs = storage.getSubscriptions()
    assertEquals(1, subs.size)
    assertTrue(subs.contains("topic_a"))

    // Add the same topic again; verify no duplicate.
    storage.addSubscription("topic_a")
    subs = storage.getSubscriptions()
    assertEquals(1, subs.size)

    // Add a second subscription.
    storage.addSubscription("topic_b")
    subs = storage.getSubscriptions()
    assertEquals(2, subs.size)
    assertTrue(subs.contains("topic_a"))
    assertTrue(subs.contains("topic_b"))

    // Remove one subscription.
    storage.removeSubscription("topic_a")
    subs = storage.getSubscriptions()
    assertEquals(1, subs.size)
    assertFalse(subs.contains("topic_a"))
    assertTrue(subs.contains("topic_b"))

    // Remove the remaining subscription.
    storage.removeSubscription("topic_b")
    subs = storage.getSubscriptions()
    assertTrue(subs.isEmpty())
  }

  /**
   * Placeholder test for AndroidKeyStore device ID encryption (marked @Ignore).
   *
   * ## Why This Is Ignored
   *
   * **Issue**: [PushStorage.saveDeviceId] and [PushStorage.getDeviceId] rely on
   * [AndroidKeyStore] to encrypt the device ID using AES-256-GCM. The AndroidKeyStore
   * is a hardware-backed secure enclave on real Android devices and cannot be simulated
   * by Robolectric on the JVM.
   *
   * **Error on JVM**: Attempting to instantiate [AndroidKeyStore] in a Robolectric test
   * throws [KeyStoreException] because the native Android security framework is not
   * available in the Linux/JVM test environment.
   *
   * **Testing Strategy**: Device ID encryption is verified via:
   * 1. **Field testing** on real Android devices (manual or via Firebase Test Lab).
   * 2. **Instrumented tests** using Android emulator (`androidTest`, not `test`).
   * 3. **Integration tests** in the example app's Flutter test suite.
   *
   * The [PushStorage] class is designed to fail gracefully if decryption fails
   * (returns null), allowing the plugin to recover and request a new device ID.
   * This error recovery is covered by the integration tests.
   */
  @Ignore("AndroidKeyStore is not available on JVM; tested via field testing and instrumented tests")
  @Test
  fun deviceIdEncryptionDecryptionAndroid() {
    // This test cannot run on JVM because AndroidKeyStore requires actual Android hardware.
    // Proof:
    //   val keyStore = KeyStore.getInstance("AndroidKeyStore")
    //   keyStore.load(null)  // -> KeyStoreException on JVM
    //
    // In a real Android environment:
    //   storage.saveDeviceId("device-12345")
    //   val retrieved = storage.getDeviceId()
    //   assertEquals("device-12345", retrieved)
  }
}
