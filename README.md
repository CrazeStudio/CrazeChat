# CrazeChat

CrazeChat's primary Android APK is built from the Kotlin/Jetpack Compose project in `app/`. It stores messages locally in Room and now calls the CrazeChat HTTP API for cloud users, chats, messages, reactions, groups, and profile data.

## API configuration

The Android build uses:

- API base URL: `https://crazechat-api.vercel.app`
- API verification password: `CRAZECHAT_API_ACCESS_KEY` (must match the Vercel `ACCESS_KEY` value)

For a local build, copy `.env.example` to `.env` and set `CRAZECHAT_API_ACCESS_KEY`. For GitHub Actions builds, add repository secret `CRAZECHAT_API_ACCESS_KEY` under **Settings → Secrets and variables → Actions**. The APK build workflow deliberately fails if this secret is missing so it does not publish a non-working build.

The app sends the key to `POST /verify`, caches the returned short-lived token in memory, and uses `X-API-Token` for API requests. The shared key is compiled into the APK, so it can be extracted by a determined user; it is suitable only as a private-app gate, not as strong per-user authentication.

## Firebase database requirement

The backend uses Firebase Realtime Database REST requests with `DATABASE_URL`. It does not use Firebase Admin credentials. Therefore Firebase Security Rules must allow the backend's unauthenticated REST requests. If rules require `auth != null` or deny all access, database endpoints return `FIREBASE_PERMISSION_DENIED`. Making the data publicly readable/writable lets anyone bypass the API key and access the database directly; do not use that arrangement for private chats or backups. For a private production deployment, use server-side Firebase authentication instead.

## Flutter prototype

The repository also contains Flutter prototype sources. The APK workflow builds the native Android `app/` module.
