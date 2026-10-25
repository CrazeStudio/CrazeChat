package com.example

import android.app.Application
import android.util.Log

class CrazeChatApp : Application() {
    override fun onCreate() {
        super.onCreate()
        val baseConfigured = BuildConfig.CRAZECHAT_API_BASE_URL.startsWith("https://")
        val keyConfigured = BuildConfig.CRAZECHAT_API_ACCESS_KEY.isNotBlank()
        Log.i("CrazeChatApp", "CrazeChat API base configured: $baseConfigured")
        val keyStatus = if (keyConfigured) "YES" else "NO"
        Log.i("CrazeChatApp", "CrazeChat API access key configured: $keyStatus")
        if (!baseConfigured || !keyConfigured) {
            Log.w("CrazeChatApp", "Set CRAZECHAT_API_ACCESS_KEY and rebuild the APK before using cloud features.")
        }
    }
}
