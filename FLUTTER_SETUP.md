# Flutter setup

The Flutter entry point is `lib/main.dart` and the dependency manifest is `pubspec.yaml`.

## Generate the Android runner

From the repository root, install Flutter and run:

```sh
flutter create --platforms=android --project-name xqnzmw --org com.aistudio.crazechat --overwrite .
```

Because that command regenerates platform boilerplate, restore the app source and dependency manifest afterward:

```sh
git checkout -- pubspec.yaml lib/main.dart
mkdir -p android/app
cp config/google-services.json android/app/google-services.json
flutter pub get
flutter run
```

The Android package must remain `com.aistudio.crazechat.xqnzmw` to match the Firebase configuration. If Flutter generates a different package, update `android/app/build.gradle` and the Kotlin MainActivity package to match.

## APK

```sh
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`.

## Security

This initial Flutter port currently sends plain text and is not end-to-end encrypted. Do not use for sensitive messages until the Kotlin cryptography is ported and tested against Flutter, and Firebase access is bound to authenticated identities.
