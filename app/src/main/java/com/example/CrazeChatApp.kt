package com.example

import android.app.Application
import android.util.Log
import com.google.firebase.FirebaseApp

class CrazeChatApp : Application() {
    override fun onCreate() {
        super.onCreate()
        try {
            if (FirebaseApp.getApps(this).isEmpty()) {
                FirebaseApp.initializeApp(this)
            }

            val dbConfigured = try {
                val url = com.example.data.SecureConfig.getDatabaseUrl()
                url.isNotBlank() && !url.contains("REDACTED")
            } catch (e: Exception) {
                false
            }

            Log.i("CrazeChatApp", "Firebase configuration loaded: YES")
            Log.i("CrazeChatApp", "Database URL configured: ${if (dbConfigured) "YES" else "NO"}")
            Log.i("CrazeChatApp", "Firebase initialization: SUCCESS")

        } catch (e: Exception) {
            Log.e("CrazeChatApp", "Firebase initialization: FAILED (${e.message})")
        }
    }
}
