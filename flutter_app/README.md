# CrazeChat Flutter client

Flutter client added alongside the existing Kotlin app. It follows the existing clean blue/white CrazeChat visual style and uses Firebase Realtime Database paths under `/users` and `/chats`.

## Setup

1. Install Flutter and Android SDK.
2. Run `flutter pub get` from this directory.
3. Run `dart pub global activate flutterfire_cli` then `flutterfire configure` and select the same Firebase project as the Android app. This generates `lib/firebase_options.dart` (not committed here because it is project-specific).
4. Verify Firebase Realtime Database URL/rules, then run `flutter run`.

## Implemented in this initial Flutter port

- Local profile register/login, exact-user-ID direct chat creation, realtime chat list and realtime messages, profile/user-ID copy, log out, and theme toggle.
- Existing `/users/{uid}` and `/chats/{chatId}/messages/{messageId}` data conventions are used where possible.

## Important compatibility/security status

This is an initial Flutter port, not yet a production replacement for the Kotlin client. The Kotlin app uses ECDH P-256 and AES-GCM with X.509/PKCS#8 encoded keys; Dart cryptographic interoperability, group chats, reactions/pinning/edit/delete, media, backup recovery, and security-rule migration still require implementation and cross-client tests. The current message screen sends text in the legacy `ciphertext` field and **does not provide end-to-end encryption**. Do not use it for sensitive messages or deploy permissive database rules. The old local-profile identity is not Firebase Authentication; production rules need a server-verifiable authenticated identity.
