import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

/// The main Flutter plugin for managing push notifications via Firebase Cloud Messaging (FCM).
///
/// This class implements the `LayrzPushPlatformChannel` pigeon interface directly (rather than delegating to a helper object)
/// because the FlutterPluginRegistrar's `addApplicationDelegate()` method requires an object that conforms to `FlutterPlugin`.
///
/// Responsibilities:
/// - Multi-tenant Firebase configuration with runtime credential injection (no hardcoded GoogleService-Info.plist).
/// - APNs token registration for FCM integration.
/// - Push notification reception and delivery via the `onPush` callback.
/// - Topic-based subscriptions with the `device_{deviceId}` topic.
///
/// Key behaviors:
/// - Firebase can be reconfigured via `setCredentials()`, which deletes any existing `FirebaseApp` instance before creating a new one.
/// - The APNs token is set on the main thread after successful APNs registration.
/// - Foreground notifications trigger `userNotificationCenter(willPresent:)`, which suppresses the system banner
///   (the app presents the notification via the Dart `onPush` stream) and filters user info to exclude FCM-internal keys.
/// - Topic subscribe/unsubscribe operations are queued by Firebase until the APNs token is available; calling these
///   before registration completes is safe.
/// - Cold-start re-initialization is handled by `ensureFirebase()`, which re-configures Firebase from persisted credentials
///   when the app process restarts without a fresh `setCredentials` call.
public class LayrzPushPlugin: NSObject, FlutterPlugin, LayrzPushPlatformChannel, UNUserNotificationCenterDelegate {
  /// The callback channel used to deliver push notifications to the Dart layer via the `onPush` stream.
  private var callbackChannel: LayrzPushCallbackChannel?

