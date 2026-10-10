package com.example.data

import android.util.Base64
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.PublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec
import java.security.MessageDigest
import java.security.SecureRandom

data class KeyPairData(
    val publicKeyBase64: String,
    val privateKeyBase64: String
)

data class EncryptedPayload(
    val ciphertext: String,
    val nonce: String
)

object CryptoManager {

    // Simple SHA-256 for basic non-cryptographic matching
    fun hashPassword(password: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val salted = "CrazeChat_Salt_2026_$password"
        val bytes = digest.digest(salted.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }

    // High-security PBKDF2 Key Derivation to protect profile backups from brute-force/GPU attacks
    private fun deriveKeyPBKDF2(password: String, username: String): SecretKeySpec {
        val salt = "CrazeChat_PBKDF2_Salt_2026_${username.lowercase()}".toByteArray(Charsets.UTF_8)
        val spec = PBEKeySpec(password.toCharArray(), salt, 2000, 256)
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        val keyBytes = factory.generateSecret(spec).encoded
        return SecretKeySpec(keyBytes, "AES")
    }

    fun generateKeyPair(): KeyPairData {
        val keyPairGen = KeyPairGenerator.getInstance("EC")
        keyPairGen.initialize(ECGenParameterSpec("secp256r1"))
        val keyPair: KeyPair = keyPairGen.generateKeyPair()

        val pubBytes = keyPair.public.encoded
        val privBytes = keyPair.private.encoded

        return KeyPairData(
            publicKeyBase64 = Base64.encodeToString(pubBytes, Base64.NO_WRAP),
            privateKeyBase64 = Base64.encodeToString(privBytes, Base64.NO_WRAP)
        )
    }

    private fun decodePublicKey(base64PublicKey: String): PublicKey {
        val cleanKey = base64PublicKey.substringBefore("::ENC::").trim()
        val bytes = Base64.decode(cleanKey, Base64.NO_WRAP)
        val spec = X509EncodedKeySpec(bytes)
        val keyFactory = KeyFactory.getInstance("EC")
        return keyFactory.generatePublic(spec)
    }

    private fun decodePrivateKey(base64PrivateKey: String): PrivateKey {
        val bytes = Base64.decode(base64PrivateKey, Base64.NO_WRAP)
        val spec = PKCS8EncodedKeySpec(bytes)
        val keyFactory = KeyFactory.getInstance("EC")
        return keyFactory.generatePrivate(spec)
    }

    private fun deriveSharedSecret(myPrivateKeyBase64: String, theirPublicKeyBase64: String): ByteArray {
        val privateKey = decodePrivateKey(myPrivateKeyBase64)
        val publicKey = decodePublicKey(theirPublicKeyBase64)

        val keyAgreement = KeyAgreement.getInstance("ECDH")
        keyAgreement.init(privateKey)
        keyAgreement.doPhase(publicKey, true)
        val sharedSecret = keyAgreement.generateSecret()

        val digest = MessageDigest.getInstance("SHA-256")
        return digest.digest(sharedSecret)
    }

    fun encryptMessage(myPrivateKeyBase64: String, theirPublicKeyBase64: String, plaintext: String): EncryptedPayload {
        val aesKeyBytes = deriveSharedSecret(myPrivateKeyBase64, theirPublicKeyBase64)
        val secretKey = SecretKeySpec(aesKeyBytes, "AES")

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val iv = ByteArray(12)
        SecureRandom().nextBytes(iv)
        val parameterSpec = GCMParameterSpec(128, iv)

        cipher.init(Cipher.ENCRYPT_MODE, secretKey, parameterSpec)
        val ciphertextBytes = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))

