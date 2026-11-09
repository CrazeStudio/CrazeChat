#!/usr/bin/env bash
set -euo pipefail
flutter create --platforms=android --project-name crazechat --org com.crazestudio .
rm -f test/widget_test.dart

# google-services.json is checked into the repository and pinned by the
# Android CI workflow's SHA-256 verification step. It is public Firebase
# client configuration, not a service-account credential.
python3 - <<'PY'
from pathlib import Path
import json

firebase_file = Path("android/app/google-services.json")
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
const FirebaseOptions defaultFirebaseOptions = FirebaseOptions(
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
    raise SystemExit("Required android/app/google-services.json is missing.")
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
if 'android:usesCleartextTraffic=' in s:
    s = re.sub(
        r'android:usesCleartextTraffic="[^"]*"',
        'android:usesCleartextTraffic="false"',
        s,
        count=1,
    )
else:
    s = s.replace(
        '<application',
        '<application\n        android:usesCleartextTraffic="false"',
        1,
    )
if 'android:networkSecurityConfig=' in s:
    s = re.sub(
        r'android:networkSecurityConfig="[^"]*"',
        'android:networkSecurityConfig="@xml/network_security_config"',
        s,
        count=1,
    )
else:
    s = s.replace(
        '<application',
        '<application\n        android:networkSecurityConfig="@xml/network_security_config"',
        1,
    )
for permission in (
    "android.permission.INTERNET",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.VIBRATE",
):
    if permission not in s:
        s = s.replace(
            "<application",
            '    <uses-permission android:name="' + permission + '" />\n    <application',
            1,
        )
if "firebase_messaging_installation_id_enabled" not in s:
    metadata = """        <meta-data
            android:name="firebase_messaging_installation_id_enabled"
            android:value="true" />
"""
    s = s.replace("</application>", metadata + "    </application>", 1)
manifest.write_text(s)

network_config = Path("android/app/src/main/res/xml/network_security_config.xml")
network_config.parent.mkdir(parents=True, exist_ok=True)
network_config.write_text("""<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="false" />
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">localhost</domain>
        <domain includeSubdomains="false">127.0.0.1</domain>
        <domain includeSubdomains="false">10.0.2.2</domain>
    </domain-config>
</network-security-config>
""")

gradle = Path("android/app/build.gradle.kts")
if gradle.exists():
    source = gradle.read_text()
    source = source.replace("minSdk = flutter.minSdkVersion", "minSdk = 24")
    if 'id("com.google.gms.google-services")' not in source:
        if "plugins {" not in source:
            raise SystemExit("Android app Gradle file has no plugins block.")
        source = source.replace(
            "plugins {",
            'plugins {\n    id("com.google.gms.google-services")',
            1,
        )
    gradle.write_text(source)

settings = Path("android/settings.gradle.kts")
if settings.exists() and 'id("com.google.gms.google-services")' not in settings.read_text():
    source = settings.read_text()
    if "plugins {" not in source:
        raise SystemExit("Android settings Gradle file has no plugins block.")
    source = source.replace(
        "plugins {",
        'plugins {\n    id("com.google.gms.google-services") version "4.5.0" apply false',
        1,
    )
    settings.write_text(source)
PY

python3 - <<'PY'
from pathlib import Path

activity = Path("android/app/src/main/kotlin/com/crazestudio/crazechat/MainActivity.kt")
activity.parent.mkdir(parents=True, exist_ok=True)
activity.write_text("""package com.crazestudio.crazechat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val localSyncChannel = "com.crazestudio.crazechat/local_sync"
    private val securityChannel = "com.crazestudio.crazechat/security"
    private val folderRequestCode = 7821
    private var pendingFolderResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Block screenshots and the recent-apps preview from the very first
        // frame; the in-app setting can turn this off after startup.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        createCrazeChatNotificationChannels()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, securityChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, localSyncChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "selectFolder" -> {
                        if (pendingFolderResult != null) {
                            result.error("PICKER_BUSY", "A folder picker is already open.", null)
                        } else {
                            pendingFolderResult = result
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                addFlags(
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                                )
                            }
                            startActivityForResult(intent, folderRequestCode)
                        }
                    }
                    "readBackup" -> runLocalIo(result) {
                        val treeUri = Uri.parse(call.argument<String>("treeUri")
                            ?: throw IllegalArgumentException("Folder permission is missing."))
                        readBackupFile(treeUri)
                    }
                    "writeBackup" -> runLocalIo(result) {
                        val treeUri = Uri.parse(call.argument<String>("treeUri")
                            ?: throw IllegalArgumentException("Folder permission is missing."))
                        val contents = call.argument<String>("contents")
                            ?: throw IllegalArgumentException("Encrypted backup contents are missing.")
                        writeBackupFile(treeUri, contents)
                        null
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun runLocalIo(result: MethodChannel.Result, operation: () -> Any?) {
        Thread {
            try {
                val value = operation()
                runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("LOCAL_SYNC_FAILED", error.message ?: "Local folder operation failed.", null)
                }
            }
        }.start()
    }

    @Deprecated("Deprecated in Android, retained for FlutterActivity folder-picker result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != folderRequestCode) return
        val pending = pendingFolderResult
        pendingFolderResult = null
        if (resultCode != RESULT_OK || data?.data == null) {
            pending?.success(null)
            return
        }
        val uri = data.data!!
        try {
            val flags = data.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            contentResolver.takePersistableUriPermission(uri, flags)
            pending?.success(uri.toString())
        } catch (error: Exception) {
            pending?.error("FOLDER_PERMISSION_FAILED", error.message, null)
        }
    }

    private fun rootDocumentUri(treeUri: Uri): Uri {
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, rootId)
    }

    private fun findBackupDocument(treeUri: Uri): Uri? {
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, rootId)
        contentResolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME
            ),
            null,
            null,
            null
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID
            )
            val nameColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME
            )
            while (cursor.moveToNext()) {
                if (cursor.getString(nameColumn) == "crazechat-encrypted-backup.json") {
                    return DocumentsContract.buildDocumentUriUsingTree(
                        treeUri,
                        cursor.getString(idColumn)
                    )
                }
            }
        }
        return null
    }

    private fun readBackupFile(treeUri: Uri): String? {
        val document = findBackupDocument(treeUri) ?: return null
        return contentResolver.openInputStream(document)?.bufferedReader(Charsets.UTF_8)?.use {
            it.readText()
        } ?: throw IllegalStateException("Could not read the encrypted backup file.")
    }

    private fun writeBackupFile(treeUri: Uri, contents: String) {
        val document = findBackupDocument(treeUri) ?: DocumentsContract.createDocument(
            contentResolver,
            rootDocumentUri(treeUri),
            "application/json",
            "crazechat-encrypted-backup.json"
        ) ?: throw IllegalStateException("Could not create the encrypted backup file.")
        contentResolver.openOutputStream(document, "wt")?.bufferedWriter(Charsets.UTF_8)?.use {
            it.write(contents)
        } ?: throw IllegalStateException("Could not write the encrypted backup file.")
    }

    private fun createCrazeChatNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannelGroup(
            NotificationChannelGroup(messageGroupId, "Messages")
        )
        createMessageChannel(manager, "crazechat_messages_default", true, true)
        createMessageChannel(manager, "crazechat_messages_sound_only", true, false)
        createMessageChannel(manager, "crazechat_messages_vibrate_only", false, true)
        createMessageChannel(manager, "crazechat_messages_silent", false, false)
    }

    private val messageGroupId = "crazechat_messages_group"

    private fun createMessageChannel(
        manager: NotificationManager,
        id: String,
        soundEnabled: Boolean,
        vibrationEnabled: Boolean
    ) {
        val channel = NotificationChannel(
            id,
            "CrazeChat messages",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "New encrypted CrazeChat messages"
            group = messageGroupId
            setShowBadge(true)
            enableLights(true)
            lightColor = 0xFF087E65.toInt()
            // Message text is never in the push payload, and the lock screen
            // should not reveal who is writing either.
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            enableVibration(vibrationEnabled)
            if (soundEnabled) {
                val attributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .build()
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                    attributes
                )
            } else {
                setSound(null, null)
            }
            if (vibrationEnabled) {
                vibrationPattern = longArrayOf(0, 180, 100, 180)
            }
        }
        manager.createNotificationChannel(channel)
    }
}
""")

manifest = Path("android/app/src/main/AndroidManifest.xml")
source = manifest.read_text()
default_channel = """        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="crazechat_messages_default" />
"""
if "com.google.firebase.messaging.default_notification_channel_id" not in source:
    source = source.replace("</application>", default_channel + "    </application>", 1)
# A dedicated single-colour status-bar icon and brand accent colour. Without
# these, Android shows the full-colour launcher icon as a grey/white square.
status_icon = """        <meta-data
            android:name="com.google.firebase.messaging.default_notification_icon"
            android:resource="@drawable/ic_stat_crazechat" />
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_color"
            android:resource="@color/crazechat_icon_background" />
"""
if "com.google.firebase.messaging.default_notification_icon" not in source:
    source = source.replace("</application>", status_icon + "    </application>", 1)
manifest.write_text(source)
PY

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

# Status-bar notification icon: white shape on transparent, lightning bolt cut out.
status_bar = """<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#FFFFFFFF"
        android:fillType="evenOdd"
        android:pathData="M54,16 C34,16 18,30 18,49 C18,60 23,70 32,77 L29,91 L46,83 C49,84 52,84 55,84 C75,84 90,69 90,50 C90,31 74,16 54,16 Z M58,28 L40,55 L53,55 L47,73 L70,46 L56,46 Z" />
</vector>
"""
(res / "drawable" / "ic_stat_crazechat.xml").write_text(status_bar)

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

# Native library that stores the API origin and shared key XOR-masked.
# The values default to empty here; CI overwrites config.h with real ones
# (tool/gen_native_config.py) before a release build.
python3 - <<'PY'
from pathlib import Path

cpp = Path("android/app/src/main/cpp")
cpp.mkdir(parents=True, exist_ok=True)

(cpp / "CMakeLists.txt").write_text("""cmake_minimum_required(VERSION 3.13)
project(crazecfg C)
add_library(crazecfg SHARED crazecfg.c)
target_link_options(crazecfg PRIVATE -Wl,-z,max-page-size=16384)
""")

(cpp / "crazecfg.c").write_text("""#include <stddef.h>
#include "config.h"

#define CC_EXPORT __attribute__((visibility("default")))

static char url_buf[CC_URL_LEN + 1];
static char key_buf[CC_KEY_LEN + 1];
static int decoded = 0;

static void decode_all(void) {
    if (decoded) return;
    for (size_t i = 0; i < CC_URL_LEN; i++) {
        url_buf[i] = (char)(cc_url_enc[i] ^ cc_mask[i % CC_MASK_LEN]);
    }
    url_buf[CC_URL_LEN] = 0;
    for (size_t i = 0; i < CC_KEY_LEN; i++) {
        key_buf[i] = (char)(cc_key_enc[i] ^ cc_mask[(i + 7) % CC_MASK_LEN]);
    }
    key_buf[CC_KEY_LEN] = 0;
    decoded = 1;
}

CC_EXPORT const char *cc_url(void) {
    decode_all();
    return url_buf;
}

CC_EXPORT const char *cc_key(void) {
    decode_all();
    return key_buf;
}
""")

config = cpp / "config.h"
if not config.exists():
    config.write_text("""/* Default empty config: the app falls back to --dart-define values. */
#define CC_MASK_LEN 16
#define CC_URL_LEN 0
#define CC_KEY_LEN 0
static const unsigned char cc_mask[CC_MASK_LEN] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};
static const unsigned char cc_url_enc[CC_URL_LEN + 1] = {0};
static const unsigned char cc_key_enc[CC_KEY_LEN + 1] = {0};
""")

gradle = Path("android/app/build.gradle.kts")
if gradle.exists():
    source = gradle.read_text()
    marker = "    defaultConfig {"
    if "externalNativeBuild" not in source and marker in source:
        block = '''    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    signingConfigs {
        create("release") {
            val keystorePath = System.getenv("CRAZECHAT_KEYSTORE_PATH")
            if (keystorePath != null) {
                storeFile = file(keystorePath)
                storePassword = System.getenv("CRAZECHAT_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("CRAZECHAT_KEY_ALIAS")
                keyPassword = System.getenv("CRAZECHAT_KEY_PASSWORD")
            }
        }
    }

'''
        source = source.replace(marker, block + marker, 1)
    else:
        print("WARNING: could not add native build block to build.gradle.kts")
    needle = 'signingConfig = signingConfigs.getByName("debug")'
    if needle in source:
        source = source.replace(
            needle,
            'signingConfig = if (System.getenv("CRAZECHAT_KEYSTORE_PATH") != null) signingConfigs.getByName("release") else signingConfigs.getByName("debug")',
            1,
        )
    else:
        print("WARNING: release signing line not found; keeping default signing")
    gradle.write_text(source)
PY

echo "CrazeChat Android project is ready."
