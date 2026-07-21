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
/// - Topic subscribe/unsubscribe operations are awaited locally via awaitApnsToken until the APNs token is available,
///   ensuring consistent behavior with a 30-second timeout.
/// - Cold-start re-initialization is handled by `ensureFirebase()`, which re-configures Firebase from persisted credentials
///   when the app process restarts without a fresh `setCredentials` call.
public class LayrzPushPlugin: NSObject, FlutterPlugin, LayrzPushPlatformChannel, UNUserNotificationCenterDelegate {
  /// The callback channel used to deliver push notifications to the Dart layer via the `onPush` stream.
  private var callbackChannel: LayrzPushCallbackChannel?

  /// Waiters for APNs token registration. Closures are invoked when the token arrives or registration fails.
  /// Access must be synchronized to the main thread.
  private var apnsWaiters: [(Bool) -> Void] = []

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

    // iOS cold-start guard: if credentials are persisted and Firebase is not yet configured,
    // silently re-initialize from persisted creds (equivalent to Android's LayrzPushInitProvider).
    // Safe no-op on fresh installs with no credentials.
    DispatchQueue.main.async {
      if let credentials = PushStorage.getCredentials(), FirebaseApp.app() == nil {
        Self.configureFirebase(with: credentials)
        UIApplication.shared.registerForRemoteNotifications()
      }
    }
  }

  // MARK: - LayrzPushPlatformChannel

  /// Configures Firebase with the provided iOS credentials and initiates APNs registration.
  ///
  /// This method implements multi-tenant credential injection: Firebase is configured at runtime from credentials
  /// passed by the Dart layer, enabling hot-swapping of Firebase projects without rebuilding the app.
  /// The method is idempotent: if the incoming credentials match the persisted ones and a FirebaseApp
  /// is currently initialized, it returns immediately without deleting or re-configuring Firebase,
  /// avoiding APNs re-registration and avoiding FCM registration-token invalidation.
  ///
  /// Process:
  /// 1. Extracts iOS-specific credentials from the cross-platform `PushCredentials` object.
  /// 2. Loads previously stored credentials via `PushStorage.getCredentials()`.
  /// 3. **Idempotency check**: If the stored credentials equal the incoming ones (compared field-by-field:
  ///    apiKey, appId, projectId, messagingSenderId, storageBucket) AND a FirebaseApp is currently
  ///    initialized, returns immediately with success.
  /// 4. Otherwise, persists credentials to UserDefaults (for cold-start re-initialization via `ensureFirebase()`).
  /// 5. If a FirebaseApp instance already exists, deletes it first (the completion block from `delete` is not
  ///    guaranteed to run on the main thread, so the next step is wrapped in `DispatchQueue.main.async`).
  /// 6. Configures a new FirebaseApp with the credentials and requests APNs registration.
  /// 7. Waits for APNs token registration with a 30-second timeout.
  ///
  /// Multi-tenant hot-swap: When credentials DIFFER, the delete + re-configure happens exactly as before.
  ///
  /// Note: FirebaseApp.configure must run on the main thread. The returned bool reflects APNs registration
  /// success (not just credential persistence), with a 30s timeout.
  func setCredentials(credentials: PushCredentials, completion: @escaping (Result<Bool, Error>) -> Void) {
    log("setCredentials(): starting")

    guard let iosCredentials = credentials.ios else {
      log("setCredentials(): No iOS credentials provided")
      completion(.success(false))
      return
    }

    log("setCredentials(): projectId=\(iosCredentials.projectId)")

    // Idempotency check: if credentials haven't changed and FirebaseApp is already initialized,
    // skip delete + re-configure to avoid APNs re-registration and FCM registration-token churn.
    if let storedCredentials = PushStorage.getCredentials(),
       credentialsEqual(stored: storedCredentials, incoming: iosCredentials),
       FirebaseApp.app() != nil {
      log("setCredentials(): Credentials unchanged, keeping existing FirebaseApp")
      completion(.success(true))
      return
    }

    log("setCredentials(): Credentials differ or FirebaseApp not initialized, updating")
    PushStorage.saveCredentials(iosCredentials)

    let configure = {
      DispatchQueue.main.async { [weak self] in
        self?.log("setCredentials(): Configuring FirebaseApp and requesting APNs registration")
        Self.configureFirebase(with: iosCredentials)
        UIApplication.shared.registerForRemoteNotifications()
        self?.awaitApnsToken { granted in
          completion(.success(granted))
        }
      }
    }

    if let app = FirebaseApp.app() {
      log("setCredentials(): Deleting existing FirebaseApp")
      app.delete { _ in configure() }
    } else {
      configure()
    }
  }

  /// Compares two [IosPushCredentials] objects field-by-field for equality.
  ///
  /// Since [IosPushCredentials] is a Pigeon-generated class, we cannot rely on its
  /// synthesized equality. This helper performs a manual field-by-field comparison
  /// (apiKey, appId, projectId, messagingSenderId, storageBucket) to detect changes.
  ///
  /// - Parameters:
  ///   - stored: The previously persisted credentials.
  ///   - incoming: The newly provided credentials.
  /// - Returns: true if all fields match, false otherwise.
  private func credentialsEqual(stored: IosPushCredentials, incoming: IosPushCredentials) -> Bool {
    return stored.apiKey == incoming.apiKey &&
           stored.appId == incoming.appId &&
           stored.projectId == incoming.projectId &&
           stored.messagingSenderId == incoming.messagingSenderId &&
           stored.storageBucket == incoming.storageBucket
  }

  /// Stores the device identifier in the Keychain.
  ///
  /// The device ID is persisted in the Keychain (rather than UserDefaults) because it should survive
  /// app uninstall and reinstall. This is used to derive the FCM topic `device_{deviceId}` for topic-based
  /// push delivery.
  func setDeviceId(deviceId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    log("setDeviceId(): starting, deviceId=\(deviceId.prefix(8))...")
    let success = PushStorage.saveDeviceId(deviceId)
    log("setDeviceId(): Device ID saved to Keychain, success=\(success)")
    completion(.success(success))
  }

  /// Retrieves the device identifier from the Keychain.
  ///
  /// Returns the device ID previously persisted via [setDeviceId]. Returns nil if no device ID
  /// has been stored or if retrieval from the Keychain fails (e.g., on a different iOS device
  /// after backup restore, or if the Keychain item was deleted).
  func getDeviceId(completion: @escaping (Result<String?, Error>) -> Void) {
    log("getDeviceId(): starting")
    let deviceId = PushStorage.getDeviceId()
    if deviceId != nil {
      log("getDeviceId(): Device ID retrieved successfully")
    } else {
      log("getDeviceId(): Device ID not found")
    }
    completion(.success(deviceId))
  }

  /// Subscribes the device to its FCM topic for receiving push notifications.
  ///
  /// The topic is derived as `device_{deviceId}`, which is device-specific and used by the backend
  /// to send notifications to individual devices.
  ///
  /// Behavior:
  /// - If the device ID or Firebase credentials are missing, returns false without attempting subscription.
  /// - Calls `ensureFirebase()` to re-configure Firebase if the app process restarted without a fresh `setCredentials` call.
  /// - This mechanism awaits the APNs token with a 30-second timeout before attempting subscription.
  /// - On success, stores the topic in UserDefaults via `addSubscription()` for local tracking.
  func subscribe(completion: @escaping (Result<Bool, Error>) -> Void) {
    log("subscribe(): starting")

    guard let deviceId = PushStorage.getDeviceId(), ensureFirebase() else {
      log("subscribe(): Cannot subscribe: missing device ID or credentials")
      completion(.success(false))
      return
    }

    log("subscribe(): topic=device_\(deviceId), waiting for APNs token")
    awaitApnsToken { [weak self] granted in
      guard granted else {
        self?.log("subscribe(): APNs token registration failed or timed out; cannot subscribe to topic")
        completion(.success(false))
        return
      }

      self?.log("subscribe(): APNs token available, calling subscribe(toTopic:)")
      let topic = "device_\(deviceId)"
      let startTime = Date()
      Messaging.messaging().subscribe(toTopic: topic) { [weak self] error in
        let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
        DispatchQueue.main.async {
          if let error = error {
            self?.log("subscribe(): Failed to subscribe to topic \(topic) after \(elapsed)ms: \(error.localizedDescription)")
            completion(.success(false))
            return
          }

          self?.log("subscribe(): Subscribed to topic: \(topic) in \(elapsed)ms")
          PushStorage.addSubscription(topic)
          completion(.success(true))
        }
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
  /// - This mechanism awaits the APNs token with a 30-second timeout before attempting unsubscription.
  /// - On success, removes the topic from UserDefaults via `removeSubscription()`.
  func unsubscribe(completion: @escaping (Result<Bool, Error>) -> Void) {
    log("unsubscribe(): starting")

    guard let deviceId = PushStorage.getDeviceId(), ensureFirebase() else {
      log("unsubscribe(): Cannot unsubscribe: missing device ID or credentials")
      completion(.success(false))
      return
    }

    log("unsubscribe(): topic=device_\(deviceId), waiting for APNs token")
    awaitApnsToken { [weak self] granted in
      guard granted else {
        self?.log("unsubscribe(): APNs token registration failed or timed out; cannot unsubscribe from topic")
        completion(.success(false))
        return
      }

      self?.log("unsubscribe(): APNs token available, calling unsubscribe(fromTopic:)")
      let topic = "device_\(deviceId)"
      let startTime = Date()
      Messaging.messaging().unsubscribe(fromTopic: topic) { [weak self] error in
        let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
        DispatchQueue.main.async {
          if let error = error {
            self?.log("unsubscribe(): Failed to unsubscribe from topic \(topic) after \(elapsed)ms: \(error.localizedDescription)")
            completion(.success(false))
            return
          }

          self?.log("unsubscribe(): Unsubscribed from topic: \(topic) in \(elapsed)ms")
          PushStorage.removeSubscription(topic)
          completion(.success(true))
        }
      }
    }
  }

  /// Retrieves the list of FCM topics the device is currently subscribed to.
  ///
  /// Returns the topics stored locally in UserDefaults; this reflects subscriptions initiated
  /// by this app instance, not subscriptions that may have been registered via other means.
  func getSubscriptions(completion: @escaping (Result<[String], Error>) -> Void) {
    log("getSubscriptions(): starting")
    let subs = PushStorage.getSubscriptions()
    log("getSubscriptions(): found \(subs.count) subscribed topics")
    completion(.success(subs))
  }

  // MARK: - APNs

  /// Handles successful APNs device token registration.
  ///
  /// Called by the OS when the app successfully registers for remote notifications.
  /// Assigns the APNs token to the Firebase Messaging instance so that FCM can
  /// route notifications through Apple's push service.
  ///
  /// This callback must run on the main thread (which is guaranteed by the OS).
  /// Notifies all waiters that the APNs token is now available.
  public func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    guard FirebaseApp.app() != nil else { return }
    Messaging.messaging().apnsToken = deviceToken   // token MUST be set BEFORE flushing
    log("APNs token set on Messaging instance")
    let waiters = apnsWaiters
    apnsWaiters.removeAll()
    for waiter in waiters { waiter(true) }
  }

  /// Handles APNs device token registration failure.
  ///
  /// Called by the OS when remote notification registration fails (e.g., due to network issues
  /// or invalid entitlements). Logs the error but does not stop the app.
  /// Notifies all waiters that APNs registration has failed.
  public func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    log("Failed to register for remote notifications: \(error.localizedDescription)")
    let waiters = apnsWaiters
    apnsWaiters.removeAll()
    for waiter in waiters { waiter(false) }
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

  /// Waits for the APNs token to be available with a configurable timeout.
  ///
  /// This method ensures that the APNs token is registered before attempting FCM operations
  /// that require it (topic subscribe/unsubscribe). It handles both immediate availability (if the token
  /// is already set) and delayed registration (if registration is in progress).
  ///
  /// Behavior:
  /// - If `Messaging.messaging().apnsToken` is already set, calls `completion(true)` immediately.
  /// - Otherwise, appends the completion to the `apnsWaiters` queue and schedules a timeout timer.
  /// - When the APNs registration completes (either successfully or with error), all queued waiters are notified.
  /// - If the timeout expires before registration completes, the waiter is called with `false` and logs a warning.
  ///
  /// - Parameters:
  ///   - timeout: The maximum time to wait in seconds (default: 30).
  ///   - completion: Called with `true` if the token becomes available, `false` if registration fails or times out.
  private func awaitApnsToken(timeout: TimeInterval = 30, completion: @escaping (Bool) -> Void) {
    if Messaging.messaging().apnsToken != nil {
      completion(true)
      return
    }

    var fired = false
    let safeCompletion = { granted in
      if !fired {
        fired = true
        completion(granted)
      }
    }

    apnsWaiters.append(safeCompletion)

    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
      if !fired {
        fired = true
        self?.log("APNs token registration timed out after \(Int(timeout))s")
        safeCompletion(false)
      }
    }
  }

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
