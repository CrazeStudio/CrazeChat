# CrazeChat — Android Gradle + Native Security Foundation

This branch starts a new Android Gradle project. The previous Flutter application remains preserved on `backup/flutter-app`.

## Stack
- Android Gradle Plugin 8.7.3, Gradle 8.9, Kotlin 2.0.21, JDK 17
- Android NDK / CMake C++20 shared library: `libcraze.so`
- JNI bridge for native request validation and canonicalization
- Android Keystore-backed AES-256-GCM local encryption
- Per-install Android Keystore HMAC-SHA256 request-signing key
- R8 release shrinking, native symbol visibility restrictions, cleartext traffic disabled

## Build
Use JDK 17, Android SDK Platform 35, NDK 27.0.12077973 (or a compatible installed NDK), and CMake 3.22.1.

```bash
gradle :app:assembleDebug
gradle :app:assembleRelease
```

## Security boundaries
- No reusable API key, master secret, or backend private key belongs in the APK or native library.
- The native library is a reverse-engineering speed bump, not a secrecy boundary.
- AES-GCM and HMAC keys are generated per installation and held by Android Keystore.
- HMAC request signing is only useful when the backend verifies signatures, timestamps, nonce uniqueness, body hashes, and user authorization. The backend must also rate-limit and revoke compromised installations.
- A client-side HMAC key is extractable in principle on a compromised/rooted device or through runtime instrumentation. Do not use it as the only user-authentication factor.
- Device backup is disabled. Encrypted records should still be treated as sensitive.

## Important
This is a security foundation and starter Android app, not a complete chat product or a completed server integration. No backend endpoint or server-side signing verification has been assumed.
