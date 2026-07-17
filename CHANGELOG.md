# Changelog

## 1.0.0

* Initial release
* Runtime (and hot-swappable) Firebase credential injection through `setCredentials`
* Secure device ID storage through `setDeviceId` (Android Keystore / iOS Keychain)
* Topic subscription management through `subscribe`, `unsubscribe` and `getSubscriptions`
* Foreground push notifications through the `onPush` stream
* Firebase re-initialization at process start on both platforms, so background delivery survives app restarts and device reboots
