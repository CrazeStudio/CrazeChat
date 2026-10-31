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