        return EncryptedPayload(
            ciphertext = Base64.encodeToString(ciphertextBytes, Base64.NO_WRAP),
            nonce = Base64.encodeToString(iv, Base64.NO_WRAP)
        )
    }

    fun decryptMessage(myPrivateKeyBase64: String, theirPublicKeyBase64: String, ciphertextBase64: String, nonceBase64: String): String {
        try {
            if (ciphertextBase64.isBlank() || nonceBase64.isBlank() || myPrivateKeyBase64.isBlank() || theirPublicKeyBase64.isBlank()) {
                return ""
            }
            val aesKeyBytes = deriveSharedSecret(myPrivateKeyBase64, theirPublicKeyBase64)
            val secretKey = SecretKeySpec(aesKeyBytes, "AES")

            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val iv = Base64.decode(nonceBase64, Base64.NO_WRAP)
            val ciphertextBytes = Base64.decode(ciphertextBase64, Base64.NO_WRAP)
            val parameterSpec = GCMParameterSpec(128, iv)

            cipher.init(Cipher.DECRYPT_MODE, secretKey, parameterSpec)
            val decryptedBytes = cipher.doFinal(ciphertextBytes)
            return String(decryptedBytes, Charsets.UTF_8)
        } catch (e: Exception) {
            return "[Encrypted Message]"
        }
    }

    fun encryptProfile(password: String, username: String, profileJson: String): String {
        val secretKey = deriveKeyPBKDF2(password, username)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val iv = ByteArray(12)
        SecureRandom().nextBytes(iv)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey, GCMParameterSpec(128, iv))
        val ciphertext = cipher.doFinal(profileJson.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(iv + ciphertext, Base64.NO_WRAP)
    }

    fun decryptProfile(password: String, username: String, encryptedProfileBase64: String): String? {
        try {
            if (encryptedProfileBase64.isBlank()) return null
            val secretKey = deriveKeyPBKDF2(password, username)
            val data = Base64.decode(encryptedProfileBase64, Base64.NO_WRAP) ?: return null
            if (data.size < 13) return null
            val iv = data.sliceArray(0 until 12)
            val ciphertext = data.sliceArray(12 until data.size)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, secretKey, GCMParameterSpec(128, iv))
            return String(cipher.doFinal(ciphertext), Charsets.UTF_8)
        } catch (e: Exception) {
            return null
        }
    }

    fun computePublicKeyFingerprint(publicKeyBase64: String): String {
        try {
            val bytes = Base64.decode(publicKeyBase64, Base64.NO_WRAP)
            val digest = MessageDigest.getInstance("SHA-256")
            val hash = digest.digest(bytes)
            return hash.take(8).joinToString("") { "%02x".format(it) }.chunked(4).joinToString(" ")
        } catch (e: Exception) {
            return "Invalid Key"
        }
    }

    // Static app-specific key for encrypting PFP links on the cloud server
    private fun derivePfpLinkKey(): SecretKeySpec {
        val salt = "CrazeChat_PFP_Link_Salt_Secure_2026".toByteArray(Charsets.UTF_8)
        val spec = PBEKeySpec("CrazeChat_PFP_Passphrase_Crypto_Link".toCharArray(), salt, 1000, 256)
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        val keyBytes = factory.generateSecret(spec).encoded
        return SecretKeySpec(keyBytes, "AES")
    }

    // Group Chat Symmetric Key derivation for multi-participant encrypted groups
    private fun deriveGroupKey(chatId: String): SecretKeySpec {
        val digest = MessageDigest.getInstance("SHA-256")
        val keyBytes = digest.digest("CrazeChat_Group_Secret_Key_2026_$chatId".toByteArray(Charsets.UTF_8))
        return SecretKeySpec(keyBytes, "AES")
    }

    fun encryptGroupMessage(chatId: String, plaintext: String): EncryptedPayload {
        val secretKey = deriveGroupKey(chatId)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val iv = ByteArray(12)
        SecureRandom().nextBytes(iv)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey, GCMParameterSpec(128, iv))
        val ciphertextBytes = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return EncryptedPayload(
            ciphertext = Base64.encodeToString(ciphertextBytes, Base64.NO_WRAP),
            nonce = Base64.encodeToString(iv, Base64.NO_WRAP)
        )
    }

    fun decryptGroupMessage(chatId: String, ciphertextBase64: String, nonceBase64: String): String {
        return try {
            if (ciphertextBase64.isBlank() || nonceBase64.isBlank()) return ""
            val secretKey = deriveGroupKey(chatId)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val iv = Base64.decode(nonceBase64, Base64.NO_WRAP)
            val ciphertextBytes = Base64.decode(ciphertextBase64, Base64.NO_WRAP)
            cipher.init(Cipher.DECRYPT_MODE, secretKey, GCMParameterSpec(128, iv))
            val decryptedBytes = cipher.doFinal(ciphertextBytes)
            String(decryptedBytes, Charsets.UTF_8)
        } catch (e: Exception) {
            "[Encrypted Group Message]"
        }
    }

    fun encryptPfpUrl(url: String): String {
        if (url.isBlank()) return ""
        return try {
            val secretKey = derivePfpLinkKey()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val iv = ByteArray(12)
            SecureRandom().nextBytes(iv)
            cipher.init(Cipher.ENCRYPT_MODE, secretKey, GCMParameterSpec(128, iv))
            val ciphertext = cipher.doFinal(url.toByteArray(Charsets.UTF_8))
            Base64.encodeToString(iv + ciphertext, Base64.NO_WRAP)
        } catch (e: Exception) {
            ""
        }
    }

    fun decryptPfpUrl(encryptedUrlBase64: String): String {
        if (encryptedUrlBase64.isBlank()) return ""
        return try {
            val secretKey = derivePfpLinkKey()
            val data = Base64.decode(encryptedUrlBase64, Base64.NO_WRAP) ?: return ""
            if (data.size < 13) return ""
            val iv = data.sliceArray(0 until 12)
            val ciphertext = data.sliceArray(12 until data.size)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, secretKey, GCMParameterSpec(128, iv))
            String(cipher.doFinal(ciphertext), Charsets.UTF_8)
        } catch (e: Exception) {
            ""
        }
    }
}
