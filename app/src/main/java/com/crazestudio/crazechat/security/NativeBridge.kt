package com.crazestudio.crazechat.security

/**
 * Small JNI boundary for the non-secret API-origin configuration. The
 * native library is not treated as a secret store; authorization happens
 * entirely on the backend.
 */
object NativeBridge {
    init { System.loadLibrary("craze") }

    external fun nativeStatus(): String
    external fun nativeApiOrigin(): String
}
