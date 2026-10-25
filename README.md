# CrazeChat

CrazeChat is an Android messaging application built with Kotlin, Jetpack Compose, Room, and a Vercel-hosted HTTP API. Its feature set includes direct and group conversations, reactions, replies, message edits/deletions, pins, read receipts, presence, profile/key discovery, local profiles, and encrypted profile recovery backups.

## Android API configuration

The application embeds only the public HTTPS API base URL. It does **not** require a shared API password in the APK, Gradle properties, or GitHub Actions secrets.

For a local build, optionally set `CRAZECHAT_API_BASE_URL` to your deployed API URL. The default in `app/build.gradle.kts` is `https://crazechat-api.vercel.app`. GitHub Actions uses the same public endpoint unless the workflow is changed.

The app authenticates individual accounts using `POST /auth/register`, `POST /auth/login`, and the legacy-account migration endpoint `POST /auth/migrate`. Access tokens expire after one hour; rotating refresh tokens are stored encrypted with Android Keystore-backed AES-GCM. The backend supports password changes, logout/session revocation, and confirmed cloud-account deletion.

## Backend deployment requirements

The API source is in the companion repository [CrazeStudio-Web](https://github.com/CrazeStudio/CrazeStudio-Web), file `api/index.js`. Before a private deployment, configure these Vercel environment variables:

- `DATABASE_URL`: the Firebase Realtime Database URL.
- `FIREBASE_SERVICE_ACCOUNT_JSON`: the service-account JSON, stored only as a server-side secret.
- `TOKEN_SIGNING_SECRET`: a strong randomly generated token-signing secret, used only on the server.
- `CRON_SECRET`: a separate random secret for expired-message cleanup.

Do not commit service-account JSON, tokens, or passwords. Do not put any of these values in `public/`, Android `BuildConfig`, or the APK. Keep Firebase Realtime Database rules closed to unauthenticated clients; the backend uses Firebase Admin SDK server credentials.

The old shared-password `POST /verify` flow has been retired by this API version. If an older deployed API is still live, it must be redeployed before this Android source can sign in.

## Account migration and backup safety

Accounts created by older app versions may migrate if their old encrypted profile backup is available and can be verified with the original password. Migration preserves the prior user ID. If the old backup is missing, invalid, or not decryptable, keep the original device and keys; do not uninstall or clear the old app data until recovery is resolved.

The app retains local profile/message data during sign-in failures where local verification can be completed. Local private keys, message text, chat-list preview text, access tokens, refresh tokens, and stored group keys are now protected using AES-GCM with an Android Keystore key. The migration logic attempts to encrypt legacy local plaintext values when the app opens.

## Cryptography and privacy limits

Direct messages use client-side ECDH-derived AES-GCM encryption. New group messages use random group secrets, versioned AES-GCM payloads, and member-specific encrypted key envelopes. When a member is added, the group owner is expected to rotate to a new key version; older members retain previous keys locally while new members receive only the new key version. Historical group messages may have used an older key derived from a constant embedded in prior APKs; those legacy messages must not be treated as confidential from a person who reverse-engineers that old APK.

The server retains ciphertext until expiry/cleanup and processes message metadata such as timestamps, chat membership, sender IDs, and delivery state. This code does not yet implement a Signal-style ratchet or forward secrecy. Profile backups remain password-encrypted, but anyone with a weak password may be exposed to offline guessing if they obtain a backup. Use a unique, strong password.

Account deletion removes the account credentials and account-owned profile/key/backup/presence/session records. Shared conversation copies may remain for other participants; deletion is not a promise that every recipient's device will erase previously downloaded content.

## Build and validation

The Android APK workflow lives at `.github/workflows/export-apk.yml`. Check GitHub Actions for the current build status. Source changes alone do not mean that an APK compiled or the Vercel service is deployed. Test registration, login, migration, refresh, logout, password change, account deletion, group-key rotation, and messaging against a separate test Firebase project before using production accounts.

