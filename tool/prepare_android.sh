#!/usr/bin/env bash
set -euo pipefail
flutter create --platforms=android --project-name crazechat --org com.crazestudio .
rm -f test/widget_test.dart

# Firebase configuration is optional for development, but required for
# background push notifications. CI can supply the same file as a base64
# GitHub Actions secret named FIREBASE_ANDROID_CONFIG_B64.
python3 - <<'PY'
from pathlib import Path
import base64
import json
import os

firebase_file = Path("android/app/google-services.json")
encoded = os.environ.get("FIREBASE_ANDROID_CONFIG_B64", "").strip()
if encoded:
    try:
        firebase_file.parent.mkdir(parents=True, exist_ok=True)
        firebase_file.write_bytes(base64.b64decode(encoded, validate=True))
    except Exception as exc:
        raise SystemExit(f"FIREBASE_ANDROID_CONFIG_B64 is not valid base64: {exc}")

options_file = Path("lib/src/firebase_options.dart")
if firebase_file.exists():
    try:
        config = json.loads(firebase_file.read_text())
        project = config["project_info"]
        clients = config["client"]
        package_name = "com.crazestudio.crazechat"
        client = next(
            item for item in clients
            if item.get("client_info", {}).get("android_client_info", {}).get("package_name") == package_name
        )
        app_id = client["client_info"]["mobilesdk_app_id"]
        api_key = client["api_key"][0]["current_key"]
        sender_id = project["project_number"]
        project_id = project["project_id"]
        if not all((app_id, api_key, sender_id, project_id)):
            raise ValueError("The selected Firebase Android app is missing required fields.")
        source = f'''import 'package:firebase_core/firebase_core.dart';

// Generated from android/app/google-services.json. Do not edit by hand.
const bool firebasePushConfigured = true;
const FirebaseOptions? defaultFirebaseOptions = FirebaseOptions(
  apiKey: {json.dumps(api_key)},
  appId: {json.dumps(app_id)},
  messagingSenderId: {json.dumps(sender_id)},
  projectId: {json.dumps(project_id)},
);
'''
        options_file.write_text(source)
        print("Firebase Android app configuration found: background push is enabled.")
    except Exception as exc:
        raise SystemExit(f"Could not generate Firebase Android options: {exc}")
else:
    options_file.write_text("""import 'package:firebase_core/firebase_core.dart';

// Safe fallback used when no Android Firebase app has been configured.
const bool firebasePushConfigured = false;
const FirebaseOptions? defaultFirebaseOptions = null;
""")
    print("No google-services.json supplied: push notifications will remain disabled.")
PY
python3 - <<'PY'
from pathlib import Path
import re

manifest = Path("android/app/src/main/AndroidManifest.xml")
s = manifest.read_text()
if 'android:allowBackup=' in s:
    s = re.sub(r'android:allowBackup="[^"]*"', 'android:allowBackup="false"', s, count=1)
else:
    s = s.replace('<application', '<application\n        android:allowBackup="false"', 1)
for permission in (
    "android.permission.INTERNET",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.VIBRATE",
):
    if permission not in s:
        s = s.replace(
            "<application",
            f'    <uses-permission android:name="{permission}" />\\n    <application',
            1,
        )
manifest.write_text(s)

gradle = Path("android/app/build.gradle.kts")
if gradle.exists():
    source = gradle.read_text()
    source = source.replace("minSdk = flutter.minSdkVersion", "minSdk = 23")
    gradle.write_text(source)
PY
# Install CrazeChat's native launcher artwork after Flutter generates the Android project.
python3 - <<'PY'
from pathlib import Path

res = Path("android/app/src/main/res")
(res / "drawable").mkdir(parents=True, exist_ok=True)
(res / "mipmap-anydpi-v26").mkdir(parents=True, exist_ok=True)
(res / "values").mkdir(parents=True, exist_ok=True)

foreground = """<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M54,16 C34,16 18,30 18,49 C18,60 23,70 32,77 L29,91 L46,83 C49,84 52,84 55,84 C75,84 90,69 90,50 C90,31 74,16 54,16 Z" />
    <path
        android:fillColor="#087E65"
        android:pathData="M58,28 L40,55 L53,55 L47,73 L70,46 L56,46 Z" />
</vector>
"""
(res / "drawable" / "ic_crazechat_foreground.xml").write_text(foreground)

adaptive = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/crazechat_icon_background" />
    <foreground android:drawable="@drawable/ic_crazechat_foreground" />
</adaptive-icon>
"""
(res / "mipmap-anydpi-v26" / "ic_launcher.xml").write_text(adaptive)
(res / "values" / "crazechat_colors.xml").write_text("""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="crazechat_icon_background">#087E65</color>
</resources>
""")

# Vector fallback keeps the icon branded on Android versions before adaptive icons.
legacy = """<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="48dp"
    android:height="48dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:fillColor="#087E65" android:pathData="M0,0 H108 V108 H0 Z" />
    <path android:fillColor="#FFFFFFFF"
        android:pathData="M54,16 C34,16 18,30 18,49 C18,60 23,70 32,77 L29,91 L46,83 C49,84 52,84 55,84 C75,84 90,69 90,50 C90,31 74,16 54,16 Z" />
    <path android:fillColor="#087E65" android:pathData="M58,28 L40,55 L53,55 L47,73 L70,46 L56,46 Z" />
</vector>
"""
(res / "drawable" / "ic_crazechat.xml").write_text(legacy)

manifest = Path("android/app/src/main/AndroidManifest.xml")
s = manifest.read_text()
s = s.replace('android:icon="@mipmap/ic_launcher"', 'android:icon="@drawable/ic_crazechat"')
s = s.replace('android:label="crazechat"', 'android:label="CrazeChat"')
manifest.write_text(s)
PY

echo "CrazeChat Android project is ready."