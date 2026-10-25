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

    private const val LOCAL_PASSWORD_ITERATIONS = 600_000

    /** New local password verifier uses a unique random salt and PBKDF2-HMAC-SHA256. */
    fun hashPassword(password: String): String {
        val salt = ByteArray(16).also(SecureRandom()::nextBytes)
        val spec = PBEKeySpec(password.toCharArray(), salt, LOCAL_PASSWORD_ITERATIONS, 256)
        val derived = try {
            SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
        } finally {
            spec.clearPassword()
        }
        return "CCPH2$$LOCAL_PASSWORD_ITERATIONS$${Base64.encodeToString(salt, Base64.NO_WRAP)}$${Base64.encodeToString(derived, Base64.NO_WRAP)}"
    }

    /** Supports old SHA-256 and plaintext local profiles only for migration, then rehashes on login. */
    fun verifyPassword(password: String, stored: String): Boolean {
        if (stored.startsWith("CCPH2$")) {
            return try {
                val parts = stored.split('$')
                if (parts.size != 4) return false
                val iterations = parts[1].toIntOrNull() ?: return false
                if (iterations !in 100_000..1_000_000) return false
                val salt = Base64.decode(parts[2], Base64.NO_WRAP)
                val expected = Base64.decode(parts[3], Base64.NO_WRAP)
                val spec = PBEKeySpec(password.toCharArray(), salt, iterations, expected.size * 8)
                val actual = try {
                    SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
                } finally {
                    spec.clearPassword()
                }
                MessageDigest.isEqual(actual, expected)
            } catch (_: Exception) { false }
        }
        val oldDigest = MessageDigest.getInstance("SHA-256")
            .digest("CrazeChat_Salt_2026_$password".toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        if (stored.matches(Regex("^[a-fA-F0-9]{64}$"))) {
            return MessageDigest.isEqual(stored.lowercase().toByteArray(Charsets.UTF_8), oldDigest.toByteArray(Charsets.UTF_8))
        }
        return stored == password
    }

    // Version 1 backups used a deterministic salt and 2,000 iterations.
    // Retained solely for compatibility with old encrypted profile backups.
    private fun deriveLegacyProfileKey(password: String, username: String): SecretKeySpec {
        val salt = "CrazeChat_PBKDF2_Salt_2026_${username.lowercase()}".toByteArray(Charsets.UTF_8)
        val spec = PBEKeySpec(password.toCharArray(), salt, 2000, 256)
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        val keyBytes = factory.generateSecret(spec).encoded
        spec.clearPassword()
        return SecretKeySpec(keyBytes, "AES")
    }

    private fun deriveProfileKeyV2(password: String, salt: ByteArray): SecretKeySpec {
        val spec = PBEKeySpec(password.toCharArray(), salt, 600_000, 256)
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        val keyBytes = factory.generateSecret(spec).encoded
        spec.clearPassword()
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

    /** V2 backup: random salt + PBKDF2-HMAC-SHA256 (600k iterations) + AES-GCM. */
    fun encryptProfile(password: String, username: String, profileJson: String): String {
        val random = SecureRandom()
        val salt = ByteArray(16).also(random::nextBytes)
        val iv = ByteArray(12).also(random::nextBytes)
        val secretKey = deriveProfileKeyV2(password, salt)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey, GCMParameterSpec(128, iv))
        cipher.updateAAD("CrazeChatProfileV2".toByteArray(Charsets.UTF_8))
        val ciphertext = cipher.doFinal(profileJson.toByteArray(Charsets.UTF_8))
        return "CCP2:" + Base64.encodeToString(salt + iv + ciphertext, Base64.NO_WRAP)
    }

    fun decryptProfile(password: String, username: String, encryptedProfileBase64: String): String? {
        return try {
            if (encryptedProfileBase64.isBlank()) return null
            if (encryptedProfileBase64.startsWith("CCP2:")) {
                val packed = Base64.decode(encryptedProfileBase64.removePrefix("CCP2:"), Base64.NO_WRAP)
                if (packed.size < 16 + 12 + 16) return null
                val salt = packed.copyOfRange(0, 16)
                val iv = packed.copyOfRange(16, 28)
                val ciphertext = packed.copyOfRange(28, packed.size)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, deriveProfileKeyV2(password, salt), GCMParameterSpec(128, iv))
                cipher.updateAAD("CrazeChatProfileV2".toByteArray(Charsets.UTF_8))
                String(cipher.doFinal(ciphertext), Charsets.UTF_8)
            } else {
                // V1 is intentionally supported only so that existing users can migrate.
                val data = Base64.decode(encryptedProfileBase64, Base64.NO_WRAP)
                if (data.size < 12 + 16) return null
                val iv = data.copyOfRange(0, 12)
                val ciphertext = data.copyOfRange(12, data.size)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, deriveLegacyProfileKey(password, username), GCMParameterSpec(128, iv))
                String(cipher.doFinal(ciphertext), Charsets.UTF_8)
            }
        } catch (_: Exception) { null }
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

    /** New groups use random secret keys wrapped individually for every member. */
    fun generateGroupKey(): String =
        Base64.encodeToString(ByteArray(32).also(SecureRandom()::nextBytes), Base64.NO_WRAP)

    fun isValidGroupKey(groupKeyBase64: String): Boolean = try {
        Base64.decode(groupKeyBase64, Base64.NO_WRAP).size == 32
    } catch (_: Exception) { false }

    fun groupMessageVersion(ciphertext: String): Int =
        Regex("^G2v([1-9][0-9]{0,8}):").find(ciphertext)?.groupValues?.getOrNull(1)?.toIntOrNull() ?: 0

    fun encryptGroupMessage(groupKeyBase64: String, plaintext: String, version: Int): EncryptedPayload {
        require(isValidGroupKey(groupKeyBase64)) { "A valid group key is required." }
        require(version > 0) { "Group key version must be positive." }
        val key = SecretKeySpec(Base64.decode(groupKeyBase64, Base64.NO_WRAP), "AES")
        val iv = ByteArray(12).also(SecureRandom()::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, iv))
        cipher.updateAAD("CrazeChatGroupV2:$version".toByteArray(Charsets.UTF_8))
        val encrypted = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return EncryptedPayload("G2v$version:" + Base64.encodeToString(encrypted, Base64.NO_WRAP),
            Base64.encodeToString(iv, Base64.NO_WRAP))
    }

    fun decryptGroupMessage(groupKeyBase64: String, ciphertext: String, nonceBase64: String): String {
        return try {
            val version = groupMessageVersion(ciphertext)
            if (version <= 0 || !isValidGroupKey(groupKeyBase64) || nonceBase64.isBlank()) return ""
            val key = SecretKeySpec(Base64.decode(groupKeyBase64, Base64.NO_WRAP), "AES")
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, Base64.decode(nonceBase64, Base64.NO_WRAP)))
            cipher.updateAAD("CrazeChatGroupV2:$version".toByteArray(Charsets.UTF_8))
            String(cipher.doFinal(Base64.decode(ciphertext.substringAfter(':'), Base64.NO_WRAP)), Charsets.UTF_8)
        } catch (_: Exception) { "[Encrypted Group Message]" }
    }

    // Compatibility only: previous versions derived this key from a constant bundled in the APK.
    // Old group messages are not confidential from someone who reverse-engineers that APK.
    private fun deriveLegacyGroupKey(chatId: String): SecretKeySpec {
        val digest = MessageDigest.getInstance("SHA-256")
        return SecretKeySpec(digest.digest("CrazeChat_Group_Secret_Key_2026_$chatId".toByteArray(Charsets.UTF_8)), "AES")
    }

    fun encryptLegacyGroupMessage(chatId: String, plaintext: String): EncryptedPayload {
        val iv = ByteArray(12).also(SecureRandom()::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, deriveLegacyGroupKey(chatId), GCMParameterSpec(128, iv))
        return EncryptedPayload(Base64.encodeToString(cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP),
            Base64.encodeToString(iv, Base64.NO_WRAP))
    }

    fun decryptLegacyGroupMessage(chatId: String, ciphertextBase64: String, nonceBase64: String): String {
        return try {
            if (ciphertextBase64.isBlank() || nonceBase64.isBlank()) return ""
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, deriveLegacyGroupKey(chatId), GCMParameterSpec(128, Base64.decode(nonceBase64, Base64.NO_WRAP)))
            String(cipher.doFinal(Base64.decode(ciphertextBase64, Base64.NO_WRAP)), Charsets.UTF_8)
        } catch (_: Exception) { "[Legacy Encrypted Group Message]" }
    }

    fun decryptGroupMessageCompat(chatId: String, groupKeyBase64: String, ciphertext: String, nonceBase64: String): String =
        if (groupMessageVersion(ciphertext) > 0) decryptGroupMessage(groupKeyBase64, ciphertext, nonceBase64)
        else decryptLegacyGroupMessage(chatId, ciphertext, nonceBase64)

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
