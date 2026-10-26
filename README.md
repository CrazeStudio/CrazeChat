# CrazeChat — Flutter rebuild

CrazeChat is being rebuilt as a Flutter Android-first messaging app. The source is organized as a standard Flutter project and uses the existing CrazeChat Vercel HTTP API rather than exposing Firebase database access from the mobile client.

## Design

The app keeps the previous CrazeChat visual direction: clean blue-and-white surfaces, deep navy in dark mode, rounded input fields and message bubbles, the forum mark, simple hierarchy, and Android-responsive layouts. Theme can follow the system or be selected manually.

## Build

Requirements: Flutter stable (Dart 3.4 or newer), Android SDK, and Java 17.

```sh
flutter create --platforms=android --org com.crazestudio --project-name crazechat .
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=CRAZECHAT_API_BASE_URL=https://crazechat-api.vercel.app --dart-define=CRAZECHAT_INSTALLATION_ID=YOUR_INSTALLATION_ID
```

The GitHub Actions workflow creates the Android platform scaffold if it is missing, analyzes and tests the Dart project, builds a release APK, and uploads the APK as a workflow artifact. A successful source commit is not the same as a successful build or live backend deployment; check the workflow and the Vercel health endpoint.

To use another API deployment, set the compile-time define `CRAZECHAT_API_BASE_URL` to its public HTTPS URL. Never put Firebase service credentials, signing secrets, API tokens, or other server secrets in Flutter source or APK build arguments.

## API contract

The API does not use Firebase Authentication or per-user auth sessions. On first use, the Flutter client calls `POST /verify` with `CRAZECHAT_INSTALLATION_ID` to obtain a web-issued, signed 24-hour `X-API-Token`. The client stores that app-access token plus the current user ID and username in platform secure storage; when the API token expires, it requests another through `/verify`. No refresh-token/session records are stored in Firebase.

Configure these server-side Vercel environment variables:

- `API_VERIFY_KEY`: the installation ID accepted by `/verify`.
- `API_TOKEN_SIGNING_SECRET`: long random secret used to sign web API tokens (legacy `TOKEN_SIGNING_SECRET` is accepted as fallback).
- `DATABASE_URL` and `FIREBASE_SERVICE_ACCOUNT_JSON`: server-only Firebase Realtime Database access.
- `CRON_SECRET`: server-only scheduled cleanup authorization.

The Flutter build must receive the matching installation ID using the compile-time define `CRAZECHAT_INSTALLATION_ID`. Never commit the value. Values compiled into an APK can be extracted, so this shared token is API access control, not strong per-user authentication.

| Feature | HTTP routes used |
| --- | --- |
| API token and health | `POST /verify`, `GET /api/health`, `GET /api/docs` |
| Registration and login | `POST /api/newuser`, `POST /auth/register`, `POST /api/user/login`, `POST /auth/login`, `POST /auth/migrate` |
| Account and password | `POST /auth/change-password`, `DELETE /auth/account`, `DELETE /api/deleteuser` |
| Compact direct chat | `GET/POST /api/chat` with `useridof1`, `useridof2`, optional `message`, `useridsendby`, and `touser` |
| Compact group chat | `GET/POST /api/groupchat` with comma-separated `userids` and optional `message` |
| Server-side purge | `DELETE /api/chat/:chatId`, `DELETE /api/groupchat/:chatId`, `POST /api/purge`, scheduled `GET /api/cron/cleanup` |
| Own profile | `GET/PUT/PATCH /api/chat/users/me` |
| Discover users | `GET /api/chat/users`, `GET /api/chat/users/:userId`, `GET /api/chat/users/by-username/:username` |
| Privacy | `GET/PATCH /api/chat/privacy/me` |
| Conversations | `POST/GET /api/chat/chats`, `GET /api/chat/chats/:chatId` |
| Group members and key envelopes | `POST /api/chat/chats/:chatId/members`, `PUT /api/chat/chats/:chatId/group-keys`, `GET /api/chat/chats/:chatId/group-key/me` |
| Encrypted messages and receipts | `POST/GET /api/chat/messages`, `POST/GET /api/chat/messages/:messageId/seen` |
| Edit, delete, pin, react | `PATCH/DELETE /api/chat/messages/:messageId`, `POST /api/chat/messages/:messageId/pin`, `POST/DELETE /api/chat/messages/:messageId/reactions` |
| Presence and public keys | `POST/GET /api/chat/presence`, `PUT /api/chat/keys/me`, `GET /api/chat/keys` |
| Encrypted backup | `PUT/GET/DELETE /api/chat/backups/me` |

The compact `/api/chat` and `/api/groupchat` routes store their `message` input as plaintext for compatibility. The Flutter app should use `POST /api/chat/messages` for end-to-end encrypted messages. Passwords are stored as salted scrypt hashes, never plaintext. Cleanup also removes old `authSessions` and `authRateLimits` nodes left by earlier versions.

## Encryption and privacy

- Direct-message format follows the earlier Android implementation: P-256 ECDH, SHA-256 of the shared secret, AES-256-GCM, base64 ciphertext-plus-tag and base64 nonce.
- Profile/key backup follows the existing `CCP2:` format: random 16-byte salt, PBKDF2-HMAC-SHA256 with 600,000 iterations, AES-GCM with `CrazeChatProfileV2` additional authenticated data.
- Group messages use versioned AES-GCM ciphertext with `G2v<version>:` prefix and `CrazeChatGroupV2:<version>` associated data. The group owner creates one encrypted key envelope per member.
- Private keys and session tokens are stored through Flutter secure storage, not SharedPreferences or the database.
- Old unversioned group messages may be readable using the legacy compatibility key, but that previous format used a constant embedded in the old app and must not be treated as confidential.

Security depends on the deployed API, Firebase database rules, server environment variables, user passwords, and actual client/device behavior. Use a test Firebase project first. Keep Firebase rules closed to unauthenticated clients and configure the companion API with server-side `DATABASE_URL`, `FIREBASE_SERVICE_ACCOUNT_JSON`, `TOKEN_SIGNING_SECRET`, and `CRON_SECRET`.

## Test scope and limitations

The repository includes model parsing tests and a CI build. Features that require a real API/Firebase deployment (registering accounts, sending between devices, restore, group rotation, expiry cleanup, account deletion) must be integration-tested against a test backend; local source review alone cannot prove production behavior. Keep the original device and app data if an account's only private key may exist there.
