package com.example.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.net.URI
import java.security.KeyStore
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class ProfileImageManager(private val context: Context) {

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        // Never follow an HTTPS redirect down to unencrypted HTTP.
        .followSslRedirects(false)
        .build()

    private val _pfpVersion = MutableStateFlow<Long>(System.currentTimeMillis())
    val pfpVersion: StateFlow<Long> = _pfpVersion.asStateFlow()

    companion object {
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS_PFP = "CrazeChat_PfpMasterKey_2026"
        private const val MAX_DIMENSION = 512
        private const val MAX_DOWNLOAD_BYTES = 10 * 1024 * 1024 // 10MB limit

        @Volatile
        private var instance: ProfileImageManager? = null

        fun getInstance(context: Context): ProfileImageManager {
            return instance ?: synchronized(this) {
                instance ?: ProfileImageManager(context.applicationContext).also { instance = it }
            }
        }
    }

    private fun getOrCreateSecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        if (!keyStore.containsAlias(KEY_ALIAS_PFP)) {
            val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
            val spec = KeyGenParameterSpec.Builder(
                KEY_ALIAS_PFP,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
            keyGenerator.init(spec)
            return keyGenerator.generateKey()
        }
        val entry = keyStore.getEntry(KEY_ALIAS_PFP, null) as KeyStore.SecretKeyEntry
        return entry.secretKey
    }

    private fun encryptData(data: ByteArray): ByteArray {
        val secretKey = getOrCreateSecretKey()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        val iv = cipher.iv // 12-byte IV for GCM
        val ciphertext = cipher.doFinal(data)

        val output = ByteArrayOutputStream()
        output.write(iv)
        output.write(ciphertext)
        return output.toByteArray()
    }

    private fun decryptData(encryptedBytes: ByteArray): ByteArray {
        require(encryptedBytes.size > 12) { "Corrupt encrypted image payload" }
        val secretKey = getOrCreateSecretKey()
        val iv = encryptedBytes.copyOfRange(0, 12)
        val ciphertext = encryptedBytes.copyOfRange(12, encryptedBytes.size)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val spec = GCMParameterSpec(128, iv)
        cipher.init(Cipher.DECRYPT_MODE, secretKey, spec)
        return cipher.doFinal(ciphertext)
    }

    fun validateImageUrl(url: String): Pair<Boolean, String?> {
        val trimmed = url.trim()
        if (trimmed.isBlank()) {
            return Pair(false, "Image URL cannot be empty")
        }
        return try {
            val uri = URI(trimmed)
            when {
                !uri.scheme.equals("https", ignoreCase = true) ->
                    Pair(false, "Image URLs must use HTTPS")
                uri.host.isNullOrBlank() ->
                    Pair(false, "Invalid host in image URL")
                uri.userInfo != null ->
                    Pair(false, "Image URLs must not contain embedded credentials")
                else -> Pair(true, null)
            }
        } catch (e: Exception) {
            Pair(false, "Invalid URL structure")
        }
    }

    private fun optimizeBitmap(rawBytes: ByteArray): ByteArray {
        val boundsOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(rawBytes, 0, rawBytes.size, boundsOptions)

        val width = boundsOptions.outWidth
        val height = boundsOptions.outHeight
        if (width <= 0 || height <= 0) {
            throw IllegalArgumentException("Could not read image dimensions. Unsupported or corrupt image file.")
        }

        var inSampleSize = 1
        if (width > MAX_DIMENSION || height > MAX_DIMENSION) {
            val halfWidth = width / 2
            val halfHeight = height / 2
            while ((halfWidth / inSampleSize) >= MAX_DIMENSION && (halfHeight / inSampleSize) >= MAX_DIMENSION) {
                inSampleSize *= 2
            }
        }

        val decodeOptions = BitmapFactory.Options().apply {
            this.inSampleSize = inSampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = BitmapFactory.decodeByteArray(rawBytes, 0, rawBytes.size, decodeOptions)
            ?: throw IllegalArgumentException("Failed to decode image data into bitmap.")

        // Further scale if needed to ensure max dimension is respected
        val finalBitmap = if (decoded.width > MAX_DIMENSION || decoded.height > MAX_DIMENSION) {
            val ratio = minOf(MAX_DIMENSION.toFloat() / decoded.width, MAX_DIMENSION.toFloat() / decoded.height)
            val targetW = (decoded.width * ratio).toInt().coerceAtLeast(1)
            val targetH = (decoded.height * ratio).toInt().coerceAtLeast(1)
            val scaled = Bitmap.createScaledBitmap(decoded, targetW, targetH, true)
            if (scaled != decoded) decoded.recycle()
            scaled
        } else {
            decoded
        }

        val output = ByteArrayOutputStream()
        finalBitmap.compress(Bitmap.CompressFormat.JPEG, 85, output)
        finalBitmap.recycle()
        return output.toByteArray()
    }

    private fun getEncryptedFile(userId: String): File {
        val safeId = userId.replace(Regex("[^a-zA-Z0-9_-]"), "_")
        return File(context.filesDir, "pfp_${safeId}.enc")
    }

    suspend fun hasPfp(userId: String): Boolean = withContext(Dispatchers.IO) {
        if (userId.isBlank()) false else getEncryptedFile(userId).exists()
    }

    suspend fun downloadAndSavePfp(userId: String, imageUrl: String): Result<Bitmap> = withContext(Dispatchers.IO) {
        try {
            val validation = validateImageUrl(imageUrl)
            if (!validation.first) {
                return@withContext Result.failure(IllegalArgumentException(validation.second ?: "Invalid image URL"))
            }

            val request = Request.Builder()
                .url(imageUrl.trim())
                .header("User-Agent", "CrazeChat/1.0 (Android E2EE Messenger)")
                .build()

            val rawBytes = httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    return@withContext Result.failure(IOException("HTTP error ${response.code} downloading image"))
                }

                val body = response.body
                    ?: return@withContext Result.failure(IOException("Empty response from image host"))

                // Reject known oversized bodies before reading, then enforce the limit while streaming
                // so a missing or dishonest Content-Length cannot exhaust memory.
                if (body.contentLength() > MAX_DOWNLOAD_BYTES.toLong()) {
                    return@withContext Result.failure(
                        IllegalArgumentException("Image exceeds the 10MB download limit")
                    )
                }

                body.byteStream().use { input ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(8 * 1024)
                    var totalBytes = 0
                    while (true) {
                        val count = input.read(buffer)
                        if (count == -1) break
                        totalBytes += count
                        if (totalBytes > MAX_DOWNLOAD_BYTES) {
                            throw IOException("Image exceeds the 10MB download limit")
                        }
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                }
            }

            // Downscale and compress into optimized format
            val optimizedBytes = optimizeBitmap(rawBytes)

            // Encrypt using hardware-backed Android KeyStore key
            val encryptedBytes = encryptData(optimizedBytes)

            // Write to private local storage
            val file = getEncryptedFile(userId)
            file.writeBytes(encryptedBytes)

            // Decrypt back for immediate in-memory return
            val returnBitmap = BitmapFactory.decodeByteArray(optimizedBytes, 0, optimizedBytes.size)

            _pfpVersion.value = System.currentTimeMillis()
            Result.success(returnBitmap)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getPfpBitmap(userId: String): Bitmap? = withContext(Dispatchers.IO) {
        if (userId.isBlank()) return@withContext null
        val file = getEncryptedFile(userId)
        if (!file.exists()) return@withContext null

        try {
            val encryptedBytes = file.readBytes()
            val decryptedBytes = decryptData(encryptedBytes)
            BitmapFactory.decodeByteArray(decryptedBytes, 0, decryptedBytes.size)
        } catch (e: Exception) {
            // If decryption fails (e.g. corrupted file), clean up
            file.delete()
            null
        }
    }

    suspend fun removePfp(userId: String): Boolean = withContext(Dispatchers.IO) {
        if (userId.isBlank()) return@withContext false
        val file = getEncryptedFile(userId)
        val deleted = if (file.exists()) file.delete() else true
        _pfpVersion.value = System.currentTimeMillis()
        deleted
    }

    suspend fun getPeerPfp(peerId: String): Bitmap? = withContext(Dispatchers.IO) {
        if (peerId.isBlank()) return@withContext null
        
        // 1. Check if we already have it locally decrypted/cached
        val file = getEncryptedFile(peerId)
        if (file.exists()) {
            try {
                val encryptedBytes = file.readBytes()
                val decryptedBytes = decryptData(encryptedBytes)
                return@withContext BitmapFactory.decodeByteArray(decryptedBytes, 0, decryptedBytes.size)
            } catch (e: Exception) {
                file.delete()
            }
        }
        
        // 2. Fetch encrypted PFP URL from Firebase Realtime Database
        try {
            val firebaseRepo = FirebaseRepository()
            val peerDto = firebaseRepo.findUserById(peerId)
            if (peerDto != null && peerDto.pfpUrl.isNotBlank()) {
                val decryptedUrl = CryptoManager.decryptPfpUrl(peerDto.pfpUrl)
                if (decryptedUrl.isNotBlank()) {
                    // Download, optimize, and save locally
                    val result = downloadAndSavePfp(peerId, decryptedUrl)
                    if (result.isSuccess) {
                        return@withContext result.getOrNull()
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("ProfileImageManager", "Failed to fetch/download peer PFP: ${e.message}")
        }
        null
    }
}
