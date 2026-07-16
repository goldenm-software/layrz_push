# layrz_push

[![Pub version](https://img.shields.io/pub/v/layrz_push?logo=flutter)](https://pub.dev/packages/layrz_push)
[![likes](https://img.shields.io/pub/likes/layrz_push?logo=flutter)](https://pub.dev/packages/layrz_push/score)
[![GitHub license](https://img.shields.io/github/license/goldenm-software/layrz_push?logo=github)](https://github.com/goldenm-software/layrz_push)

A Flutter plugin to handle push notifications on Android and iOS using Firebase Cloud Messaging with
**runtime credential injection**.

## Why?

Layrz is multi-tenant: each client has their own Firebase project. FlutterFire hardcodes the Firebase
configuration at compile time (`google-services.json` / `GoogleService-Info.plist`), which doesn't work
when the credentials are only known at runtime. This plugin wraps the native Firebase Messaging SDKs
directly and initializes Firebase with credentials injected on the go — they can even be replaced at
any time (hot-swap between tenants).

## Minimum requirements

### Android

Android 7.0 Nougat (API Level 24) or later.

### iOS

iOS 15.0 or later (required by the Firebase Apple SDK).

## Usage

```dart
import 'package:layrz_push/layrz_push.dart';

final push = LayrzPush();

/// Inject the Firebase credentials at runtime. Each platform reads its own
/// sub-object; calling this again replaces the previous Firebase app.
await push.setCredentials(
  credentials: PushCredentials(
    android: AndroidPushCredentials(
      apiKey: '...',             // client[].api_key[].current_key of google-services.json
      appId: '...',              // client[].client_info.mobilesdk_app_id
      projectId: '...',          // project_info.project_id
      messagingSenderId: '...',  // project_info.project_number
    ),
    ios: IosPushCredentials(
      apiKey: '...',             // API_KEY of GoogleService-Info.plist
      appId: '...',              // GOOGLE_APP_ID
      projectId: '...',          // PROJECT_ID
      messagingSenderId: '...',  // GCM_SENDER_ID
    ),
  ),
);

/// Set the Layrz device ID. It's stored securely on the device
/// (Android Keystore / iOS Keychain) and defines the FCM topic
/// used by subscribe/unsubscribe: `device_{deviceId}`.
await push.setDeviceId(deviceId: 'my-device-id');

/// Subscribe to the `device_{deviceId}` topic.
await push.subscribe();

/// List the currently subscribed topics (tracked locally,
/// FCM has no native API for this).
final topics = await push.getSubscriptions();

/// Listen for push notifications while the app is in FOREGROUND.
/// Background/terminated notifications are displayed by the system.
push.onPush.listen((PushNotification notification) {
  print('${notification.title}: ${notification.body} - ${notification.data}');
});

/// Unsubscribe from the `device_{deviceId}` topic.
await push.unsubscribe();
```

## Permissions and requirements

The handling of the notification permission is **not part of this library**, so you need to take care of
it by yourself: the plugin never asks the user for permission. You can use the
[`permission_handler`](https://pub.dev/packages/permission_handler) package to handle the permissions on
your Flutter app, or you can handle them manually with native code, the choice is yours. Without the
permission granted, notifications are silently not displayed.

### Android

Declare the notification permission in your app's `AndroidManifest.xml` (required to display
notifications since Android 13 / API Level 33) and request it at runtime:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <!-- Required to display notifications since Android 13 (API Level 33) -->
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

  <!-- ... -->
</manifest>
```

You do **not** need `google-services.json` nor the `com.google.gms.google-services` Gradle plugin —
credentials are injected at runtime via `setCredentials`.

### iOS

- Request the notification authorization through `UNUserNotificationCenter` (native code) or any
  permissions package like [`permission_handler`](https://pub.dev/packages/permission_handler).
- Enable the **Push Notifications** capability in your Xcode project (Runner target → Signing &
  Capabilities). For background delivery, also enable **Background Modes → Remote notifications**.
- Upload an APNs authentication key (or certificate) to **each tenant's Firebase project**
  (Project settings → Cloud Messaging), otherwise Apple devices will never receive the pushes.

You do **not** need `GoogleService-Info.plist` — credentials are injected at runtime via
`setCredentials`.

## Foreground behavior

When the app is in foreground, notifications are **not** displayed by the system on either platform;
they are only delivered to the `onPush` stream, so the app decides how to present them. When the app
is in background or terminated, the system displays them and `onPush` does not fire.

## FAQ

### Why does `subscribe()` return `false`?

`subscribe()`/`unsubscribe()` require both `setCredentials()` and `setDeviceId()` to have been called
before. They also return `false` when FCM rejects the operation (for example, no network).

### Do you support Web, macOS, Windows or Linux?

Not for now. The plugin is focused on the mobile platforms used by Layrz apps. However, if you want to contribute, feel free to reach us with a PR, we're open to contributors!

### Do I need `google-services.json` or `GoogleService-Info.plist`?

No — that's the whole point of this plugin. Credentials are injected at runtime via `setCredentials`.

### Why is this package called `layrz_push`?

All packages developed by [Layrz](https://layrz.com) are prefixed with `layrz_`, check out our other packages on [pub.dev](https://pub.dev/publishers/goldenm.com/packages).

### Do you have other libraries?

Of course! We have multiple libraries (for Layrz or general purpose) that you can use in your projects, you can find us on [PyPi](https://pypi.org/user/goldenm/) for Python libraries, [RubyGems](https://rubygems.org/profiles/goldenm) for Ruby gems, [NPM of Golden M](https://www.npmjs.com/~goldenm) or [NPM of Layrz](https://www.npmjs.com/~layrz-software) for NodeJS libraries or here in [Pub.dev](https://pub.dev/publishers/goldenm.com/packages) for Dart/Flutter libraries.

### I need to pay to use this package?

**No!** This library is free and open source, you can use it in your projects without any cost, but if you want to support us, give us a thumbs up here in [pub.dev](https://pub.dev/packages/layrz_push) and star our [Repository](https://github.com/goldenm-software/layrz_push)!

### Can I contribute to this package?

**Yes!** We are open to contributions, feel free to open a pull request or an issue on the [Repository](https://github.com/goldenm-software/layrz_push)!

### I have a question, how can I contact you?

If you need more assistance, you open an issue on the [Repository](https://github.com/goldenm-software/layrz_push) and we're happy to help you :)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Who are you? / Want to work with us?

**Golden M** is a software and hardware development company what is working on a new, innovative and disruptive technologies. For more information, contact us at [sales@goldenm.com](mailto:sales@goldenm.com) or via WhatsApp at [+(507)-6979-3073](https://wa.me/50769793073?text="From%20layrz_push%20flutter%20library.%20Hello").
