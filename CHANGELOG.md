# Changelog

## 1.1.0

* Add `getDeviceId()` method to retrieve persisted device ID from secure storage
* Method returns null if no device ID has been set or if retrieval fails (e.g., Android Keystore unavailable after Auto Backup)
* Fixed: `setCredentials` is now idempotent — re-initialization only happens when credentials change; identical credentials are a no-op, avoiding FCM registration-token churn and GMS/APNs retry backoff delays
* Added: detailed step-by-step operational logging for subscribe/unsubscribe/credential operations, including FCM token acquisition timing and topic operation completion times, for improved device debugging diagnostics

## 1.0.0

* Initial release
* Runtime (and hot-swappable) Firebase credential injection through `setCredentials`
* Secure device ID storage through `setDeviceId` (Android Keystore / iOS Keychain)
* Topic subscription management through `subscribe`, `unsubscribe` and `getSubscriptions`
* Foreground push notifications through the `onPush` stream
* Firebase re-initialization at process start on both platforms, so background delivery survives app restarts and device reboots
