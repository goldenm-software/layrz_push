# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

`layrz_push` is a Flutter plugin wrapping native Firebase Cloud Messaging on **Android and iOS**
with **runtime credential injection**. Layrz is multi-tenant — each client has their own Firebase
project — so FlutterFire's compile-time config (`google-services.json` / `GoogleService-Info.plist`)
is unusable here. Credentials arrive through `setCredentials` and can be hot-swapped at any time
(the native side deletes the existing `FirebaseApp` and re-initializes).

## Architecture

Platform communication uses **Pigeon** (`pigeon: ^26.3.3`), following the `layrz_ble` conventions:

- `pigeon/layrz_push.dart` — the single source of truth for the API. After editing it, run
  `make pigeon`. Never hand-edit the generated files (`*.g.dart`, `*.g.kt`, `*.g.swift`).
- `lib/layrz_push.dart` — public facade (`LayrzPush`) + exports. Static `_platform` with
  `LayrzPush.setInstance()` for test mocking.
- `lib/src/platform_interface.dart` — abstract `LayrzPushPlatform`.
- `lib/src/layrz_push_pigeon/pigeon_channel.dart` — pigeon adapter; wires the `@FlutterApi`
  callback into a broadcast `StreamController`.
- `android/src/main/kotlin/com/layrz/layrz_push/` — `LayrzPushPlugin.kt` (host API),
  `LayrzPushMessagingService.kt` (FCM service, forwards foreground messages via the companion
  `instance`), `PushStorage.kt` (SharedPreferences + Keystore AES-GCM for the device id).
- `ios/layrz_push/Sources/layrz_push/` — `LayrzPushPlugin.swift` (host API + APNs wiring +
  `UNUserNotificationCenterDelegate`), `PushStorage.swift` (Keychain for the device id,
  UserDefaults for the rest).
- `tools/push-secrets/` — Go TUI (charmbracelet huh) that converts a pasted
  `google-services.json` / `GoogleService-Info.plist` into `example/assets/secrets.json`.
- `tools/push-sender/` — Go TUI that sends test pushes to a topic via the FCM HTTP v1 API,
  authenticated with a service account key (`service-account.json`, gitignored).

## API semantics (do not change without asking)

- `subscribe()` / `unsubscribe()` take **no arguments** — they act on the FCM topic
  `device_{deviceId}`. The FCM registration token is intentionally not exposed (topics only).
- `setDeviceId` persists the id **securely** (Android Keystore / iOS Keychain).
- `getSubscriptions()` returns a **locally tracked** list — FCM has no native API for it.
- `onPush` fires **only in foreground**, with no system banner on either platform
  (iOS `willPresent` completes with `[]`; Android FCM suppresses it natively).
- Notification permissions are the **consuming app's responsibility** — the plugin never
  requests them and declares none in its manifest.
- Credentials are persisted natively so `ensureFirebase()` can re-initialize on cold start
  (background delivery needs an initialized `FirebaseApp`). Both native sides have this guard —
  keep it when touching `subscribe`/`unsubscribe`.

## Commands

- `make pigeon` — regenerate bindings after editing `pigeon/layrz_push.dart`
- `make test` / `flutter analyze` — must both be clean before finishing
- `make run` — run the example (`$(MAKE) -C example run`)
- `make tui` — run the secrets generator
- `cd example && flutter build apk --debug` — proves the Kotlin side compiles
- `cd tools/push-secrets && go vet ./... && go test ./...` — for the Go tool

## Platform gotchas

- **iOS cannot be compiled on this Linux machine** — no Xcode. Verify Swift changes against the
  generated `LayrzPush.g.swift` signatures manually; real compilation happens on a Mac/CI.
- iOS minimum is **15.0** (required by Firebase Apple SDK 12; podspec and `Package.swift` must
  stay in sync). The podspec needs `s.static_framework = true` because of Firebase pods.
- Android intentionally has **no google-services Gradle plugin** — that's the whole point of the
  plugin. Never add it, neither here nor in the example.
- `FirebaseApp.configure` on iOS must run on the main thread, and `FirebaseApp.app()?.delete`'s
  completion is not guaranteed to be on main.
- The plugin class itself implements the pigeon host API on iOS because
  `registrar.addApplicationDelegate()` requires a `FlutterPlugin` conformer.

## Example lab

`example/` is a test lab: platform-aware credential fields, `permission_handler` for the
notification permission (iOS macro `PERMISSION_NOTIFICATIONS=1` lives in `example/ios/Podfile`),
and a `ThemedSnackbar`/`layrz_theme` UI. Credentials are plain text fields by default and can be
overridden by `example/assets/secrets.json` (gitignored; template at
`example/assets/secrets.example.json`; pubspec declares the `assets/` directory so the file may
be absent). Generate it with `make tui`.

## Git & release

- Work happens on `development`; `main` is the release branch (PR `development` → `main`).
- Follow the workspace commit conventions: split commits by logical category, stage files
  explicitly by name.
