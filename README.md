# CrazeChat

Flutter messaging app with device-side encrypted direct messages. The app uses **CrazeStudio-Web** as its database API; it does not deploy a separate CrazeChat authentication server.

## Backend configuration

Deploy `CrazeStudio/CrazeStudio-Web` using its documented Vercel or Cloudflare Worker setup. Configure these server-side values in that deployment:

- `ACCESS_KEY`
- `FIREBASE_URL`
- `FIREBASE_SDK`

The Android app uses the existing CrazeStudio-Web database routes:

- `GET /db/:path*`
- `PUT /db/:path*`
- `PATCH /db/:path*`
- `DELETE /db/:path*`

No `/auth/*` or `/chats/*` backend endpoints are added. The Flutter API adapter translates the app's account and chat actions into database-gateway operations.

## Firebase data layout

CrazeChat stores application data directly at the Firebase Realtime Database root:

```text
users/
  {uid}/
    uid
    username
    usernameLower
    passwordHash
    publicKey
    identityEnvelope
    createdAt

usernames/
  {usernameLower}/
    uid

chats/
  {chatId}/
    participants/
    createdAt
    updatedAt
    lastMessageAt

userChats/
  {uid}/
    {chatId}: true

Massages/
  {chatId}/
    {messageId}/
      senderId
      format
      ciphertext
      nonce
      mac
      createdAt
```

The `Massages` path is intentionally capitalized and spelled exactly as shown. Message payloads are encrypted on-device; the database stores the ciphertext envelope. A user can long-press one of their own sent messages and confirm deletion. CrazeChat then sends `DELETE /db/Massages/{chatId}/{messageId}`, removing the server record rather than only hiding it locally.

Passwords are processed on-device with PBKDF2-HMAC-SHA256 (310,000 iterations) and a random salt before the password hash is stored. The password itself is not written to the database. The private identity key remains inside the password-encrypted identity envelope.

## Android configuration

Set GitHub Actions repository secrets:

- `BURL`: the CrazeStudio-Web deployment origin only, such as `https://your-project.vercel.app` (do not append `/db`).
- `KEY`: the same value configured as CrazeStudio-Web's server-side `ACCESS_KEY`.

Build locally:

```bash
bash tool/prepare_android.sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define=BURL=https://YOUR-CRAZESTUDIO-WEB-ORIGIN --dart-define=KEY=YOUR_ACCESS_KEY
```

GitHub Actions builds the release APK when both repository secrets are present.

## Security limitation

CrazeStudio-Web's existing database gateway authorizes requests with one shared `ACCESS_KEY`. Because the Android build contains that key, a determined user can extract it and call the database routes directly. Client-side checks in the app are not a substitute for server-enforced per-user authorization. This integration is suitable for controlled testing, not a public production messenger with private user data, until the backend adds a secure per-user authorization mechanism. Keep Firebase direct-client rules locked down and never publish the service-account JSON.

The current chat encryption implementation uses X25519, HKDF-SHA256, and AES-256-GCM. It has not been independently audited and does not provide forward secrecy or out-of-band public-key verification.


## Fast message synchronization

CrazeChat initially loads the latest 50 messages and then requests only messages at or after the last received `createdAt` timestamp. The gateway translates the bounded sync request into a Firebase Realtime Database query. This avoids downloading and decrypting the entire conversation every few seconds.

**Required Firebase Realtime Database index:** merge the following index into your existing database rules. Do not replace your existing security rules with this snippet.

```json
{
  "rules": {
    "Massages": {
      "$chatId": {
        ".indexOn": ["createdAt"]
      }
    }
  }
}
```

The app reuses its HTTP client, fetches chat records concurrently, decrypts only newly received messages, and adds sent messages locally after the server confirms the write. The two-account switcher stores at most two account profiles in Android secure storage; each account's private identity key remains encrypted by its own password.
