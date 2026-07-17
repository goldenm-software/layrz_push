package com.layrz.layrz_push

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.google.firebase.FirebaseApp
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Unit tests for [FirebaseBootstrap], covering cold-start Firebase initialization
 * from persisted credentials and re-initialization guards.
 *
 * These tests use Robolectric to simulate the Android environment and verify that
 * [FirebaseBootstrap.ensureFirebase] correctly initializes Firebase when credentials
 * are available and gracefully skips initialization when they are not.
 */
@RunWith(RobolectricTestRunner::class)
class FirebaseBootstrapTest {
  private lateinit var context: Context
  private lateinit var storage: PushStorage

  @Before
  fun setUp() {
    context = ApplicationProvider.getApplicationContext()
    storage = PushStorage(context)
    // Ensure no Firebase app is initialized at the start of each test.
    deleteAllFirebaseApps()
  }

  @After
  fun tearDown() {
    // Clean up all Firebase apps after each test to prevent state leakage.
    deleteAllFirebaseApps()
  }

  /**
   * Tests that [ensureFirebase] returns false when no credentials are stored.
   *
   * Verifies the guard case: if the device has not yet received credentials
   * (e.g., cold start before the Dart layer calls [setCredentials]), or if
   * credentials have been cleared, [FirebaseBootstrap.ensureFirebase] returns
   * false, allowing the caller to skip Firebase-dependent operations.
   */
  @Test
  fun ensureFirebaseReturnsFalseWithNoCredentials() {
    val result = FirebaseBootstrap.ensureFirebase(context)
    assertFalse(result, "ensureFirebase should return false when no credentials are stored")
  }

  /**
   * Tests that [ensureFirebase] initializes Firebase when credentials are stored.
   *
   * Verifies the happy path: after [PushStorage.saveCredentials] persists a complete
   * set of Firebase configuration (apiKey, appId, projectId, messagingSenderId, and
   * optional storageBucket), [FirebaseBootstrap.ensureFirebase] re-initializes Firebase
   * and returns true. The Firebase default app is then available for use.
   */
  @Test
  fun ensureFirebaseInitializeWhenCredentialsExist() {
    // Arrange: Save valid credentials to storage.
    val credentials = AndroidPushCredentials(
      apiKey = "test-api-key-789",
      appId = "com.test.app:android:init-test-001",
      projectId = "test-project-bootstrap",
      messagingSenderId = "111222333444",
      storageBucket = "test-project-bootstrap.appspot.com"
    )
    storage.saveCredentials(credentials)

    // Act: Call ensureFirebase to re-initialize Firebase from stored credentials.
    val result = FirebaseBootstrap.ensureFirebase(context)

    // Assert: Firebase is initialized and accessible.
    assertTrue(result, "ensureFirebase should return true when credentials are available")
    val app = FirebaseApp.getInstance()
    assertTrue(app != null, "Firebase default app should be initialized")
  }

  /**
   * Tests that [ensureFirebase] returns true when Firebase is already initialized.
   *
   * Verifies the idempotency contract: calling [ensureFirebase] twice in succession
   * should not attempt to re-initialize Firebase. The second call should return true
   * immediately, without creating a second default app.
   */
  @Test
  fun ensureFirebaseReturnsTrueWhenAlreadyInitialized() {
    // Arrange: Save credentials and initialize Firebase once.
    val credentials = AndroidPushCredentials(
      apiKey = "test-api-key-idempotent",
      appId = "com.test.app:android:idempotent-001",
      projectId = "test-project-idempotent",
      messagingSenderId = "555666777888",
      storageBucket = null
    )
    storage.saveCredentials(credentials)

    // Act: First call to ensureFirebase.
    val firstResult = FirebaseBootstrap.ensureFirebase(context)
    assertTrue(firstResult, "First ensureFirebase call should return true")

    // Act: Second call to ensureFirebase (app already initialized).
    val secondResult = FirebaseBootstrap.ensureFirebase(context)
    assertTrue(secondResult, "Second ensureFirebase call should return true")

    // Assert: Only one Firebase app exists (no re-initialization).
    val apps = FirebaseApp.getApps(context)
    assertEquals(1, apps.size, "Should have exactly one Firebase app after two ensureFirebase calls")
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
