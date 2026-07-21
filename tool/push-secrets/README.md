# push-secrets

TUI companion for the `layrz_push` example lab: converts a `google-services.json`
(Android) or a `GoogleService-Info.plist` (iOS) into the values required by
`example/assets/secrets.json`.

## Usage

```bash
cd tools/push-secrets
go run .
```

1. Paste the raw content of the file — the format is auto-detected (JSON → Android, plist → iOS).
2. If the `google-services.json` has multiple apps, pick the package.
3. Review the extracted values, set the device ID and confirm.
4. The tool merges into the existing `example/assets/secrets.json` (or creates it),
   so you can run it twice to add both platforms.

Use `-output <path>` to write somewhere else.
