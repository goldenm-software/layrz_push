import Foundation

/// Manages persistent storage of push notification configuration and state.
///
/// This class handles two distinct storage backends:
/// - **Keychain** (kSecClassGenericPassword): Device ID, which must survive app uninstall and reinstall
///   with the default accessibility class kSecAttrAccessibleWhenUnlocked. Keychain items survive app uninstall
///   and can be restored on the same device via encrypted backups, and can migrate to a new device via
///   encrypted iCloud backups (if the app uses iCloud Keychain sync).
/// - **UserDefaults**: Firebase credentials and topic subscriptions. These are not encrypted at rest and
///   are designed to be readable for cold-start re-initialization. They do NOT survive app uninstall.
///   Credentials are stored as JSON-encoded data; subscriptions are stored as a string array.
///
/// All methods are static, making this a utility class with no instance state.
class PushStorage {
  private static let keychainService = "com.layrz.layrz_push"
  private static let deviceIdAccount = "device_id"
  private static let credentialsKey = "push_credentials"
  private static let subscriptionsKey = "push_subscriptions"

  /// Persists the device ID to the Keychain.
  ///
  /// The Keychain uses a delete-then-add pattern to ensure a fresh item with the current timestamp
  /// and default accessibility attributes. The device ID is stored as a UTF-8-encoded data blob
  /// in a generic password item under the service `com.layrz.layrz_push` and account `device_id`.
  ///
  /// Important behavior:
  /// - The item is stored with the default accessibility class `kSecAttrAccessibleWhenUnlocked`,
  ///   meaning it is accessible only when the device is unlocked.
  /// - Keychain items survive app uninstall and reinstall on the same device.
  /// - With the default accessibility, Keychain items can migrate to a new device via encrypted iCloud backups
  ///   if the app uses iCloud Keychain sync, or they persist locally if not using iCloud Keychain.
  /// - This behavior is by design: the device ID should remain constant across app reinstalls.
  ///
  /// Returns `true` if the save succeeded, `false` otherwise.
  static func saveDeviceId(_ deviceId: String) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: deviceIdAccount,
      kSecValueData as String: deviceId.data(using: .utf8) ?? Data(),
    ]

    let searchQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: deviceIdAccount,
    ]

    SecItemDelete(searchQuery as CFDictionary)

    let status = SecItemAdd(query as CFDictionary, nil)
    return status == errSecSuccess
  }

  /// Retrieves the device ID from the Keychain.
  ///
  /// Queries the Keychain for the generic password item stored by `saveDeviceId()` and decodes it
  /// from UTF-8 data. Returns `nil` if no device ID has been stored or if decoding fails.
  ///
  /// This is used by the plugin during app startup and whenever the device ID is needed (e.g., to
  /// derive the FCM topic for subscription operations).
  static func getDeviceId() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: deviceIdAccount,
      kSecReturnData as String: true,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess else {
      return nil
    }

    if let data = result as? Data, let deviceId = String(data: data, encoding: .utf8) {
      return deviceId
    }

    return nil
  }

  /// Deletes the device ID from the Keychain.
  ///
  /// Removes the Keychain item. Returns `true` if the deletion succeeded or the item was not found
  /// (treating "not found" as success, since the end state is the same).
  ///
  /// This method is provided for completeness but is not currently called by the plugin.
  static func deleteDeviceId() -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: deviceIdAccount,
    ]

    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  /// Persists Firebase credentials to UserDefaults as JSON-encoded data.
  ///
  /// The credentials are stored under the key `push_credentials` in the standard UserDefaults store.
  /// They are encoded using `JSONEncoder` and the custom `Codable` conformance defined in the
  /// `IosPushCredentials` extension at the end of this file.
  ///
  /// This storage method is by design (not secret-grade) because credentials need to be readable
  /// for cold-start re-initialization when the app process restarts. UserDefaults is sufficient
  /// for this use case.
  ///
  /// Important behavior:
  /// - UserDefaults are NOT encrypted at rest.
  /// - UserDefaults DO NOT survive app uninstall (unlike Keychain).
  /// - Encoding failures are silently ignored (no data is stored).
  static func saveCredentials(_ credentials: IosPushCredentials) {
    let defaults = UserDefaults.standard
    let encoder = JSONEncoder()

    if let data = try? encoder.encode(credentials) {
      defaults.set(data, forKey: credentialsKey)
    }
  }

  /// Retrieves Firebase credentials from UserDefaults.
  ///
  /// Decodes the JSON-encoded credentials stored by `saveCredentials()`. Returns `nil` if no
  /// credentials have been stored or if decoding fails.
  ///
  /// Used by `ensureFirebase()` to re-configure Firebase when the app process restarts without
  /// a fresh `setCredentials` call from the Dart layer.
  static func getCredentials() -> IosPushCredentials? {
    let defaults = UserDefaults.standard

    guard let data = defaults.data(forKey: credentialsKey) else {
      return nil
    }

    let decoder = JSONDecoder()
    return try? decoder.decode(IosPushCredentials.self, from: data)
  }

  /// Deletes the stored Firebase credentials from UserDefaults.
  ///
  /// Removes the credentials entry, effectively signing out or resetting the Firebase configuration.
  /// This method is provided for completeness but is not currently called by the plugin.
  static func deleteCredentials() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: credentialsKey)
  }

  /// Persists the list of FCM topics to UserDefaults.
  ///
  /// Replaces the entire subscriptions list with the provided array. The array is stored as
  /// a property list (serialized directly by UserDefaults) under the key `push_subscriptions`.
  ///
  /// Used by `addSubscription()` and `removeSubscription()` to maintain a record of subscribed topics.
  static func saveSubscriptions(_ topics: [String]) {
    let defaults = UserDefaults.standard
    defaults.set(topics, forKey: subscriptionsKey)
  }

  /// Retrieves the list of FCM topics from UserDefaults.
  ///
  /// Returns an empty array if no subscriptions have been stored.
  ///
  /// Used by the plugin's `getSubscriptions()` method to return the list of subscribed topics
  /// to the Dart layer.
  static func getSubscriptions() -> [String] {
    let defaults = UserDefaults.standard
    return defaults.array(forKey: subscriptionsKey) as? [String] ?? []
  }

  /// Adds a topic to the subscriptions list if it is not already present.
  ///
  /// Fetches the current list, checks for duplicates, appends the new topic if needed, and
  /// persists the updated list back to UserDefaults.
  ///
  /// Called by the plugin's `subscribe()` method after a successful FCM subscription.
  static func addSubscription(_ topic: String) {
    var topics = getSubscriptions()
    if !topics.contains(topic) {
      topics.append(topic)
      saveSubscriptions(topics)
    }
  }

  /// Removes a topic from the subscriptions list.
  ///
  /// Fetches the current list, removes all occurrences of the topic (in case of duplicates),
  /// and persists the updated list back to UserDefaults.
  ///
  /// Called by the plugin's `unsubscribe()` method after a successful FCM unsubscription.
  static func removeSubscription(_ topic: String) {
    var topics = getSubscriptions()
    topics.removeAll { $0 == topic }
    saveSubscriptions(topics)
  }
}

