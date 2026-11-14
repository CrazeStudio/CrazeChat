package com.crazestudio.crazechat.security

import android.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.bouncycastle.crypto.digests.SHA256Digest
import org.bouncycastle.crypto.generators.Argon2BytesGenerator
import org.bouncycastle.crypto.generators.HKDFBytesGenerator
import org.bouncycastle.crypto.params.Argon2Parameters
import org.bouncycastle.crypto.params.HKDFParameters
import org.bouncycastle.math.ec.rfc7748.X25519
import org.json.JSONObject
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

data class IdentityMaterial(
    val privateKey: ByteArray,
    val publicKey: ByteArray,
    val envelope: JSONObject
)

object CryptoService {
    private const val IDENTITY_AAD = "CrazeChat/identity-key/v1"
    private const val MESSAGE_FORMAT = "cc-e2ee-v1"
    private const val LOCAL_BACKUP_FORMAT = "cc-local-backup-v1"
    private const val ARGON_MEMORY_KIB = 32 * 1024
    private const val ARGON_ITERATIONS = 2
    private val random = SecureRandom()

    private fun randomBytes(size: Int) = ByteArray(size).also(random::nextBytes)

    /** Creates a 256-bit device-generated phrase; it is never derived from account details. */
    fun generateEncryptionPhrase(): String {
        val entropy = randomBytes(32)
        return try {
            Base64.encodeToString(entropy, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
                .chunked(4).joinToString("-")
        } finally {
            entropy.fill(0)
        }
    }
    private fun b64(bytes: ByteArray) = Base64.encodeToString(bytes, Base64.NO_WRAP)
    private fun decode(value: String) = Base64.decode(value, Base64.DEFAULT)

    private suspend fun derivePasswordKey(password: String, salt: ByteArray): ByteArray =
        withContext(Dispatchers.Default) {
            require(password.isNotEmpty()) { "Enter the encryption passphrase." }
            val output = ByteArray(32)
            val passwordChars = password.toCharArray()
            try {
                val parameters = Argon2Parameters.Builder(Argon2Parameters.ARGON2_id)
                    .withVersion(Argon2Parameters.ARGON2_VERSION_13)
                    .withIterations(ARGON_ITERATIONS)
                    .withMemoryAsKB(ARGON_MEMORY_KIB)
                    .withParallelism(1)
                    .withSalt(salt)
                    .build()
                Argon2BytesGenerator().apply { init(parameters) }
                    .generateBytes(passwordChars, output)
            } finally {
                passwordChars.fill('\u0000')
            }
            output
        }

    suspend fun createIdentity(encryptionPassphrase: String, separatePassphrase: Boolean = true): IdentityMaterial {
        require(encryptionPassphrase.length >= 12) {
            "Use an encryption passphrase with at least 12 characters."
        }
        val privateKey = randomBytes(32)
        val publicKey = ByteArray(32)
        X25519.generatePublicKey(privateKey, 0, publicKey, 0)
        val publicKeyEncoded = b64(publicKey)
        val salt = randomBytes(16)
        val wrappingKey = derivePasswordKey(encryptionPassphrase, salt)
        val nonce = randomBytes(12)
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(wrappingKey, "AES"), GCMParameterSpec(128, nonce))
            cipher.updateAAD("$IDENTITY_AAD:$publicKeyEncoded".toByteArray(Charsets.UTF_8))
            val packed = cipher.doFinal(privateKey)
            val envelope = JSONObject()
                .put("version", if (separatePassphrase) 2 else 3)
                .put("keyProtection", if (separatePassphrase) "separate-passphrase-v2" else "account-password-v3")
                .put("kdf", "Argon2id")
                .put("kdfMemoryKiB", ARGON_MEMORY_KIB)
                .put("kdfIterations", ARGON_ITERATIONS)
                .put("salt", b64(salt))
                .put("nonce", b64(nonce))
                .put("ciphertext", b64(packed.copyOfRange(0, packed.size - 16)))
                .put("mac", b64(packed.copyOfRange(packed.size - 16, packed.size)))
                .put("publicKey", publicKeyEncoded)
            return IdentityMaterial(privateKey, publicKey, envelope)
        } finally {
            wrappingKey.fill(0)
        }
    }

    suspend fun unlockIdentity(envelope: JSONObject, passphrase: String): IdentityMaterial {
        validateIdentityEnvelope(envelope)
        val publicKeyEncoded = envelope.getString("publicKey")
        val publicKey = decode(publicKeyEncoded)
        val salt = decode(envelope.getString("salt"))
        val nonce = decode(envelope.getString("nonce"))
        val ciphertext = decode(envelope.getString("ciphertext"))
        val mac = decode(envelope.getString("mac"))
        val wrappingKey = derivePasswordKey(passphrase, salt)
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(wrappingKey, "AES"), GCMParameterSpec(128, nonce))
            cipher.updateAAD("$IDENTITY_AAD:$publicKeyEncoded".toByteArray(Charsets.UTF_8))
            val privateKey = cipher.doFinal(ciphertext + mac)
            require(privateKey.size == 32) { "The identity private key has an invalid length." }
            val derivedPublic = ByteArray(32)
            X25519.generatePublicKey(privateKey, 0, derivedPublic, 0)
            require(MessageDigest.isEqual(derivedPublic, publicKey)) {
                "The decrypted identity does not match its public key."
            }
            return IdentityMaterial(privateKey, publicKey, envelope)
        } finally {
            wrappingKey.fill(0)
        }
    }

    suspend fun rewrapIdentity(
        privateKey: ByteArray,
        publicKey: ByteArray,
        passphrase: String,
        separatePassphrase: Boolean
    ): IdentityMaterial {
        require(privateKey.size == 32 && publicKey.size == 32) {
            "The unlocked identity key is invalid."
        }
        require(passphrase.length >= 12) { "Use a passphrase with at least 12 characters." }
        val derivedPublic = ByteArray(32)
        X25519.generatePublicKey(privateKey, 0, derivedPublic, 0)
        require(MessageDigest.isEqual(derivedPublic, publicKey)) {
            "The unlocked private key does not match the account's public key."
        }
        val publicKeyEncoded = b64(publicKey)
        val salt = randomBytes(16)
        val nonce = randomBytes(12)
        val wrappingKey = derivePasswordKey(passphrase, salt)
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(wrappingKey, "AES"), GCMParameterSpec(128, nonce))
            cipher.updateAAD("$IDENTITY_AAD:$publicKeyEncoded".toByteArray(Charsets.UTF_8))
            val packed = cipher.doFinal(privateKey)
            val envelope = JSONObject()
                .put("version", if (separatePassphrase) 2 else 3)
                .put("keyProtection", if (separatePassphrase) "separate-passphrase-v2" else "account-password-v3")
                .put("kdf", "Argon2id")
                .put("kdfMemoryKiB", ARGON_MEMORY_KIB)
                .put("kdfIterations", ARGON_ITERATIONS)
                .put("salt", b64(salt))
                .put("nonce", b64(nonce))
                .put("ciphertext", b64(packed.copyOfRange(0, packed.size - 16)))
                .put("mac", b64(packed.copyOfRange(packed.size - 16, packed.size)))
                .put("publicKey", publicKeyEncoded)
            return IdentityMaterial(privateKey.copyOf(), publicKey.copyOf(), envelope)
        } finally {
            wrappingKey.fill(0)
        }
    }

    fun validateIdentityEnvelope(envelope: JSONObject) {
        require(envelope.optInt("version") in 1..3 && envelope.optString("kdf") == "Argon2id") {
            "Unsupported encrypted identity format."
        }
        require(decode(envelope.getString("salt")).size == 16) { "Invalid identity salt." }
        require(decode(envelope.getString("nonce")).size == 12) { "Invalid identity nonce." }
        require(decode(envelope.getString("mac")).size == 16) { "Invalid identity authentication tag." }
        require(decode(envelope.getString("publicKey")).size == 32) { "Invalid identity public key." }
        require(decode(envelope.getString("ciphertext")).isNotEmpty()) { "Identity ciphertext is empty." }
    }

    fun derivePublicKey(privateKey: ByteArray): ByteArray {
        require(privateKey.size == 32) { "The identity private key is invalid." }
        return ByteArray(32).also { X25519.generatePublicKey(privateKey, 0, it, 0) }
    }

    suspend fun deriveChatKey(identityPrivateKey: ByteArray, peerPublicKeyBase64: String, chatId: String): ByteArray =
        withContext(Dispatchers.Default) {
            val peerPublicKey = decode(peerPublicKeyBase64)
            require(identityPrivateKey.size == 32 && peerPublicKey.size == 32) {
                "Conversation encryption keys have an invalid length."
            }
            val shared = ByteArray(32)
            require(X25519.calculateAgreement(identityPrivateKey, 0, peerPublicKey, 0, shared, 0)) {
                "Could not establish the encrypted conversation."
            }
            try {
                ByteArray(32).also { output ->
                    val hkdf = HKDFBytesGenerator(SHA256Digest())
                    hkdf.init(HKDFParameters(
                        shared,
                        chatId.toByteArray(Charsets.UTF_8),
                        "CrazeChat/direct-message/v1".toByteArray(Charsets.UTF_8)
                    ))
                    hkdf.generateBytes(output, 0, output.size)
                }
            } finally {
                shared.fill(0)
            }
        }

    fun encryptMessage(text: String, chatKey: ByteArray, chatId: String, senderId: String): JSONObject {
        require(text.isNotEmpty() && text.toByteArray(Charsets.UTF_8).size <= 12000)
        require(chatKey.size == 32)
        val nonce = randomBytes(12)
        val aad = "CrazeChat/message/v1:$chatId:$senderId".toByteArray(Charsets.UTF_8)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(chatKey, "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD(aad)
        val packed = cipher.doFinal(text.toByteArray(Charsets.UTF_8))
        return JSONObject()
            .put("format", MESSAGE_FORMAT)
            .put("ciphertext", b64(packed.copyOfRange(0, packed.size - 16)))
            .put("nonce", b64(nonce))
            .put("mac", b64(packed.copyOfRange(packed.size - 16, packed.size)))
    }

    fun decryptMessage(message: JSONObject, chatKey: ByteArray, chatId: String): String {
        require(message.optString("format") == MESSAGE_FORMAT) { "Unsupported message encryption format." }
        require(chatKey.size == 32)
        val senderId = message.getString("senderId")
        val nonce = decode(message.getString("nonce"))
        val ciphertext = decode(message.getString("ciphertext"))
        val mac = decode(message.getString("mac"))
        require(nonce.size == 12 && mac.size == 16 && ciphertext.isNotEmpty())
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(chatKey, "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD("CrazeChat/message/v1:$chatId:$senderId".toByteArray(Charsets.UTF_8))
        val clear = String(cipher.doFinal(ciphertext + mac), Charsets.UTF_8)
        return try {
            val payload = JSONObject(clear)
            if (payload.optString("__cc_type") == "message") payload.optString("text", "") else clear
        } catch (_: Exception) {
            clear
        }
    }

    suspend fun encryptLocalBackup(archive: ByteArray, identityPrivateKey: ByteArray, userId: String): JSONObject =
        withContext(Dispatchers.Default) {
            require(identityPrivateKey.size == 32 && userId.isNotBlank())
            val keyBytes = ByteArray(32)
            val hkdf = HKDFBytesGenerator(SHA256Digest())
            hkdf.init(HKDFParameters(
                identityPrivateKey,
                "CrazeChat/local-backup-salt/v1:$userId".toByteArray(Charsets.UTF_8),
                "CrazeChat/local-folder-backup/v1".toByteArray(Charsets.UTF_8)
            ))
            hkdf.generateBytes(keyBytes, 0, keyBytes.size)
            try {
                val nonce = randomBytes(12)
                val aad = "$LOCAL_BACKUP_FORMAT:$userId".toByteArray(Charsets.UTF_8)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(keyBytes, "AES"), GCMParameterSpec(128, nonce))
                cipher.updateAAD(aad)
                val packed = cipher.doFinal(archive)
                JSONObject()
                    .put("format", LOCAL_BACKUP_FORMAT)
                    .put("nonce", b64(nonce))
                    .put("ciphertext", b64(packed.copyOfRange(0, packed.size - 16)))
                    .put("mac", b64(packed.copyOfRange(packed.size - 16, packed.size)))
            } finally {
                keyBytes.fill(0)
            }
        }

    suspend fun decryptLocalBackup(envelope: JSONObject, identityPrivateKey: ByteArray, userId: String): ByteArray =
        withContext(Dispatchers.Default) {
            require(identityPrivateKey.size == 32 && userId.isNotBlank())
            require(envelope.optString("format") == LOCAL_BACKUP_FORMAT) {
                "Unsupported local backup format."
            }
            val nonce = decode(envelope.getString("nonce"))
            val ciphertext = decode(envelope.getString("ciphertext"))
            val mac = decode(envelope.getString("mac"))
            require(nonce.size == 12 && mac.size == 16 && ciphertext.isNotEmpty())
            val keyBytes = ByteArray(32)
            val hkdf = HKDFBytesGenerator(SHA256Digest())
            hkdf.init(HKDFParameters(
                identityPrivateKey,
                "CrazeChat/local-backup-salt/v1:$userId".toByteArray(Charsets.UTF_8),
                "CrazeChat/local-folder-backup/v1".toByteArray(Charsets.UTF_8)
            ))
            hkdf.generateBytes(keyBytes, 0, keyBytes.size)
            try {
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(keyBytes, "AES"), GCMParameterSpec(128, nonce))
                cipher.updateAAD("$LOCAL_BACKUP_FORMAT:$userId".toByteArray(Charsets.UTF_8))
                cipher.doFinal(ciphertext + mac)
            } finally {
                keyBytes.fill(0)
            }
        }

    fun fingerprint(publicKeyBase64: String): String {
        val publicKey = decode(publicKeyBase64)
        require(publicKey.size == 32) { "Contact public key must contain exactly 32 bytes." }
        val digest = MessageDigest.getInstance("SHA-256").digest(publicKey)
        return digest.joinToString("") { "%02X".format(it) }.chunked(4).joinToString(" ")
    }

    fun createMessageId(): String = randomBytes(16).joinToString("") { "%02x".format(it) }
}
