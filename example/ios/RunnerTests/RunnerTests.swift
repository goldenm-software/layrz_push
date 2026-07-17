import Foundation
import Flutter
import UIKit
import XCTest

// If your plugin has been explicitly set to "type: .dynamic" in the Package.swift,
// you will need to add your plugin as a dependency of RunnerTests within Xcode.

@testable import layrz_push

// This demonstrates a simple unit test of the Swift portion of this plugin's implementation.
//
// See https://developer.apple.com/documentation/xctest for more information about using XCTest.

class RunnerTests: XCTestCase {

  override func setUp() {
    super.setUp()
    // Clear UserDefaults
    UserDefaults.standard.removeObject(forKey: "push_credentials")
    UserDefaults.standard.removeObject(forKey: "push_subscriptions")

    // Clear Keychain entry for device_id
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.layrz.layrz_push",
      kSecAttrAccount as String: "device_id"
    ]
    SecItemDelete(query as CFDictionary)
  }

  override func tearDown() {
    super.tearDown()
    // Clear UserDefaults
    UserDefaults.standard.removeObject(forKey: "push_credentials")
    UserDefaults.standard.removeObject(forKey: "push_subscriptions")

    // Clear Keychain entry for device_id
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.layrz.layrz_push",
      kSecAttrAccount as String: "device_id"
    ]
    SecItemDelete(query as CFDictionary)
  }

  // MARK: - PushStorage / UserDefaults Credentials Tests

  /// Test saving credentials with all fields and verifying roundtrip equality.
  func testSaveAndGetCredentials_roundtrip() {
    let credentials = IosPushCredentials(
      apiKey: "test_api_key",
      appId: "test_app_id",
      projectId: "test_project_id",
      messagingSenderId: "test_messaging_sender_id",
      storageBucket: "test_storage_bucket"
    )

    PushStorage.saveCredentials(credentials)
    let retrieved = PushStorage.getCredentials()

    XCTAssertNotNil(retrieved)
    XCTAssertEqual(retrieved?.apiKey, credentials.apiKey)
    XCTAssertEqual(retrieved?.appId, credentials.appId)
    XCTAssertEqual(retrieved?.projectId, credentials.projectId)
    XCTAssertEqual(retrieved?.messagingSenderId, credentials.messagingSenderId)
    XCTAssertEqual(retrieved?.storageBucket, credentials.storageBucket)
  }

  /// Test saving credentials with nil storageBucket field.
  func testSaveAndGetCredentials_nilStorageBucket() {
    let credentials = IosPushCredentials(
      apiKey: "test_api_key",
      appId: "test_app_id",
      projectId: "test_project_id",
      messagingSenderId: "test_messaging_sender_id",
      storageBucket: nil
    )

    PushStorage.saveCredentials(credentials)
    let retrieved = PushStorage.getCredentials()

    XCTAssertNotNil(retrieved)
    XCTAssertNil(retrieved?.storageBucket)
    XCTAssertEqual(retrieved?.apiKey, credentials.apiKey)
  }

  /// Test saving credentials with non-nil storageBucket and verifying it is preserved.
  func testSaveCredentials_withStorageBucket() {
    let credentials = IosPushCredentials(
      apiKey: "key1",
      appId: "app1",
      projectId: "proj1",
      messagingSenderId: "sender1",
      storageBucket: "bucket.appspot.com"
    )

    PushStorage.saveCredentials(credentials)
    let retrieved = PushStorage.getCredentials()

    XCTAssertEqual(retrieved?.storageBucket, "bucket.appspot.com")
  }

  /// Test that credentials are nil after deletion.
  func testGetCredentials_afterDelete() {
    let credentials = IosPushCredentials(
      apiKey: "key1",
      appId: "app1",
      projectId: "proj1",
      messagingSenderId: "sender1",
      storageBucket: "bucket"
    )

    PushStorage.saveCredentials(credentials)
    PushStorage.deleteCredentials()
    let retrieved = PushStorage.getCredentials()

    XCTAssertNil(retrieved)
  }

  /// Test that getCredentials returns nil when credentials were never saved.
  func testGetCredentials_whenNeverSaved() {
    let retrieved = PushStorage.getCredentials()
    XCTAssertNil(retrieved)
  }

  // MARK: - PushStorage / Keychain Device ID Tests

  /// Test saving device ID and verifying roundtrip equality.
  func testSaveAndGetDeviceId_roundtrip() {
    let deviceId = "test-device-id-12345"

    let saveSuccess = PushStorage.saveDeviceId(deviceId)
    XCTAssertTrue(saveSuccess)

    let retrieved = PushStorage.getDeviceId()
    XCTAssertEqual(retrieved, deviceId)
  }

  /// Test that the second save overwrites the first value.
  func testSaveDeviceId_overwrite() {
    let firstId = "first-device-id"
    let secondId = "second-device-id"

    PushStorage.saveDeviceId(firstId)
    let firstRetrieve = PushStorage.getDeviceId()
    XCTAssertEqual(firstRetrieve, firstId)

    PushStorage.saveDeviceId(secondId)
    let secondRetrieve = PushStorage.getDeviceId()
    XCTAssertEqual(secondRetrieve, secondId)
  }

  /// Test that device ID is nil after deletion.
  func testGetDeviceId_afterDelete() {
    let deviceId = "device-to-delete"

    PushStorage.saveDeviceId(deviceId)
    PushStorage.deleteDeviceId()

    let retrieved = PushStorage.getDeviceId()
    XCTAssertNil(retrieved)
  }

  /// Test that getDeviceId returns nil when device ID was never saved.
  func testGetDeviceId_whenNeverSaved() {
    let retrieved = PushStorage.getDeviceId()
    XCTAssertNil(retrieved)
  }

  /// Test that saveDeviceId returns true on success.
  func testSaveDeviceId_success() {
    let result = PushStorage.saveDeviceId("test-id")
    XCTAssertTrue(result)
  }

  // MARK: - PushStorage / Subscriptions Tests

  /// Test adding and retrieving multiple subscriptions.
  func testAddAndGetSubscriptions_roundtrip() {
    let topic1 = "device_id_topic_1"
    let topic2 = "device_id_topic_2"

    PushStorage.addSubscription(topic1)
    PushStorage.addSubscription(topic2)

    let subscriptions = PushStorage.getSubscriptions()
    XCTAssertEqual(subscriptions.count, 2)
    XCTAssertTrue(subscriptions.contains(topic1))
    XCTAssertTrue(subscriptions.contains(topic2))
  }

  /// Test that adding the same topic twice only stores it once.
  func testAddSubscription_deduplicates() {
    let topic = "device_id_duplicate_topic"

    PushStorage.addSubscription(topic)
    PushStorage.addSubscription(topic)

    let subscriptions = PushStorage.getSubscriptions()
    let occurrences = subscriptions.filter { $0 == topic }.count
    XCTAssertEqual(occurrences, 1)
  }

  /// Test removing a subscription.
  func testRemoveSubscription() {
    let topic1 = "keep_this_topic"
    let topic2 = "remove_this_topic"

    PushStorage.addSubscription(topic1)
    PushStorage.addSubscription(topic2)
    PushStorage.removeSubscription(topic2)

    let subscriptions = PushStorage.getSubscriptions()
    XCTAssertTrue(subscriptions.contains(topic1))
    XCTAssertFalse(subscriptions.contains(topic2))
  }

  /// Test that getSubscriptions returns empty array when none were added.
  func testGetSubscriptions_empty() {
    let subscriptions = PushStorage.getSubscriptions()
    XCTAssertEqual(subscriptions.count, 0)
  }

  /// Test directly calling saveSubscriptions with an array.
  func testSaveAndGetSubscriptions_directRoundtrip() {
    let topics = ["topic_1", "topic_2", "topic_3"]

    PushStorage.saveSubscriptions(topics)
    let retrieved = PushStorage.getSubscriptions()

    XCTAssertEqual(retrieved.count, topics.count)
    for topic in topics {
      XCTAssertTrue(retrieved.contains(topic))
    }
  }

  // MARK: - Codable Conformance Tests

  /// Test encoding and decoding IosPushCredentials with all fields populated.
  func testIosPushCredentials_encodeDecode_allFields() {
    let original = IosPushCredentials(
      apiKey: "key",
      appId: "app",
      projectId: "proj",
      messagingSenderId: "sender",
      storageBucket: "bucket"
    )

    let encoder = JSONEncoder()
    let encoded = try! encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try! decoder.decode(IosPushCredentials.self, from: encoded)

    XCTAssertEqual(decoded, original)
  }

  /// Test encoding and decoding IosPushCredentials with nil storageBucket.
  func testIosPushCredentials_encodeDecode_nilStorageBucket() {
    let original = IosPushCredentials(
      apiKey: "key",
      appId: "app",
      projectId: "proj",
      messagingSenderId: "sender",
      storageBucket: nil
    )

    let encoder = JSONEncoder()
    let encoded = try! encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try! decoder.decode(IosPushCredentials.self, from: encoded)

    XCTAssertNil(decoded.storageBucket)
    XCTAssertEqual(decoded.apiKey, original.apiKey)
  }

  /// Test decoding JSON that omits storageBucket key results in nil field.
  func testIosPushCredentials_encodeDecode_preservesNil() {
    let json = """
    {
      "apiKey": "key",
      "appId": "app",
      "projectId": "proj",
      "messagingSenderId": "sender"
    }
    """

    let decoder = JSONDecoder()
    let decoded = try! decoder.decode(IosPushCredentials.self, from: json.data(using: .utf8)!)

    XCTAssertNil(decoded.storageBucket)
  }

  // MARK: - Generated Struct Equality/Hashability Tests

  /// Test that two PushNotification instances with identical values are equal.
  func testPushNotification_equality() {
    let notification1 = PushNotification(
      title: "Test Title",
      body: "Test Body",
      data: ["key": "value"]
    )
    let notification2 = PushNotification(
      title: "Test Title",
      body: "Test Body",
      data: ["key": "value"]
    )

    XCTAssertEqual(notification1, notification2)
  }

  /// Test that two PushNotification instances with different values are not equal.
  func testPushNotification_inequality() {
    let notification1 = PushNotification(
      title: "Title 1",
      body: "Body 1",
      data: ["key": "value1"]
    )
    let notification2 = PushNotification(
      title: "Title 2",
      body: "Body 2",
      data: ["key": "value2"]
    )

    XCTAssertNotEqual(notification1, notification2)
  }

  /// Test that two equal PushNotification instances have the same hash value.
  func testPushNotification_hashable() {
    let notification1 = PushNotification(
      title: "Title",
      body: "Body",
      data: ["key": "value"]
    )
    let notification2 = PushNotification(
      title: "Title",
      body: "Body",
      data: ["key": "value"]
    )

    XCTAssertEqual(notification1.hashValue, notification2.hashValue)
  }

  /// Test that two IosPushCredentials instances with identical values are equal.
  func testIosPushCredentials_equality() {
    let creds1 = IosPushCredentials(
      apiKey: "key",
      appId: "app",
      projectId: "proj",
      messagingSenderId: "sender",
      storageBucket: "bucket"
    )
    let creds2 = IosPushCredentials(
      apiKey: "key",
      appId: "app",
      projectId: "proj",
      messagingSenderId: "sender",
      storageBucket: "bucket"
    )

    XCTAssertEqual(creds1, creds2)
  }

  /// Test that two equal IosPushCredentials instances have the same hash value.
  func testIosPushCredentials_hashable() {
    let creds1 = IosPushCredentials(
      apiKey: "key",
      appId: "app",
      projectId: "proj",
      messagingSenderId: "sender",
      storageBucket: "bucket"
    )
    let creds2 = IosPushCredentials(
      apiKey: "key",
      appId: "app",
      projectId: "proj",
      messagingSenderId: "sender",
      storageBucket: "bucket"
    )

    XCTAssertEqual(creds1.hashValue, creds2.hashValue)
  }

  // MARK: - Future Work (Deferred Tests)
  // The following test areas require runtime environment and are deferred:
  // - awaitApnsToken: Requires real APNs token delivery from iOS
  // - APNs delegate methods (didFinishLaunchingWithOptions, etc.): Require AppDelegate integration
  // - Firebase integration (ensureFirebase, setCredentials, subscribe, unsubscribe):
  //   Requires initialized FirebaseApp and real FCM registration tokens
  // - onPush broadcast: Requires StreamController wiring and method channel dispatch

}
