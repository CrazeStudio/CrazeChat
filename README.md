# CrazeChat

CrazeChat is a Flutter direct-messaging app by CrazeStudio. Message content is encrypted on the device with X25519, HKDF-SHA256, and AES-256-GCM. The API stores encrypted message envelopes and never receives plaintext message content.

## Local message retention and server purge

Incoming messages are decrypted for display, then their **encrypted envelopes** are durably written to Android secure storage before a read acknowledgement is sent. The backend deletes its Firebase message payload after the read acknowledgement succeeds. That server-side deletion never removes or hides the receiver's local copy: ChatView reloads the encrypted local history on every open, including after an app restart.

The `message_deleted` WebSocket event describes remote server-copy deletion only; the client deliberately ignores it for local history. Local messages are scoped by authenticated user ID and chat ID, so switching accounts does not mix their caches. Message content is decrypted only in memory for display.

There is no persistent Firebase `purges` collection or deletion tombstone. Incoming delivery is push-only over the authenticated WebSocket; message history is fetched on initial connection/reconnection. The 20-second timer retries queued outgoing messages only.

**Device-retention limitation:** uninstalling the app, clearing its data, or losing the device without an enabled and recent local folder backup permanently loses that device's locally retained message history after the server copy has been purged. Android secure storage protects individual cache records, but this per-message key/value cache is not a substitute for a scalable encrypted database.

Message send/receive actions use the platform's short system sound. Profile avatars currently use generated initials and stable colors; uploaded photo avatars are not supported yet.

The signed-in session and identity key are stored using Android secure storage backed by the platform keystore. Reopening the app restores the session and key automatically while the JWT remains valid, unless CrazeChat was manually locked or was in the background for at least five minutes with auto-lock enabled; in either case, the identity must be unlocked again. An expired/revoked session still requires sign-in.

## Architecture

```text
CrazeChat Android (Flutter)
        |
        | HTTPS + X-Access-Key + per-user JWT
        v
CrazeStudio-Web (/db/* path-based REST API)
        |
        | server-side Firebase service account
        v
Firebase Realtime Database
```

**CrazeStudio-Web is the only API/backend for this app.** The app does not deploy or require a separate Express, Node, or Render service. The `backend/` and `render.yaml` files are legacy artifacts and are not part of the current deployment path.

The deployment uses `BURL` for the Flutter app's API origin, `KEY` as the Flutter build variable sent in the `X-Access-Key` request header, and `ACCESS_KEY` as the backend environment variable. Frontend `KEY` and backend `ACCESS_KEY` must contain the identical value. The separate server-only `ADMIN_KEY` protects generic Firebase paths and the legacy bare `POST /db` operation dispatcher; CrazeChat mobile builds must never contain it.

## API contract

