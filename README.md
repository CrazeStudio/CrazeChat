# CrazeChat

CrazeChat is a Flutter direct-messaging app by CrazeStudio. Message content is encrypted on the device using the existing X25519 + HKDF-SHA256 + AES-256-GCM envelope. The authenticated Node.js API stores encrypted envelopes and never accepts a plaintext message field.

## Architecture

- Android app: Flutter, local encrypted-message cache, device-side encryption.
- API: Node.js + Express, deployed from the backend directory (Render blueprint included).
- Database: Firebase Realtime Database, accessed only by the API using Firebase Admin credentials.
- Authentication: Per-user JWT bearer tokens signed by API_TOKEN_SIGNING_SECRET.
- CloudPurge: Receiver-confirmed server-side ciphertext deletion with a durable receipt tombstone.

The Flutter app no longer uses the generic CrazeStudio-Web ACCESS_KEY gateway. Do not put a Firebase service-account key or a shared database access key in the APK.

## Backend deployment

Deploy CrazeStudio/CrazeChat as a Render Blueprint. The render.yaml file creates the crazechat-api service.

Set these environment variables in the backend service:

| Variable | Purpose |
| --- | --- |
| DATABASE_URL | Firebase Realtime Database HTTPS URL |
| FIREBASE_SERVICE_ACCOUNT_JSON | Complete Firebase service-account JSON |
| API_TOKEN_SIGNING_SECRET | Random secret of at least 32 characters used to sign JWTs |
| ALLOWED_ORIGINS | Optional comma-separated CORS allowlist; * supports native mobile clients |

The Firebase service account must have permission to read and write the CrazeChat database. Keep the service-account JSON and JWT signing secret in backend environment variables only.

The health endpoint is /api/health; API documentation is available at /api/docs.

## Android build configuration

Set one GitHub Actions repository secret:

- API_URL: the HTTPS origin of the deployed CrazeChat API, for example https://crazechat-api.onrender.com. Do not append a route or slash path.

The old BURL and KEY secrets are no longer used by the Android application. Remove them after the new API deployment is ready.

Build locally:

~~~bash
bash tool/prepare_android.sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define=API_URL=https://YOUR-CRAZECHAT-API-ORIGIN
~~~

Backend checks:

~~~bash
cd backend
npm install --include=dev
npm test
npm start
~~~

Required backend environment variables are documented in backend/.env.example.

## Existing Firebase data compatibility

The authenticated backend deliberately uses the existing root-level Firebase paths so existing accounts and direct conversations are retained:

~~~text
users/{uid}
usernames/{usernameLower}
chats/{chatId}
userChats/{uid}/{chatId}
Massages/{chatId}/{messageId}
MassagesPurge/{chatId}/{messageId}
~~~

The message path Massages is intentionally capitalized and spelled exactly as shown for compatibility with previous CrazeChat builds.

Merge the indexes in firebase.database.rules.json into your Firebase Realtime Database rules. Keep direct client reads and writes denied. The API uses Firebase Admin credentials and does not rely on permissive mobile-client rules.

## CloudPurge lifecycle

1. The sender encrypts the message and writes a copy to the device's secure local storage before submitting it to the API.
2. The API stores the encrypted envelope under Massages/{chatId}/{messageId}.
3. The receiver downloads and decrypts the envelope.
4. The receiver saves the encrypted envelope in Flutter Secure Storage. The acknowledgement call is made only after that write completes.
5. The API verifies that the caller is a participant and is not the sender.
6. A single Firebase multi-location update writes a cloudpurge-received tombstone under MassagesPurge and removes the server-side encrypted payload.
7. Both participants keep their local encrypted copy. Sender-deletion tombstones are handled separately and remove the local display copy.

The acknowledgement is authenticated and idempotent. A receiver cannot acknowledge their own message. A failed local save or failed acknowledgement leaves the server payload available for a later retry.

Trust boundary: the server cannot remotely inspect a receiver's device storage. It relies on the authenticated official client to send the acknowledgement only after its local secure-storage write has succeeded. A modified client could lie about this; no server-side API can prove another device has durably saved a file without a trusted hardware attestation mechanism.

## Security notes

- Password hashes retain the existing PBKDF2-HMAC-SHA256 format (310,000 iterations) so existing root-level accounts remain usable.
- Login issues a seven-day signed JWT. Protected routes verify signature, issuer, audience, and expiry.
- User IDs and sender IDs are taken from the verified JWT, never from a client-supplied sender field.
- Message envelopes are size-limited and validated before database writes.
- Registration and message endpoints are rate-limited.
- Firebase direct-client rules should remain deny-by-default.
- The existing Cloudflare backend/worker.ts is a legacy implementation and is not the app API target for this release. Do not deploy it for CrazeChat until it has been brought to parity with the Node.js API and CloudPurge receipt contract.
- The current key agreement does not yet provide forward secrecy or out-of-band public-key verification. The cryptography has not been independently audited.

## Current app functions

- Username/password registration and login.
- Server-verified JWT sessions.
- Direct conversations and automatic message polling.
- Encrypted local message cache and offline outbox retry.
- CloudPurge receipt synchronization.
- In-conversation message search, copy, and sender-side deletion.
- Local account locking and account switching.

Attachments, voice messages, reactions, group chats, and calls are not included in this implementation yet.
