package com.example.data

/**
 * Secure configuration utility to hide sensitive strings from simple decompilers using JNI.
 */
object SecureConfig {
    init {
        System.loadLibrary("crazechat")
    }

    /**
     * Native method that returns the Firebase database URL.
     */
    external fun getNativeUrl(): String

    /**
     * Reconstructs the database URL at runtime using JNI.
     */
    fun getDatabaseUrl(): String {
        return try {
            getNativeUrl()
        } catch (e: Exception) {
            // No hardcoded fallback to prevent leakage in decompile
            ""
        }
    }
}