The Flutter client uses these path-based endpoints on the CrazeStudio-Web deployment:

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/db/auth/register` | Create account and encrypted identity backup |
| POST | `/db/auth/login` | Authenticate and receive a user JWT |
| POST | `/db/auth/update-identity` | Replace the encrypted identity envelope after client-side passphrase migration |
| GET | `/db/auth/session` | Validate the current session |
| GET | `/db/users/search?query=name` | Search usernames |
| GET | `/db/chats` | List the signed-in user's conversations |
| POST | `/db/chats` | Create or open a direct conversation |
| GET | `/db/chats/{chatId}/messages` | Synchronize encrypted messages |
| POST | `/db/chats/{chatId}/messages` | Send an encrypted message |
| DELETE | `/db/chats/{chatId}/messages/{messageId}` | Delete a message sent by the current user |
| POST | `/db/chats/{chatId}/messages/acknowledge` | Acknowledge delivery/read; a read acknowledgement purges the server payload |

CrazeChat app REST requests send `X-Access-Key: {KEY}`. Protected requests also send `Authorization: Bearer {user JWT}`; the Authorization header is reserved for the user's JWT. The mobile app does **not** contain the Firebase service-account key or `ADMIN_KEY`. Generic Firebase path operations and the legacy bare `POST /db` dispatcher require the separate server-only `X-Admin-Key`.

## CrazeStudio-Web deployment

Deploy `CrazeStudio/CrazeStudio-Web` to your selected serverless host. The current Cloudflare Worker origin used by CrazeChat is:

```text
https://crazestudio-web.mehetabhoque566.workers.dev
```

For Cloudflare, configure these server-side secrets with Wrangler (never commit their values):

```bash
npx wrangler secret put ACCESS_KEY
npx wrangler secret put FIREBASE_URL
npx wrangler secret put FIREBASE_SDK
npx wrangler secret put SESSION_SECRET
```

For Vercel, add the same names under Project → Settings → Environment Variables. The required backend values are:

| Variable | Purpose |
| --- | --- |
| `ACCESS_KEY` | Shared gateway key (32+ random bytes recommended); it must match the CrazeChat frontend `KEY` value exactly. |
| `FIREBASE_URL` | HTTPS Firebase Realtime Database URL |
| `FIREBASE_SDK` | Complete service-account JSON |
| `SESSION_SECRET` | Random server-only JWT signing secret of at least 32 characters. |

The CrazeStudio-Web deployment must define `ACCESS_KEY` server-side. Every `/db/*` request, including registration and login, must send the matching value in `X-Access-Key`. Protected chat routes additionally validate per-user JWTs and conversation membership. In Flutter, use the build-variable name `KEY`; never define `ACCESS_KEY` in the app.

Set `ALLOWED_ORIGINS` only when browser clients need an origin allowlist. Native Android requests do not send a browser Origin header.

**Security limit:** `KEY` is embedded in the APK and can be extracted. Treat it as a shared app-gateway gate, not as a confidential credential or a replacement for user authentication. Keep per-user JWT checks, participant authorization, and server-side rate limits enabled.

The client accepts only HTTPS API origins for remote servers and uses `wss` for remote realtime traffic. Android blocks cleartext networking except for the explicit local-development hosts `localhost`, `127.0.0.1`, and `10.0.2.2`.

Signing out clears the session on this device, but the current separately deployed backend has no logout/revocation route in this repository; an already copied JWT may remain usable until its server-side expiry. Keep JWT lifetimes short and add server-side revocation/refresh-token rotation before relying on logout to invalidate stolen tokens.

The CrazeChat REST routes use the existing per-user JWT verification and participant checks in the CrazeStudio-Web dispatcher. Registration and login are public entry points; the gateway currently applies an in-process per-instance request throttle. Before a public production launch, configure a deployment-level rate limit/WAF for `/db/auth/register` and `/db/auth/login`, because serverless instance-local throttling is only best-effort.

## Android build

The app has two build variables: `BURL` is the HTTPS origin of CrazeStudio-Web and `KEY` is the shared value matching backend `ACCESS_KEY`:

```bash
bash tool/prepare_android.sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release \
  --dart-define=BURL=https://crazestudio-web.mehetabhoque566.workers.dev \
  --dart-define=KEY=YOUR_SHARED_KEY \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_OAUTH_CLIENT_ID
```

For GitHub Actions, configure `BURL` with `https://crazestudio-web.mehetabhoque566.workers.dev` (the workflow has this origin as a fallback), repository secret `KEY` with exactly the same value as backend `ACCESS_KEY`, `ACCESS_KEY` itself remains a backend environment variable and is not the Flutter build-variable name.

### Background notifications (FCM)

Background notifications use Firebase Cloud Messaging HTTP v1. Add an Android app in the **same Firebase project** used by CrazeStudio-Web, with package name `com.crazestudio.crazechat`, then download its `google-services.json`.

- This repository currently tracks `android/app/google-services.json` as public Firebase Android client configuration; CI verifies its hash and project identity. `tool/prepare_android.sh` generates the Dart Firebase options from that file. If you switch Firebase projects, update the file and the matching CI assertions.
- The Firebase Android API key in this file is client configuration, not a service-account secret, and can be extracted from the APK. Restrict it in Google Cloud to the CrazeChat Android package/signing certificates and only the APIs the app needs. Never put a Firebase Admin/service-account JSON file in the app or repository.
- Enable the Firebase Cloud Messaging API for the Google Cloud project used by Firebase. The backend service account must be allowed to send FCM messages.

The server sends a generic notification (no message text) and opaque chat/message IDs. The user opens the app to decrypt and view the locally synchronized message. Replies and reactions also travel as encrypted message envelopes. Android notification permission must also be allowed by the device user.

## Encrypted local folder sync

Local sync is available in **Settings → Local Folder Sync**. Choose a folder through Android's system folder picker. CrazeChat stores a file named `crazechat-encrypted-backup.json` in that folder and retains the folder permission across app restarts. The app reads the previous backup, merges encrypted message envelopes and deletion tombstones, then writes an updated encrypted archive.

Before writing, the archive is encrypted with AES-256-GCM using a key derived from the unlocked CrazeChat identity key. The selected folder contains no plaintext message text. Restoring requires the same CrazeChat account and unlocked identity. Automatic sync is debounced after message changes and attempted when the app resumes. The archive is limited to 64 MB and includes messages retained in the device's local cache.

Changing the selected folder does not erase the previous folder's backup. Copying the encrypted backup file to another device or storage location is supported; select the destination folder on that device and sync using the same CrazeChat identity. Local folder sync is not a live cloud synchronization service: the selected folder must be accessible to Android when sync runs.

## Database and privacy

- Accounts are stored under `Users/{sha256-lowercase-username}`.
- Direct conversations are stored under `Massages/chats/{chatId}`.
- Participants are recorded in the existing `participents` node for compatibility.
- Encrypted messages are stored under `Massages/chats/{chatId}/massages/{messageId}`.
- Read acknowledgements delete the server-side message payload directly; no server-side purge receipts or tombstones are stored. Opt-in local archives use client-encrypted deletion tombstones to prevent deleted messages from returning on another device.
- Firebase direct-client reads and writes must remain denied. CrazeStudio-Web accesses Firebase using its server-side service account.
- The API validates JWT sessions and verifies conversation membership before returning or mutating conversation data.
- The current key agreement does not yet provide forward secrecy or out-of-band public-key verification; the cryptographic design has not been independently audited.

## Identity-key protection

New accounts use two independent secrets:

- **Account password** authenticates with CrazeStudio-Web and is verified by the backend.
- **Encryption passphrase** derives the Argon2id wrapping key for the X25519 identity private key. It stays on the device and is never sent to the API.

The encrypted identity envelope uses version 2 (`keyProtection: separate-passphrase-v2`) for accounts using separate key protection. Changing the account password does not re-encrypt the identity envelope. The encryption passphrase can be changed while the identity is unlocked; only the new encrypted envelope is uploaded through the authenticated `/db/auth/update-identity` route. The backend must preserve the existing public key when accepting an envelope update.

Existing version-1 and version-3 accounts remain readable using their previous account password. After signing in, use Settings → Set separate encryption passphrase to migrate the identity key to version 2. Keep the new passphrase safe: the server cannot recover it. A new device will need the encryption passphrase to unlock a version-2 envelope.

The native configuration library only obfuscates the shared API key in the Android binary. It does not make a client-embedded key secret. Actual access control depends on authenticated user sessions, server-side authorization, and rate limits.

## Contact public-key verification

Before sending messages or reactions to a contact, compare the contact's SHA-256 public-key fingerprint with them over a separate trusted channel (in person or a voice/video call). Open the fingerprint icon in the conversation header. Unverified contacts cannot receive outgoing messages or reactions; queued messages are not sent until verification. Fingerprints are stored locally per contact. If a previously verified contact's key changes, the app displays a warning and blocks sending until the replacement fingerprint is independently checked. Never accept a fingerprint sent only inside the conversation being verified.

This is manual trust-on-first-use with local pinning, not a formal key-transparency service. Reinstalling or clearing app data removes the local trusted-fingerprint store, so verify contacts again.

## Current app functions

- Username/password registration and login.
- Device-encrypted identity backup and local unlock.
- Server-verified JWT sessions and account switching.
- Direct conversations, WebSocket foreground delivery, and Firebase Cloud Messaging background alerts.
- X25519 + HKDF-SHA256 + AES-256-GCM message encryption for text, replies, and reaction events.
- Encrypted local message cache and offline send retry.
- Opt-in, identity-key-encrypted local folder message sync with account isolation and merge-safe deletion tombstones.
- Read acknowledgement triggers server-side payload deletion while retaining the encrypted local copy and local reply/reaction history.
- WhatsApp-style quoted replies and emoji reactions.
- In-conversation search, copy, and sender-side deletion.
- Configurable push notifications, sound effects, vibration, and System/Light/Dark appearance.
- Local account locking, secure-storage-backed session persistence, and optional five-minute background auto-lock.

Attachments, voice messages, group chats, and calls are not implemented in this release.
