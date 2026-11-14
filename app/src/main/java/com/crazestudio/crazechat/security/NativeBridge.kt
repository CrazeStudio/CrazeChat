package com.crazestudio.crazechat.security

/**
 * Small JNI boundary for the per-build obfuscated API configuration and
 * request canonicalization. The native library is not treated as a secret
 * store: all authorization still happens on the backend.
 */
object NativeBridge {
    init { System.loadLibrary("craze") }

    external fun nativeStatus(): String
    external fun nativeApiOrigin(): String
    external fun nativeBuildCanonicalRequest(
        method: String,
        path: String,
        timestamp: String,
        nonce: String,
        bodySha256Hex: String
    ): String?
}
