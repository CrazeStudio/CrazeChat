# CrazeChat — Native Android / Gradle

CrazeChat is being rebuilt as a native Android application using Kotlin, Jetpack Compose, the Android NDK and a C++ shared library. The original Flutter project remains preserved on `backup/flutter-app`.

## App structure

- `app/`: Kotlin Android application and Jetpack Compose UI
- `app/src/main/cpp/`: C++ JNI library built as `libcraze.so`
- `app/src/main/java/.../security/CryptoService.kt`: identity and message cryptography
- `SecureVault.kt`: encrypted local data vault protected by Android Keystore
- `CrazeChatApi.kt`: HTTPS REST and authenticated WebSocket client

## Design implementation

The native app follows the supplied six-page CrazeChat design: dark charcoal surfaces, purple gradient actions, branded authentication, conversation list, message view, profile, and settings.

A few elements in the mockup are visual concepts that the current server cannot support yet. The current CrazeStudio-Web deployment provides username/password authentication, direct one-to-one conversations, encrypted text messages, profile-photo URLs, message delivery/read events, and generic push notifications. It does not currently expose Google/Apple OAuth, email/password recovery, phone/video calling, group chats, voice messages, or media upload. These are not represented as working features in the Gradle app.

The existing API uses usernames rather than email addresses. Account creation requires an account password and a separate encryption passphrase. The separate passphrase protects the X25519 private identity key.

## Backend

Default API origin:

```text
https://crazestudio-web.mehetabhoque566.workers.dev
```

CrazeChat calls the existing `/db/*` API using:

- `X-Access-Key`: build-time shared gateway value
- `Authorization: Bearer <user JWT>`: per-user session token

The backend keeps its Firebase service account, `ADMIN_KEY`, and `SESSION_SECRET` on the server. Never add those values to the Android project.

## Build requirements

- JDK 17
- Gradle 8.9
- Android SDK Platform 35 / Build Tools 35.0.0
- Android NDK 27.0.12077973
- CMake 3.22.1

Set the API key and build:

```bash
export CRAZECHAT_BURL="https://crazestudio-web.mehetabhoque566.workers.dev"
export CRAZECHAT_KEY="the-same-value-as-backend-ACCESS_KEY"
gradle --no-daemon :app:assembleDebug
gradle --no-daemon :app:assembleRelease
```

The CI workflow reads `BURL` and `KEY` repository secrets; `BURL` has the public Worker origin as a fallback. If `KEY` is absent, the APK still builds but API calls will display a clear configuration error.

The build generates `app/src/main/cpp/generated/craze_config.h` locally from the environment. It is ignored by Git. The API origin and gateway key are XOR-masked per build before they are compiled into `libcraze.so`.

## Security model

- Messages use the existing wire format: X25519 agreement, HKDF-SHA256, and AES-256-GCM.
- Identity private keys are wrapped with Argon2id and AES-256-GCM using a separate passphrase. The envelope remains compatible with the current Worker API.
- Local session data and encrypted message envelopes are stored in an AES-256-GCM vault. The AES key is generated and retained by Android Keystore.
- A new contact's SHA-256 public-key fingerprint must be compared using an independent trusted channel and verified before remote message sync or sending is enabled.
- Incoming encrypted message envelopes are saved to the local vault before the client sends a read acknowledgement. The Worker deletes its remote message copy after a successful read acknowledgement.
- Cleartext networking and HTTP redirects are disabled for API requests.
- Release builds enable R8 shrinking and C++ symbol visibility restrictions.

### Important limitations

The native library and XOR-masked configuration raise the effort needed to inspect the APK, but they cannot make a client-side gateway key secret. A determined attacker can recover it from a running application. Treat `ACCESS_KEY` as a shared application gateway gate only; per-user JWT authentication and server-side authorization remain essential.

Android Keystore protects local keys at rest, but a rooted or instrumented device can still misuse them while the app is running. No client can guarantee protection after full device compromise.

The encrypted message cache is currently held in a Keystore-encrypted local vault and bounded to the most recent 10,000 envelopes per conversation. The Gradle rebuild does not yet include the Flutter app's folder-backup/export workflow. Uninstalling or clearing app data removes the local vault.

This is a first native Gradle implementation, not a completed independent cryptographic audit. Verify backend configuration and run the Android CI build before distributing a release.
