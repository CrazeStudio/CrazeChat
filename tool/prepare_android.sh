#!/usr/bin/env bash
set -euo pipefail
flutter create --platforms=android --project-name crazechat --org com.crazestudio .
rm -f test/widget_test.dart
python3 - <<'PY'
from pathlib import Path
import re

manifest = Path("android/app/src/main/AndroidManifest.xml")
s = manifest.read_text()
if 'android:allowBackup=' in s:
    s = re.sub(r'android:allowBackup="[^"]*"', 'android:allowBackup="false"', s, count=1)
else:
    s = s.replace('<application', '<application\n        android:allowBackup="false"', 1)
if 'android.permission.INTERNET' not in s:
    s = s.replace('<application', '    <uses-permission android:name="android.permission.INTERNET" />\n    <application', 1)
manifest.write_text(s)

gradle = Path("android/app/build.gradle.kts")
if gradle.exists():
    source = gradle.read_text()
    source = source.replace("minSdk = flutter.minSdkVersion", "minSdk = 23")
    gradle.write_text(source)
PY
echo "CrazeChat Android project is ready."