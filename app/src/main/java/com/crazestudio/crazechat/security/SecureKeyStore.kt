package com.crazestudio.crazechat.security

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import android.util.Base64

/**
 * AES-256-GCM local encryption. The key is generated and retained by Android Keystore;
 * it is not serialized into app files or compiled into libcraze.so.
 */
object SecureKeyStore {
    private const val STORE = "AndroidKeyStore"
    private const val AES_ALIAS = "crazechat.local.aes.v1"
    private const val GCM_TAG_BITS = 128

    private fun key(): SecretKey {
        val store = KeyStore.getInstance(STORE).apply { load(null) }
        (store.getKey(AES_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, STORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                AES_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setKeySize(256)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return generator.generateKey()
    }

    /** Returns Base64(IV || ciphertext || authentication tag). */
    fun encrypt(plainText: ByteArray): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.doFinal(plainText)
        val packed = cipher.iv + encrypted
        return Base64.encodeToString(packed, Base64.NO_WRAP)
    }

    fun decrypt(encoded: String): ByteArray {
        val packed = Base64.decode(encoded, Base64.NO_WRAP)
        require(packed.size > 12 + 16) { "Encrypted payload is too short" }
        val iv = packed.copyOfRange(0, 12)
        val ciphertextAndTag = packed.copyOfRange(12, packed.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(GCM_TAG_BITS, iv))
        return cipher.doFinal(ciphertextAndTag)
    }
}
