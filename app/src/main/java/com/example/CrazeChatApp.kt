package com.example

import android.app.Application
import android.util.Log

class CrazeChatApp : Application() {
    override fun onCreate() {
        super.onCreate()
        val apiConfigured = BuildConfig.CRAZECHAT_API_BASE_URL.startsWith("https://") &&
            BuildConfig.CRAZECHAT_API_ACCESS_KEY.isNotBlank()
        Log.i("CrazeChatApp", "CrazeChat API base configured: ${BuildConfig.CRAZECHAT_API_BASE_URL.startsWith("https://")}")
        Log.i("CrazeChatApp", "CrazeChat API access key configured: ${if (apiConfigured) "YES" else "NO"}")
        if (!apiConfigured) {
            Log.w("CrazeChatApp", "Set CRAZECHAT_API_ACCESS_KEY and rebuild the APK before using cloud features.")
        }
    }
}
