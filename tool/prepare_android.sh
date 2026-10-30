#!/usr/bin/env bash
set -euo pipefail
flutter create --platforms=android --project-name crazechat --org com.crazestudio .
python3 - <<'PY'
from pathlib import Path
p = Path("android/app/src/main/AndroidManifest.xml")
s = p.read_text()
if 'android:allowBackup=' in s:
    import re
    s = re.sub(r'android:allowBackup="[^"]*"', 'android:allowBackup="false"', s, count=1)
else:
    s = s.replace('<application', '<application\n        android:allowBackup="false"', 1)
if 'android.permission.INTERNET' not in s:
    s = s.replace('<application', '    <uses-permission android:name="android.permission.INTERNET" />\n    <application', 1)
p.write_text(s)
PY
echo "CrazeChat Android project is ready."