# CrazeChat

CrazeChat is a Flutter Android messaging app with password-protected identity keys and end-to-end encrypted direct messages. The app is designed so the API and Firebase database receive ciphertext, not readable message text.

## Included

- Username/password account registration and sign-in.
- Server-side password verification using salted scrypt hashes.
- X25519 identity keys created on the device.
- The account password derives an Argon2id wrapping key that encrypts the private identity key with AES-256-GCM.
- Encrypted identity-key backup stored on the API, allowing restore on another device with the same password.
- X25519 + HKDF-SHA256 derives a shared direct-chat key.
- AES-256-GCM encrypts each message on-device with chat/sender context as authenticated additional data.
- Firebase stores user metadata, public keys, encrypted identity envelopes, and encrypted message envelopes.
- Flutter secure storage holds the session token and encrypted local identity backup.
- Android CI runs analysis, crypto tests, and produces a release APK.
- A Render Blueprint deploys the Node.js API. No Firebase service-account key is included in the repository or APK.

## Encryption model

The login password is not sent as the message-encryption key. It is used on-device with Argon2id to unlock the user's encrypted X25519 private key. Two chat participants use X25519 and HKDF-SHA256 to derive the same conversation secret, then AES-256-GCM encrypts each message with a fresh nonce. The API stores the encrypted envelope; it does not have the private keys or chat secret.

This is end-to-end encryption, not a promise that data is mathematically impossible to recover. Weak passwords, compromised devices, modified client builds, screenshots, notifications, and implementation flaws can still expose information. The initial direct-chat design uses long-lived identity keys and does not provide forward secrecy against later identity-key compromise. Do not use this first release for high-risk communications until it has had an independent security review.

If a user loses the account password and has no unlocked device, the encrypted private key cannot be recovered by CrazeStudio. There is no password reset that can decrypt the old key.

## Deploy the API on Render

1. Create a Firebase project and enable Realtime Database.
2. Create a Firebase service account and keep its JSON private.
3. In Firebase Realtime Database Rules, apply the contents of \`firebase.database.rules.json\`. These deny direct client reads and writes; the API uses the Admin SDK.
4. In Render, create a Blueprint from this repository and configure:
   - \`DATABASE_URL\`: the Realtime Database URL.
   - \`FIREBASE_SERVICE_ACCOUNT_JSON\`: the entire service-account JSON.
   - \`API_TOKEN_SIGNING_SECRET\`: a random secret of at least 32 characters.
   - \`ALLOWED_ORIGINS\`: leave \`*\` for native Android, or set exact web origins later.
5. After deployment, open \`https://YOUR-RENDER-SERVICE.onrender.com/api/health\`. It must report \`ok: true\` and \`database: "connected"\`.

Never paste service-account JSON or signing secrets into GitHub, source files, or chat. Rotate any secret that has been exposed.

## Build the Android app

Install Flutter stable, Android Studio / Android SDK, and Java 17 or newer. From the repository root:

\`\`\`bash
bash tool/prepare_android.sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define=CRAZECHAT_API_BASE_URL=https://YOUR-RENDER-SERVICE.onrender.com
\`\`\`

The APK is created at \`build/app/outputs/flutter-apk/app-release.apk\`. GitHub Actions also uploads it as the \`crazechat-android-release\` artifact after a successful build.

For local API development, copy \`backend/.env.example\` to \`backend/.env\`, fill in Firebase values, then run \`cd backend && npm install && npm run dev\`. Use \`http://10.0.2.2:3000\` for an Android emulator or your computer's LAN IP for a physical device.

## API routes

- \`POST /auth/register\` — create a username and upload the encrypted identity envelope.
- \`POST /auth/login\` — verify the password and return the encrypted identity envelope.
- \`GET /users?q=username\` — search users and retrieve public keys.
- \`POST /chats\` — create or reopen a direct conversation by username.
- \`GET /chats\` — list the current user's conversations.
- \`GET /chats/:chatId/messages\` — retrieve recent encrypted messages.
- \`POST /chats/:chatId/messages\` — store an encrypted message envelope only.
- \`GET /api/health\` — check API and Firebase connectivity.
- \`GET /api/docs\` — compact API documentation.

## Current scope

This first rebuild implements account creation/sign-in, password-based identity-key protection, username lookup, one-to-one encrypted messaging, conversation history, secure local session storage, Firebase persistence, and a Render deployment path. Group chats, media attachments, push notifications, typing indicators, message editing/reactions, multi-device key rotation, and forward secrecy are not implemented in this first build.

## Security notes

Use HTTPS for every deployed API connection. Keep Firebase Realtime Database inaccessible to unauthenticated clients. The server retains encrypted message history without a retention policy. A successful Android CI build does not prove that Firebase credentials are configured or that the live service is healthy; verify the health endpoint and test with two separate accounts/devices before using it for real conversations.