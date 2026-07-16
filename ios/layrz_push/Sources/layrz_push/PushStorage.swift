import Foundation

class PushStorage {
  private static let keychainService = "com.layrz.layrz_push"
  private static let deviceIdAccount = "device_id"
  private static let credentialsKey = "push_credentials"
  private static let subscriptionsKey = "push_subscriptions"

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

  static func deleteDeviceId() -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: deviceIdAccount,
    ]

    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  static func saveCredentials(_ credentials: IosPushCredentials) {
    let defaults = UserDefaults.standard
    let encoder = JSONEncoder()

    if let data = try? encoder.encode(credentials) {
      defaults.set(data, forKey: credentialsKey)
    }
  }

  static func getCredentials() -> IosPushCredentials? {
    let defaults = UserDefaults.standard

    guard let data = defaults.data(forKey: credentialsKey) else {
      return nil
    }

    let decoder = JSONDecoder()
    return try? decoder.decode(IosPushCredentials.self, from: data)
  }

  static func deleteCredentials() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: credentialsKey)
  }

  static func saveSubscriptions(_ topics: [String]) {
    let defaults = UserDefaults.standard
    defaults.set(topics, forKey: subscriptionsKey)
  }

  static func getSubscriptions() -> [String] {
    let defaults = UserDefaults.standard
    return defaults.array(forKey: subscriptionsKey) as? [String] ?? []
  }

  static func addSubscription(_ topic: String) {
    var topics = getSubscriptions()
    if !topics.contains(topic) {
      topics.append(topic)
      saveSubscriptions(topics)
    }
  }

  static func removeSubscription(_ topic: String) {
    var topics = getSubscriptions()
    topics.removeAll { $0 == topic }
    saveSubscriptions(topics)
  }
}

extension IosPushCredentials: Codable {
  enum CodingKeys: String, CodingKey {
    case apiKey
    case appId
    case projectId
    case messagingSenderId
    case storageBucket
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.apiKey = try container.decode(String.self, forKey: .apiKey)
    self.appId = try container.decode(String.self, forKey: .appId)
    self.projectId = try container.decode(String.self, forKey: .projectId)
    self.messagingSenderId = try container.decode(String.self, forKey: .messagingSenderId)
    self.storageBucket = try container.decodeIfPresent(String.self, forKey: .storageBucket)
  }

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