  /// Registers the plugin with the Flutter runtime.
  ///
  /// Sets up the pigeon channel, assigns this instance as the application delegate
  /// (so it receives APNs registration callbacks), and registers as the user notification center delegate
  /// (so it handles foreground notification presentation).
  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let instance = LayrzPushPlugin()
    instance.callbackChannel = LayrzPushCallbackChannel(binaryMessenger: messenger)
    LayrzPushPlatformChannelSetup.setUp(binaryMessenger: messenger, api: instance)
    registrar.addApplicationDelegate(instance)
    UNUserNotificationCenter.current().delegate = instance
  }

  // MARK: - LayrzPushPlatformChannel

  /// Configures Firebase with the provided iOS credentials and initiates APNs registration.
  ///
  /// This method implements multi-tenant credential injection: Firebase is configured at runtime from credentials
  /// passed by the Dart layer, enabling hot-swapping of Firebase projects without rebuilding the app.
  ///
  /// Process:
  /// 1. Extracts iOS-specific credentials from the cross-platform `PushCredentials` object.
  /// 2. Persists credentials to UserDefaults (for cold-start re-initialization via `ensureFirebase()`).
  /// 3. If a FirebaseApp instance already exists, deletes it first (the completion block from `delete` is not
  ///    guaranteed to run on the main thread, so the next step is wrapped in `DispatchQueue.main.async`).
  /// 4. Configures a new FirebaseApp with the credentials and requests APNs registration.
  ///
  /// Note: FirebaseApp.configure must run on the main thread.
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

  /// Stores the device identifier in the Keychain.
  ///
  /// The device ID is persisted in the Keychain (rather than UserDefaults) because it should survive
  /// app uninstall and reinstall. This is used to derive the FCM topic `device_{deviceId}` for topic-based
  /// push delivery.
  func setDeviceId(deviceId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    let success = PushStorage.saveDeviceId(deviceId)
    completion(.success(success))
  }

  /// Subscribes the device to its FCM topic for receiving push notifications.
  ///
  /// The topic is derived as `device_{deviceId}`, which is device-specific and used by the backend
  /// to send notifications to individual devices.
  ///
  /// Behavior:
  /// - If the device ID or Firebase credentials are missing, returns false without attempting subscription.
  /// - Calls `ensureFirebase()` to re-configure Firebase if the app process restarted without a fresh `setCredentials` call.
  /// - Firebase queues topic operations until the APNs token is available; calling this before APNs registration
  ///   is safe.
  /// - On success, stores the topic in UserDefaults via `addSubscription()` for local tracking.
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

  /// Unsubscribes the device from its FCM topic.
  ///
  /// Reverses the effect of `subscribe()`: removes the device from the `device_{deviceId}` topic and
  /// clears the topic from local storage.
  ///
  /// Behavior mirrors `subscribe()`:
  /// - Returns false if the device ID or Firebase credentials are missing.
  /// - Calls `ensureFirebase()` to re-configure Firebase if needed.
  /// - On success, removes the topic from UserDefaults via `removeSubscription()`.
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

  /// Retrieves the list of FCM topics the device is currently subscribed to.
  ///
  /// Returns the topics stored locally in UserDefaults; this reflects subscriptions initiated
  /// by this app instance, not subscriptions that may have been registered via other means.
  func getSubscriptions(completion: @escaping (Result<[String], Error>) -> Void) {
    completion(.success(PushStorage.getSubscriptions()))
  }

  // MARK: - APNs

  /// Handles successful APNs device token registration.
  ///
  /// Called by the OS when the app successfully registers for remote notifications.
  /// Assigns the APNs token to the Firebase Messaging instance so that FCM can
  /// route notifications through Apple's push service.
  ///
  /// This callback must run on the main thread (which is guaranteed by the OS).
  public func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    guard FirebaseApp.app() != nil else { return }
    Messaging.messaging().apnsToken = deviceToken
  }

  /// Handles APNs device token registration failure.
  ///
  /// Called by the OS when remote notification registration fails (e.g., due to network issues
  /// or invalid entitlements). Logs the error but does not stop the app.
  public func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    log("Failed to register for remote notifications: \(error.localizedDescription)")
  }

  // MARK: - UNUserNotificationCenterDelegate

  /// Handles incoming push notifications when the app is in the foreground.
  ///
  /// This method is called by the OS when a notification arrives and the app is actively in use.
  /// Unlike background delivery, the system does not automatically display a banner or play a sound.
  ///
  /// Behavior:
  /// - Suppresses the system banner by passing an empty options set to `completionHandler`.
  ///   The app itself presents the notification via the Dart layer's `onPush` stream, ensuring
  ///   a consistent presentation experience across platforms.
  /// - Extracts the title, body, and user-info data from the notification payload.
  /// - Filters the user-info dictionary to include only string values and to exclude FCM-internal keys:
  ///   - The "aps" key (Apple-specific payload metadata).
  ///   - Keys starting with "gcm." or "google." (FCM-specific internal routing data).
  ///   This filtering ensures clean, user-relevant data is passed to the Dart layer.
  /// - Sends the `PushNotification` object to the Dart layer via the callback channel on the main thread.
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

  /// Re-configures Firebase from persisted credentials if the app process restarted without a fresh `setCredentials` call.
  ///
  /// This is a cold-start guard that ensures Firebase remains available even if the app was terminated
  /// by the OS and relaunched in response to a push notification (or for other reasons), without
  /// the Dart layer having called `setCredentials` again.
  ///
  /// Process:
  /// 1. Returns `true` if a `FirebaseApp` instance is already configured.
  /// 2. Attempts to load credentials from UserDefaults.
  /// 3. If credentials exist, reconfigures Firebase with them and requests APNs registration.
  /// 4. Returns `false` if no credentials are persisted (the Dart layer must call `setCredentials` first).
  ///
  /// Called by `subscribe()` and `unsubscribe()` before attempting FCM operations.
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

  /// Creates and configures a FirebaseApp instance with the provided credentials.
  ///
  /// This static helper encapsulates the Firebase configuration logic, allowing it to be called
  /// from both `setCredentials()` and `ensureFirebase()`. It constructs a `FirebaseOptions` object
  /// from the iOS-specific credentials and passes it to Firebase's configuration method.
  ///
  /// Must be called on the main thread (caller is responsible for ensuring this).
  private static func configureFirebase(with credentials: IosPushCredentials) {
    let options = FirebaseOptions(googleAppID: credentials.appId, gcmSenderID: credentials.messagingSenderId)
    options.apiKey = credentials.apiKey
    options.projectID = credentials.projectId
    if let bucket = credentials.storageBucket {
      options.storageBucket = bucket
    }

    FirebaseApp.configure(options: options)
  }

  /// Logs a message with a plugin identifier prefix.
  ///
  /// Used for debugging and troubleshooting Firebase and FCM operations.
  private func log(_ message: String) {
    NSLog("LayrzPushPlugin: \(message)")
  }
}
