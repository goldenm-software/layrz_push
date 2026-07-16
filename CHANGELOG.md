## 1.0.0

* Initial release
* Runtime (and hot-swappable) Firebase credential injection through `setCredentials`
* Secure device ID storage through `setDeviceId` (Android Keystore / iOS Keychain)
* Topic subscription management through `subscribe`, `unsubscribe` and `getSubscriptions`
* Foreground push notifications through the `onPush` stream
