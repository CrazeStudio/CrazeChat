package com.crazestudio.crazechat.security

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey

/**
 * Per-install HMAC key held by Android Keystore. Server must independently enforce
 * authentication, expiry, replay prevention, authorization, and rate limits.
 */
object RequestSigner {
    private const val STORE = "AndroidKeyStore"
    private const val HMAC_ALIAS = "crazechat.request.hmac.v1"
    private val random = SecureRandom()

    data class SignedHeaders(
        val timestamp: String,
        val nonce: String,
        val bodySha256: String,
        val signature: String
    )

    private fun key(): SecretKey {
        val store = KeyStore.getInstance(STORE).apply { load(null) }
        (store.getKey(HMAC_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, STORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                HMAC_ALIAS,
                KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
            ).setDigests(KeyProperties.DIGEST_SHA256).build()
        )
        return generator.generateKey()
    }

    fun sign(method: String, path: String, body: ByteArray): SignedHeaders {
        val timestamp = (System.currentTimeMillis() / 1000L).toString()
        val nonceBytes = ByteArray(16).also(random::nextBytes)
        val nonce = Base64.encodeToString(nonceBytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        val bodyHash = MessageDigest.getInstance("SHA-256")
            .digest(body).joinToString("") { "%02x".format(it) }

        val canonical = requireNotNull(
            NativeBridge.nativeBuildCanonicalRequest(method, path, timestamp, nonce, bodyHash)
        ) { "Request rejected by native validation" }

        val mac = Mac.getInstance("HmacSHA256")
        mac.init(key())
        val signature = Base64.encodeToString(
            mac.doFinal(canonical.toByteArray(Charsets.UTF_8)),
            Base64.NO_WRAP
        )
        return SignedHeaders(timestamp, nonce, bodyHash, signature)
    }
}
