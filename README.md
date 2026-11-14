# CrazeChat — Native Android (Gradle)

CrazeChat is the native Android implementation of the preserved Flutter application. It uses Kotlin, Jetpack Compose, Android Keystore, the Android NDK and a C++ JNI library. The original Flutter source remains on `backup/flutter-app`.

## UI

The native UI follows the supplied charcoal/purple CrazeChat design and includes authentication, inbox, direct conversation, profile, settings, privacy/security, storage and encrypted folder-sync views.

## Features ported from the Flutter app

- Username/password registration and login, local identity unlock, sign-out, add-account and switching between up to two saved accounts.
- X25519 identity keys protected by Argon2id and AES-256-GCM, with passphrase re-wrapping and compatibility with the existing identity envelope.
- Direct one-to-one chat, authenticated WebSocket delivery with REST polling/reconnect fallback, encrypted local outbox and retry.
- Text messages, quoted replies, emoji reactions, in-chat search, copy, sender-side deletion and read receipts.
- Independent public-key fingerprint verification. Remote history sync and sending remain blocked until the contact key is verified.
- Encrypted local message cache. The app saves received encrypted envelopes before sending the read acknowledgement that causes the server to purge its copy.
- Firebase push registration and four sound/vibration notification-channel combinations. Foreground notifications use a dismissible generic banner; background notifications contain no plaintext.
- Configurable notification, sound-effect and vibration preferences.
- System, light and dark appearance.
- Screenshot blocking, manual app lock, profile-photo URL update, account-password change and separate identity-passphrase change.
- Opt-in Android Storage Access Framework folder sync. Backups use the legacy `cc-local-backup-v1` format and account-bound identity-key encryption. Import merges encrypted messages and deletion tombstones; archive reads/writes are limited to 64 MB.

## Features deliberately not shown as working controls

The old Flutter app and current server do not provide Google/Apple OAuth, email recovery, group rooms, voice/video calls, audio messages or image/file message upload. These are not exposed as functional features in this app.

## Existing backend

Default API origin:

```text
https://crazestudio-web.mehetabhoque566.workers.dev
```

CrazeChat uses the existing `/db/*` REST routes and `/api/realtime/{chatId}` WebSocket route. Requests include:

- `X-Access-Key`: the existing shared gateway value supplied at build time.
- `Authorization: Bearer <user JWT>`: the authenticated per-user session token.

The API uses usernames, not email addresses. Account passwords must be at least 12 characters. A new account also needs a separate encryption passphrase. The backend's Firebase service account, `ADMIN_KEY`, and `SESSION_SECRET` remain server-side and must never be placed in the APK.

## Build

Requirements:

- JDK 17
- Gradle 8.9
- Android SDK Platform 35 and Build Tools 35.0.0
- Android NDK 27.0.12077973
- CMake 3.22.1

Build with the same shared key configured as the backend's `ACCESS_KEY`:

```bash
export CRAZECHAT_BURL="https://crazestudio-web.mehetabhoque566.workers.dev"
export CRAZECHAT_KEY="the-backend-ACCESS_KEY"
gradle --no-daemon :app:assembleDebug
gradle --no-daemon :app:assembleRelease
```

GitHub Actions reads the `BURL` and `KEY` repository secrets; `BURL` falls back to the default Worker origin. If `KEY` is absent, the project can compile but API calls will show a configuration error.

The build generates `app/src/main/cpp/generated/craze_config.h` from the build environment. This generated file is ignored by Git. The API origin and gateway value are XOR-masked per build before being compiled into `libcraze.so`.

## Security model and limits

- Message envelopes preserve the existing wire format: X25519 key agreement, HKDF-SHA256 and AES-256-GCM.
- Identity envelopes preserve Argon2id (32 MiB, two iterations), AES-256-GCM and the existing API fields.
- The local vault uses AES-256-GCM with a key generated and retained by Android Keystore.
- Folder backups use the same legacy identity-private-key-derived HKDF parameters and account binding.
- Contact public-key fingerprints must be compared over an independent trusted channel before the client enables remote sync or sending.
- HTTPS is enforced for non-local API origins and OkHttp redirects are disabled. Android cleartext traffic is disabled.
- Release builds use R8 shrinking and restricted native symbol visibility.

**The embedded shared gateway value is not a true secret.** XOR masking and a native library add reverse-engineering friction, but a determined attacker can recover a value used by a running client. The shared gateway key must not replace per-user JWT authentication, server-side authorization, rate limits or server-side secret management.

Android Keystore protects local key material at rest. A rooted or instrumented device can still use secrets while the app is running. Local folder sync is opt-in; uninstalling or clearing app data removes the local vault. Keep the encrypted backup folder if you need to restore the message archive.

The native implementation is a code port, not an independent cryptographic audit. Before public release, complete device-level account, push, reply/reaction, migration and backup-restore tests against the production Worker and test at least one Android 13+ and one older supported device.
