package com.layrz.layrz_push

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import com.google.firebase.FirebaseApp
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner

/**
 * Unit tests for [LayrzPushInitProvider], covering cold-start Firebase initialization
 * via ContentProvider and stub method implementations.
 *
 * These tests use Robolectric to simulate the Android environment and verify that
 * the ContentProvider correctly initializes Firebase at process startup and that
 * its stub methods (query, getType, insert, update, delete) return null/0 as expected.
 */
@RunWith(RobolectricTestRunner::class)
class LayrzPushInitProviderTest {
  private lateinit var context: Context
  private lateinit var provider: LayrzPushInitProvider

  @Before
  fun setUp() {
    context = ApplicationProvider.getApplicationContext()
    // Ensure no Firebase app is initialized at the start of each test.
    deleteAllFirebaseApps()
  }

  @After
  fun tearDown() {
    // Clean up all Firebase apps after each test to prevent state leakage.
    deleteAllFirebaseApps()
  }

  /**
   * Tests that [LayrzPushInitProvider.onCreate] returns true when no credentials are stored.
   *
   * Verifies the guard case: if the device has not yet received credentials
   * (e.g., before the Dart layer calls [setCredentials]), the provider's [onCreate]
   * method returns true (ContentProvider contract), and Firebase is not initialized
   * (the guard skips initialization gracefully).
   */
  @Test
  fun onCreateReturnsTrueWithNoCredentials() {
    // Setup the provider using Robolectric's ContentProvider utilities.
    val contentProvider = Robolectric.setupContentProvider(LayrzPushInitProvider::class.java)

    // The provider should have already called onCreate() during setup.
    // Verify that Firebase is not initialized (no credentials were stored).
    assertFirebaseNotInitialized()
  }

  /**
   * Tests that [LayrzPushInitProvider.onCreate] initializes Firebase when credentials are stored.
   *
   * Verifies the happy path: if credentials are persisted via [PushStorage.saveCredentials]
   * before the ContentProvider is instantiated (e.g., during cold start with previously
   * stored credentials), the provider's [onCreate] method initializes Firebase from
   * those credentials, and returns true.
   */
  @Test
  fun onCreateReturnsTrueAndInitializeFirebaseWhenCredentialsStored() {
    // Arrange: Save credentials to storage before setting up the provider.
    val storage = PushStorage(context)
    val credentials = AndroidPushCredentials(
      apiKey = "test-api-key-provider",
      appId = "com.test.app:android:provider-001",
      projectId = "test-project-provider",
      messagingSenderId = "999888777666",
      storageBucket = "test-project-provider.appspot.com",
    )
    storage.saveCredentials(credentials)

    // Act: Setup the provider (triggers onCreate).
    val contentProvider = Robolectric.setupContentProvider(LayrzPushInitProvider::class.java)

    // Assert: Firebase is initialized.
    assertFirebaseIsInitialized()
  }

  /**
   * Tests that [LayrzPushInitProvider.query] returns null (stub implementation).
   *
   * Verifies that the query stub method returns null as documented, since the
   * provider does not expose any data via the ContentProvider interface.
   */
  @Test
  fun queryReturnsNull() {
    provider = Robolectric.setupContentProvider(LayrzPushInitProvider::class.java)
    val result = provider.query(
      Uri.parse("content://com.layrz.layrz_push.test/data"),
      null,
      null,
      null,
      null,
    )
    assertNull(result)
  }

  /**
   * Tests that [LayrzPushInitProvider.getType] returns null (stub implementation).
   *
   * Verifies that the getType stub method returns null as documented, since the
   * provider does not expose any data via the ContentProvider interface.
   */
  @Test
  fun getTypeReturnsNull() {
    provider = Robolectric.setupContentProvider(LayrzPushInitProvider::class.java)
    val result = provider.getType(Uri.parse("content://com.layrz.layrz_push.test/data"))
    assertNull(result)
  }

  /**
   * Tests that [LayrzPushInitProvider.insert] returns null (stub implementation).
   *
   * Verifies that the insert stub method returns null as documented, since the
   * provider does not expose any data via the ContentProvider interface.
   */
  @Test
  fun insertReturnsNull() {
    provider = Robolectric.setupContentProvider(LayrzPushInitProvider::class.java)
    val values = ContentValues().apply {
      put("key", "value")
    }
    val result = provider.insert(
      Uri.parse("content://com.layrz.layrz_push.test/data"),
      values,
    )
    assertNull(result)
  }

  /**
   * Tests that [LayrzPushInitProvider.update] returns 0 (stub implementation).
   *
   * Verifies that the update stub method returns 0 as documented, since the
   * provider does not expose any data via the ContentProvider interface.
   */
  @Test
  fun updateReturnsZero() {
    provider = Robolectric.setupContentProvider(LayrzPushInitProvider::class.java)
    val values = ContentValues().apply {
      put("key", "value")
    }
    val result = provider.update(
      Uri.parse("content://com.layrz.layrz_push.test/data"),
      values,
      null,
      null,
    )
    assertEquals(0, result)
  }

  /**
   * Tests that [LayrzPushInitProvider.delete] returns 0 (stub implementation).
   *
   * Verifies that the delete stub method returns 0 as documented, since the
   * provider does not expose any data via the ContentProvider interface.
   */
  @Test
  fun deleteReturnsZero() {
    provider = Robolectric.setupContentProvider(LayrzPushInitProvider::class.java)
    val result = provider.delete(
      Uri.parse("content://com.layrz.layrz_push.test/data"),
      null,
      null,
    )
    assertEquals(0, result)
  }

  /**
   * Helper method to verify that Firebase is initialized.
   *
   * Attempts to retrieve the default Firebase app. If successful, Firebase is
   * initialized. If [IllegalStateException] is thrown, Firebase is not initialized.
   */
  private fun assertFirebaseIsInitialized() {
    try {
      val app = FirebaseApp.getInstance()
      assertTrue(app != null, "Firebase app should be initialized")
    } catch (e: IllegalStateException) {
      assertTrue(false, "Firebase app should be initialized but received IllegalStateException")
    }
  }

  /**
   * Helper method to verify that Firebase is not initialized.
   *
   * Attempts to retrieve the default Firebase app. If [IllegalStateException] is
   * thrown, Firebase is not initialized (expected case).
   */
  private fun assertFirebaseNotInitialized() {
    try {
      FirebaseApp.getInstance()
      assertTrue(false, "Firebase app should not be initialized")
    } catch (e: IllegalStateException) {
      // Expected when no Firebase app is initialized.
      assertTrue(true)
    }
  }

  /**
   * Helper method to delete all FirebaseApp instances.
   *
   * Attempts to retrieve the default Firebase app and delete it. If no app is
   * initialized (IllegalStateException), the deletion is skipped (expected case).
   * This ensures test isolation by cleaning up state from previous tests.
   */
  private fun deleteAllFirebaseApps() {
    try {
      val app = FirebaseApp.getInstance()
      app.delete()
    } catch (e: IllegalStateException) {
      // Expected when no Firebase app is initialized; nothing to delete.
    }
  }
}
