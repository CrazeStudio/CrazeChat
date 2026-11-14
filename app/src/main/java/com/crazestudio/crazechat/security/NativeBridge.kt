package com.crazestudio.crazechat.security

/**
 * JNI boundary for logic that benefits from native implementation.
 * Never put API tokens, private keys, or other reusable secrets in this library.
 */
object NativeBridge {
    init { System.loadLibrary("craze") }

    external fun nativeStatus(): String
    external fun nativeBuildCanonicalRequest(
        method: String,
        path: String,
        timestamp: String,
        nonce: String,
        bodySha256Hex: String
    ): String?
}
