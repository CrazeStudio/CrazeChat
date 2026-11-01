# CrazeChat

CrazeChat is a Flutter direct-messaging app by CrazeStudio. Message content is encrypted on the device with X25519, HKDF-SHA256, and AES-256-GCM. The API stores encrypted message envelopes and never receives plaintext message content.

## Architecture

```text
CrazeChat Android (Flutter)
        |
        | HTTPS + per-user JWT
        v
CrazeStudio-Web (/db/* path-based REST API)
        |
        | server-side Firebase service account
        v
Firebase Realtime Database
```

**CrazeStudio-Web is the only API/backend for this app.** The app does not deploy or require a separate Express, Node, or Render service. The `backend/` and `render.yaml` files are legacy artifacts and are not part of the current deployment path.

The deployment uses `BURL` for the Flutter app's API origin, `KEY` as the Flutter build variable sent in the `X-Access-Key` request header, and `ACCESS_KEY` as the backend environment variable. Frontend `KEY` and backend `ACCESS_KEY` must contain the identical value.

## API contract

The Flutter client uses these path-based endpoints on the CrazeStudio-Web deployment:

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/db/auth/register` | Create account and encrypted identity backup |
| POST | `/db/auth/login` | Authenticate and receive a user JWT |
| GET | `/db/auth/session` | Validate the current session |
| GET | `/db/users/search?query=name` | Search usernames |
| GET | `/db/chats` | List the signed-in user's conversations |
| POST | `/db/chats` | Create or open a direct conversation |
| GET | `/db/chats/{chatId}/messages` | Synchronize encrypted messages |
| POST | `/db/chats/{chatId}/messages` | Send an encrypted message |
| DELETE | `/db/chats/{chatId}/messages/{messageId}` | Delete a message sent by the current user |
| GET | `/db/chats/{chatId}/purges` | Synchronize CloudPurge receipts |
| POST | `/db/chats/{chatId}/purges/{messageId}/acknowledge` | Acknowledge a received message |

Every request sends `X-Access-Key: {KEY}`. Protected requests also send `Authorization: Bearer {user JWT}`; the Authorization header is reserved for the user's JWT. The mobile app does **not** contain the Firebase service-account key. The existing `POST /db` operation dispatcher and generic Firebase path operations use the same shared-key check.

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

The CrazeChat REST routes use the existing per-user JWT verification and participant checks in the CrazeStudio-Web dispatcher. Registration and login are public entry points; the gateway currently applies an in-process per-instance request throttle. Before a public production launch, configure a deployment-level rate limit/WAF for `/db/auth/register` and `/db/auth/login`, because serverless instance-local throttling is only best-effort.

## Android build

The only app build variable is the HTTPS origin of the CrazeStudio-Web deployment:

```bash
bash tool/prepare_android.sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release \\
  --dart-define=BURL=https://crazestudio-web.mehetabhoque566.workers.dev \\
  --dart-define=KEY=YOUR_SHARED_KEY
```

For GitHub Actions, configure `BURL` with `https://crazestudio-web.mehetabhoque566.workers.dev` (the workflow has this origin as a fallback) and configure repository secret `KEY` with exactly the same value as backend `ACCESS_KEY`. The workflow compiles both values into the APK. `ACCESS_KEY` itself remains a backend environment variable and is not the Flutter build-variable name.

## Database and privacy

- Accounts are stored under `Users/{sha256-lowercase-username}`.
- Direct conversations are stored under `Massages/chats/{chatId}`.
- Participants are recorded in the existing `participents` node for compatibility.
- Encrypted messages are stored under `Massages/chats/{chatId}/massages/{messageId}`.
- CloudPurge receipts are stored under `Massages/chats/{chatId}/purges/{messageId}`.
- Firebase direct-client reads and writes must remain denied. CrazeStudio-Web accesses Firebase using its server-side service account.
- The API validates JWT sessions and verifies conversation membership before returning or mutating conversation data.
- The current key agreement does not yet provide forward secrecy or out-of-band public-key verification; the cryptographic design has not been independently audited.

## Current app functions

- Username/password registration and login.
- Device-encrypted identity backup and local unlock.
- Server-verified JWT sessions and account switching.
- Direct conversations and periodic inbox/message synchronization.
- X25519 + HKDF-SHA256 + AES-256-GCM message encryption.
- Encrypted local message cache and offline send retry.
- CloudPurge receipt synchronization.
- In-conversation search, copy, and sender-side deletion.
- Local account locking and secure-storage-backed session persistence.

Attachments, voice messages, reactions, group chats, and calls are not implemented in this release.