/// Extends the pigeon-generated `IosPushCredentials` struct to conform to `Codable`.
///
/// This extension is necessary because `IosPushCredentials` is generated by the Pigeon code-generation tool
/// and does not synthesize `Codable` conformance. This custom implementation allows the credentials to be
/// JSON-encoded and decoded for persistence in UserDefaults.
///
/// The `CodingKeys` enum defines the JSON keys used during serialization. The `encode(to:)` and
/// `init(from:)` methods provide fine-grained control over which fields are serialized: the optional
/// `storageBucket` field is encoded only if present.
extension IosPushCredentials: Codable {
  enum CodingKeys: String, CodingKey {
    case apiKey
    case appId
    case projectId
    case messagingSenderId
    case storageBucket
  }

  /// Decodes a Firebase credentials object from a JSON decoder.
  ///
  /// Decodes the mandatory fields (apiKey, appId, projectId, messagingSenderId) and the optional
  /// storageBucket field. Used by `PushStorage.getCredentials()` to restore credentials from
  /// UserDefaults when the app starts.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.apiKey = try container.decode(String.self, forKey: .apiKey)
    self.appId = try container.decode(String.self, forKey: .appId)
    self.projectId = try container.decode(String.self, forKey: .projectId)
    self.messagingSenderId = try container.decode(String.self, forKey: .messagingSenderId)
    self.storageBucket = try container.decodeIfPresent(String.self, forKey: .storageBucket)
  }

  /// Encodes this credentials object to a JSON encoder.
  ///
  /// Encodes all fields, omitting storageBucket if it is not set. Used by `PushStorage.saveCredentials()`
  /// to persist credentials to UserDefaults when they are provided by the Dart layer.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(self.apiKey, forKey: .apiKey)
    try container.encode(self.appId, forKey: .appId)
    try container.encode(self.projectId, forKey: .projectId)
    try container.encode(self.messagingSenderId, forKey: .messagingSenderId)
    if let storageBucket = self.storageBucket {
      try container.encode(storageBucket, forKey: .storageBucket)
    }
  }
}
