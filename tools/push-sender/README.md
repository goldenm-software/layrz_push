# push-sender

TUI companion for the `layrz_push` example lab: sends test push notifications to an
FCM topic through the HTTP v1 API, so you don't need the Firebase console campaigns
wizard to test the plugin.

## Requirements

A Firebase **service account key** for the tenant project:
Firebase console → Project settings → Service accounts → **Generate new private key**.

Save it as `tools/push-sender/service-account.json` (gitignored) or pass `-account <path>`.

## Usage

```bash
cd tools/push-sender
go run .
```

1. The topic is prefilled from the lab's `example/assets/secrets.json` (`device_{deviceId}`).
2. Set title/body (or leave both empty and use only `key=value` data pairs for a data-only message).
3. Send — the FCM message id is printed, and the loop lets you send as many as you need.

Remember the plugin's semantics while testing: app in foreground → the notification reaches the
`onPush` stream with no system banner; app in background or killed → the system displays it.
