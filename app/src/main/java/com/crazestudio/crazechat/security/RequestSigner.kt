package com.crazestudio.crazechat.security

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/**
 * Per-install ECDSA P-256 private key held by Android Keystore.
 * Register the returned public key with the backend during an authenticated enrollment flow.
 */
object RequestSigner {
    private const val STORE = "AndroidKeyStore"
    private const val KEY_ALIAS = "crazechat.request.ecdsa.v1"
    private val random = SecureRandom()

    data class SignedHeaders(
        val timestamp: String,
        val nonce: String,
        val bodySha256: String,
        val publicKey: String,
        val signature: String
    )

    private fun keyPair(): KeyPair {
        val store = KeyStore.getInstance(STORE).apply { load(null) }
        val privateKey = store.getKey(KEY_ALIAS, null) as? java.security.PrivateKey
        val certificate = store.getCertificate(KEY_ALIAS)
        if (privateKey != null && certificate != null) {
            return KeyPair(certificate.publicKey, privateKey)
        }

        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, STORE)
        generator.initialize(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_SIGN)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .build()
        )
        return generator.generateKeyPair()
    }

    fun sign(method: String, path: String, body: ByteArray): SignedHeaders {
        val timestamp = (System.currentTimeMillis() / 1000L).toString()
        val nonceBytes = ByteArray(16).also(random::nextBytes)
        val nonce = Base64.encodeToString(
            nonceBytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING
        )
        val bodyHash = MessageDigest.getInstance("SHA-256")
            .digest(body).joinToString("") { "%02x".format(it) }

        val canonical = requireNotNull(
            NativeBridge.nativeBuildCanonicalRequest(method, path, timestamp, nonce, bodyHash)
        ) { "Request rejected by native validation" }

        val pair = keyPair()
        val signer = Signature.getInstance("SHA256withECDSA")
        signer.initSign(pair.private, random)
        signer.update(canonical.toByteArray(Charsets.UTF_8))
        val publicKey = Base64.encodeToString(pair.public.encoded, Base64.NO_WRAP)
        val signature = Base64.encodeToString(signer.sign(), Base64.NO_WRAP)
        return SignedHeaders(timestamp, nonce, bodyHash, publicKey, signature)
    }
}
