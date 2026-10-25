package com.example.data

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Small Android-Keystore-backed at-rest protection for session tokens and private-key strings.
 * The AES key never leaves Android Keystore. This is not a substitute for message end-to-end
 * encryption; it protects app-private storage if the preferences file is copied.
 */
object SecureVault {
    private const val KEY_ALIAS = "com.crazestudio.crazechat.local.v1"
    private const val PREFIX = "enc:"
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128

    @Synchronized
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return generator.generateKey()
    }

    @Synchronized
    fun encrypt(plainText: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.doFinal(plainText.toByteArray(StandardCharsets.UTF_8))
        val packed = cipher.iv + encrypted
        return PREFIX + Base64.encodeToString(packed, Base64.NO_WRAP)
    }

    @Synchronized
    fun decrypt(stored: String?): String? {
        if (stored == null) return null
        // Existing installs used plaintext preferences. This compatibility branch permits an
        // existing session to open once; all newly saved values are encrypted.
        if (!stored.startsWith(PREFIX)) return stored
        return try {
            val packed = Base64.decode(stored.removePrefix(PREFIX), Base64.NO_WRAP)
            if (packed.size <= IV_BYTES) return null
            val iv = packed.copyOfRange(0, IV_BYTES)
            val encrypted = packed.copyOfRange(IV_BYTES, packed.size)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, iv))
            String(cipher.doFinal(encrypted), StandardCharsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }
}
