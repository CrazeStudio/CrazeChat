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

The deployment uses two environment variables at different trust boundaries: `BURL` configures the Flutter app's upstream API origin, while `KEY` is a server-only CrazeStudio-Web gateway secret. They must never be combined into the Android app configuration.

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

Protected requests send `Authorization: Bearer {user JWT}`. The mobile app does **not** contain the Firebase service-account key or the shared CrazeStudio-Web gateway key. The existing `POST /db` operation dispatcher remains available for compatibility, and generic Firebase path operations remain separately gateway-key protected.

## CrazeStudio-Web deployment

Deploy `CrazeStudio/CrazeStudio-Web` to your selected serverless host. The current Cloudflare Worker origin used by CrazeChat is:

```text
https://crazestudio-web.mehetabhoque566.workers.dev
```

For Cloudflare, configure these server-side secrets with Wrangler (never commit their values):

```bash
npx wrangler secret put KEY
npx wrangler secret put FIREBASE_URL
npx wrangler secret put FIREBASE_SDK
npx wrangler secret put SESSION_SECRET
```

For Vercel, add the same names under Project → Settings → Environment Variables. The required backend values are:

| Variable | Purpose |
| --- | --- |
| `KEY` | Random server-only gateway secret (at least 32 bytes); used for generic database routes and readiness diagnostics. |
| `FIREBASE_URL` | HTTPS Firebase Realtime Database URL |
| `FIREBASE_SDK` | Complete service-account JSON |
| `SESSION_SECRET` | Random server-only JWT signing secret of at least 32 characters. |

The CrazeStudio-Web deployment must define `KEY` as a server-side secret (the gateway keeps `ACCESS_KEY` as a backwards-compatible alias). It is used by the generic database gateway and legacy operation endpoint; the path-based CrazeChat REST endpoints use per-user JWTs instead. **Do not pass `KEY` through `--dart-define`, Flutter assets, GitHub build output, or any Android configuration.**

Set `ALLOWED_ORIGINS` only when browser clients need an origin allowlist. Native Android requests do not send a browser Origin header.

The CrazeChat REST routes use the existing per-user JWT verification and participant checks in the CrazeStudio-Web dispatcher. Registration and login are public entry points; the gateway currently applies an in-process per-instance request throttle. Before a public production launch, configure a deployment-level rate limit/WAF for `/db/auth/register` and `/db/auth/login`, because serverless instance-local throttling is only best-effort.

## Android build

The only app build variable is the HTTPS origin of the CrazeStudio-Web deployment:

```bash
bash tool/prepare_android.sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define=BURL=https://crazestudio-web.mehetabhoque566.workers.dev
```

For GitHub Actions, configure repository secret `BURL` with `https://crazestudio-web.mehetabhoque566.workers.dev` (the workflow also has this non-secret origin as a fallback). `BURL` is compiled into the app because it is a public API origin, not a credential. The workflow runs Flutter analysis and tests on each push/PR and builds a release APK. `KEY` belongs only in CrazeStudio-Web's server environment and is not an Android or CrazeChat GitHub Actions build secret.

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
