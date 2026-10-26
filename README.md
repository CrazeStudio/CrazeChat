# CrazeChat — Flutter Android app

CrazeChat is an Android-first Flutter messaging app. It connects to the CrazeChat API on Vercel, backed by Firebase Realtime Database; Firebase service credentials are never included in the APK.

## Design

Clean blue-and-white surfaces, deep navy in dark mode, rounded inputs and message bubbles, responsive Android layouts, and system/manual theme selection.

## Build and install

The default API base URL is `https://crazechat-api.vercel.app`.

Requirements for a local build: Flutter stable, Android SDK, and Java 17.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release \
  --dart-define=CRAZECHAT_API_BASE_URL=https://crazechat-api.vercel.app
```

The **CrazeChat Android CI** workflow runs Dart analysis and regression tests, creates Android platform files if they are absent, builds a release APK on pushes to `main`, and uploads the `crazechat-android-release` artifact. Open **Actions → CrazeChat Android CI**, select a successful run, and download that artifact. The app version is `2.0.1+3).

You may change `CRAZECHAT_API_BASE_URL` to another public HTTPS API base URL at build time. This version does not need a shared installation ID in the APK.

## API contract

New installs register and log in through `POST /auth/register` and `POST /auth/login` without sending an app-wide password. The API returns a signed, user-scoped `X-API-Token` and a rotating refresh token. The client stores these tokens in Android secure storage and refreshes using `POST /auth/refresh`. The API derives the user ID from the signed token and rejects a mismatching `X-User-ID`. Legacy `POST /verify` is not part of the current sign-in flow.

Required Vercel environment variables:

- `DATABASE_URL`: Firebase Realtime Database URL (not PostgreSQL).
- `FIREBASE_SERVICE_ACCOUNT_JSON`: server-only Firebase service-account JSON.
- `API_TOKEN_SIGNING_SECRET`: long, random server-only secret for signing access tokens.
- `CRON_SECRET`: long, random secret for the cleanup endpoint.
- `API_VERIFY_KEY`: optional, for legacy clients that still use `POST /verify`.

After changing Vercel environment variables, redeploy the API. Verify `GET https://crazechat-api.vercel.app/api/health` returns `ok: true` and `database: "connected"`. A source-code commit or a passing APK build does not prove that live Vercel/Firebase is healthy.

| Feature | HTTP routes used |
| --- | --- |
| Authentication and health | `POST /auth/register`, `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout`, `GET /api/health`, `GET /api/docs` (`POST /verify` is legacy-only) |
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

Security depends on the deployed API, Firebase database rules, server environment variables, user passwords, and actual client/device behavior. Use a test Firebase project first. Keep Firebase rules closed to unauthenticated clients and configure the API with `DATABASE_URL`, `FIREBASE_SERVICE_ACCOUNT_JSON`, `API_TOKEN_SIGNING_SECRET`, and `CRON_SECRET` on Vercel. `API_VERIFY_KEY` is only for legacy clients using `/verify`.

## Test scope and limitations

The repository includes model parsing tests and a CI build. Features that require a real API/Firebase deployment (registering accounts, sending between devices, restore, group rotation, expiry cleanup, account deletion) must be integration-tested against a test backend; local source review alone cannot prove production behavior. Keep the original device and app data if an account's only private key may exist there.
