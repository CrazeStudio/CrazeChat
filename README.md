# CrazeChat

Flutter messaging app with password-protected identity keys and client-side encrypted direct messages.

## Deploy API to Cloudflare Workers

The Worker entry point is `backend/worker.ts`. It uses Firebase Realtime Database REST with service-account OAuth and Cloudflare Web Crypto; it does not run the Express/Node server.

From the repository root:

```bash
cd backend
npm install
npx wrangler login
npx wrangler secret put DATABASE_URL
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_JSON
npx wrangler secret put API_TOKEN_SIGNING_SECRET
npx wrangler secret put ACCESS_KEY
npm run build:worker
npm run deploy:worker
```

Enter the database URL, complete service-account JSON, random signing secret (at least 32 characters), and app access key when prompted. The secret names are exactly `DATABASE_URL`, `FIREBASE_SERVICE_ACCOUNT_JSON`, `API_TOKEN_SIGNING_SECRET`, and `ACCESS_KEY`.

Set GitHub Actions repository secrets:
- `BURL`: deployed Worker base URL, e.g. `https://crazechat-api.<your-subdomain>.workers.dev`.
- `KEY`: the exact same value configured as Worker secret `ACCESS_KEY`.

The Android workflow compiles these values into the app. An embedded app key can be extracted, so it is only a basic gate, not a replacement for user authentication, authorization, and abuse controls.

## Firebase

Create a Firebase project, enable Realtime Database, create a service account with database access, and keep direct client database access denied. Set `DATABASE_URL` and `FIREBASE_SERVICE_ACCOUNT_JSON` as Worker secrets. Health endpoint: `/api/health`.

## Android build

From repository root:

```bash
bash tool/prepare_android.sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define=BURL=https://YOUR-WORKER-URL --dart-define=KEY=YOUR_ACCESS_KEY
```

GitHub Actions uploads the release APK when both repository secrets `BURL` and `KEY` are configured.

## Routes

`POST /auth/register`, `POST /auth/login`, `GET /users?q=username`, `POST /chats`, `GET /chats`, `GET /chats/:chatId/messages`, `POST /chats/:chatId/messages`, `GET /api/health`, `GET /api/docs`.

## Compatibility and security notes

The Worker hashes new account passwords using PBKDF2-HMAC-SHA256 (310,000 iterations), because Workers Web Crypto does not expose Node scrypt. Existing accounts created by the previous Express backend use scrypt hashes and will not authenticate against this Worker version; recreate/migrate those accounts before switching. This initial build has no distributed rate limiter; configure Cloudflare rate limiting before public production use.

Messages remain encrypted client-side with X25519/HKDF-SHA256 and AES-256-GCM. This initial design lacks forward secrecy and out-of-band public-key verification and has not been independently audited. Do not use it for high-risk communications until reviewed.
