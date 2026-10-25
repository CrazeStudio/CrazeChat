package com.example

import android.app.Application
import android.util.Log

class CrazeChatApp : Application() {
    override fun onCreate() {
        super.onCreate()
        val baseConfigured = BuildConfig.CRAZECHAT_API_BASE_URL.startsWith("https://")
        Log.i("CrazeChatApp", "CrazeChat API base configured: $baseConfigured")
        if (!baseConfigured) {
            Log.w("CrazeChatApp", "Configure a valid HTTPS CrazeChat API base URL before using cloud features.")
        }
    }
}
