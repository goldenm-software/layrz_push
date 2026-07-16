import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

public class LayrzPushPlugin: NSObject, FlutterPlugin, LayrzPushPlatformChannel, UNUserNotificationCenterDelegate {
  private var callbackChannel: LayrzPushCallbackChannel?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let instance = LayrzPushPlugin()
    instance.callbackChannel = LayrzPushCallbackChannel(binaryMessenger: messenger)
    LayrzPushPlatformChannelSetup.setUp(binaryMessenger: messenger, api: instance)
    registrar.addApplicationDelegate(instance)
    UNUserNotificationCenter.current().delegate = instance
  }

  // MARK: - LayrzPushPlatformChannel

  func setCredentials(credentials: PushCredentials, completion: @escaping (Result<Bool, Error>) -> Void) {
    guard let iosCredentials = credentials.ios else {
      completion(.success(false))
      return
    }

    PushStorage.saveCredentials(iosCredentials)

    let configure = {
      DispatchQueue.main.async {
        Self.configureFirebase(with: iosCredentials)
        UIApplication.shared.registerForRemoteNotifications()
        completion(.success(true))
      }
    }

    if let app = FirebaseApp.app() {
      app.delete { _ in configure() }
    } else {
      configure()
    }
  }

  func setDeviceId(deviceId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    let success = PushStorage.saveDeviceId(deviceId)
    completion(.success(success))
  }

  func subscribe(completion: @escaping (Result<Bool, Error>) -> Void) {
    guard let deviceId = PushStorage.getDeviceId(), ensureFirebase() else {
      log("Cannot subscribe: missing device ID or credentials")
      completion(.success(false))
      return
    }

    let topic = "device_\(deviceId)"
    Messaging.messaging().subscribe(toTopic: topic) { [weak self] error in
      DispatchQueue.main.async {
        if let error = error {
          self?.log("Failed to subscribe to topic \(topic): \(error.localizedDescription)")
          completion(.success(false))
          return
        }

        PushStorage.addSubscription(topic)
        completion(.success(true))
      }
    }
  }

  func unsubscribe(completion: @escaping (Result<Bool, Error>) -> Void) {
    guard let deviceId = PushStorage.getDeviceId(), ensureFirebase() else {
      log("Cannot unsubscribe: missing device ID or credentials")
      completion(.success(false))
      return
    }

    let topic = "device_\(deviceId)"
    Messaging.messaging().unsubscribe(fromTopic: topic) { [weak self] error in
      DispatchQueue.main.async {
        if let error = error {
          self?.log("Failed to unsubscribe from topic \(topic): \(error.localizedDescription)")
          completion(.success(false))
          return
        }

        PushStorage.removeSubscription(topic)
        completion(.success(true))
      }
    }
  }

  func getSubscriptions(completion: @escaping (Result<[String], Error>) -> Void) {
    completion(.success(PushStorage.getSubscriptions()))
  }

  // MARK: - APNs

  public func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    guard FirebaseApp.app() != nil else { return }
    Messaging.messaging().apnsToken = deviceToken
  }

  public func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    log("Failed to register for remote notifications: \(error.localizedDescription)")
  }

  // MARK: - UNUserNotificationCenterDelegate

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // No system banner in foreground, the app presents it through the onPush stream.
    completionHandler([])

    let content = notification.request.content

    var data: [String: String] = [:]
    for (key, value) in content.userInfo {
      guard let key = key as? String, let value = value as? String else { continue }
      guard key != "aps", !key.hasPrefix("gcm."), !key.hasPrefix("google.") else { continue }
      data[key] = value
    }

    let title: String? = content.title.isEmpty ? nil : content.title
    let body: String? = content.body.isEmpty ? nil : content.body
    let push = PushNotification(title: title, body: body, data: data)

    DispatchQueue.main.async { [weak self] in
      self?.callbackChannel?.onPush(notification: push) { _ in }
    }
  }

  // MARK: - Helpers

  /// Re-configures Firebase from the persisted credentials when the app
  /// process was restarted without a new setCredentials call.
  private func ensureFirebase() -> Bool {
    if FirebaseApp.app() != nil { return true }

    guard let credentials = PushStorage.getCredentials() else {
      log("No stored credentials to re-configure Firebase")
      return false
    }

    Self.configureFirebase(with: credentials)
    UIApplication.shared.registerForRemoteNotifications()
    return true
  }

  private static func configureFirebase(with credentials: IosPushCredentials) {
    let options = FirebaseOptions(googleAppID: credentials.appId, gcmSenderID: credentials.messagingSenderId)
    options.apiKey = credentials.apiKey
    options.projectID = credentials.projectId
    if let bucket = credentials.storageBucket {
      options.storageBucket = bucket
    }

    FirebaseApp.configure(options: options)
  }

  private func log(_ message: String) {
    NSLog("LayrzPushPlugin: \(message)")
  }
}
