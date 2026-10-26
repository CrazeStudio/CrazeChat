# CrazeChat — Rebuild Reference

CrazeChat is being restarted from a clean repository. This README is intentionally retained as the product, design, and architecture reference for the next implementation.

## Design direction

- Keep the CrazeChat identity and the existing app’s purpose: a polished Android-first private messaging app.
- Use a premium, modern, carefully spaced interface; rounded surfaces and message bubbles; clear visual hierarchy; readable typography; consistent icons; and responsive layouts for different Android screen sizes and orientations.
- Preserve the established CrazeStudio design sensibility: futuristic but practical, clean surfaces, restrained silver/neutral tones with orange as an accent, and system-following light/dark themes where appropriate.
- Keep chat UI focused on conversations: clear chat list, recognizable avatars, readable timestamps and delivery/read states, straightforward message composition, and accessible actions for replies, reactions, edits, deletes, and pins.
- Avoid an unrequested redesign that discards the app’s established visual identity. Before rebuilding, inspect any screenshots or surviving app build available to the owner and use them as the visual source of truth. This text is a design brief, not a pixel-perfect screenshot specification.

## Product scope to restore

- Android messaging client.
- Direct and group conversations.
- Account registration, login, migration, password changes, logout/session revocation, and account deletion.
- Message replies, reactions, edits/deletions, pins, read receipts, and presence.
- Profile and public-key discovery.
- Client-side message encryption and secure key handling.
- Password-encrypted profile/key recovery backups.
- Expiring server-side message ciphertext and scheduled cleanup.

## Architecture notes

The previous implementation used Kotlin, Jetpack Compose, Room, Android Keystore-backed AES-GCM storage, and a Vercel-hosted HTTP API. The companion API repository was `CrazeStudio/CrazeStudio-Web`; its API used Firebase Realtime Database through Firebase Admin SDK.

Previous API environment variables (server-side only):
- `DATABASE_URL`
- `FIREBASE_SERVICE_ACCOUNT_JSON`
- `TOKEN_SIGNING_SECRET`
- `CRON_SECRET`

The previous Android API base URL was configurable using `CRAZECHAT_API_BASE_URL`; its default was `https://crazechat-api.vercel.app`.

Previous account routes included `POST /auth/register`, `POST /api/user/login` (with `POST /auth/login` as a backward-compatible alias), and `POST /auth/migrate`. Login credentials belong in an HTTPS JSON request body, never URL path segments. Do not add a shared database password or embed server secrets in the APK.

## Security and recovery requirements

- Keep Firebase rules closed to unauthenticated clients; access the database through server-side Firebase Admin credentials.
- Never commit service-account JSON, tokens, passwords, private keys, or production environment values.
- Protect local private keys, tokens, and message data with Android Keystore-backed encryption.
- Encrypt recovery backups with a password-based scheme using an appropriate work factor.
- Do not claim end-to-end encryption guarantees beyond what the implementation actually provides. A future rebuild must review key rotation, historical-message compatibility, and forward-secrecy limitations explicitly.
- Message expiry must be enforced server-side with reliable cleanup, not merely hidden in the UI.
- Do not clear existing app data on a device that may contain the only recoverable private key.

## Rebuild checklist

1. Recreate the Android app and backend integration from a clean, documented structure.
2. Rebuild the UI against the design direction above and any original screenshots still available.
3. Add tests for registration, login, account migration, backup restore, refresh, logout, password changes, account deletion, direct/group messaging, membership changes, key rotation, and expiry cleanup.
4. Verify the Android build in CI and deploy/test the Vercel API independently before calling either one complete.
5. Keep this README as the persistent product and design reference; update it when architecture or design decisions change.

## Reset status

The source tree is intentionally being reduced to this README so the implementation can be rebuilt from a clean starting point. The repository itself is retained.
