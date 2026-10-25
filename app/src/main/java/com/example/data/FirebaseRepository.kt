package com.example.data

import android.content.Context
import android.util.Log
import com.example.BuildConfig
import com.google.firebase.database.ChildEventListener
import com.google.firebase.database.DataSnapshot
import com.google.firebase.database.DatabaseError
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

data class FirebaseUserDto(
    val userId: String = "",
    val username: String = "",
    val publicKey: String = "",
    val encryptedBackup: String = "",
    val pfpUrl: String = ""
)

data class FirebaseMessageDto(
    val senderId: String = "",
    val receiverId: String = "",
    val ciphertext: String = "",
    val nonce: String = "",
    val timestamp: Long = 0L,
    val senderUsername: String = "",
    val isEdited: Boolean = false,
    val editedAt: Long = 0L,
    val isPinned: Boolean = false,
    val pinnedAt: Long = 0L,
    val isDeleted: Boolean = false,
    val reactionTargetId: String = "",
    val reactionEmoji: String = "",
    val replyToId: String = "",
    val replyToText: String = "",
    val replyToSender: String = "",
    val reactionsJson: String = "{}"
)

data class FirebaseGroupDto(
    val chatId: String = "",
    val groupName: String = "",
    val groupOwnerId: String = "",
    val members: Map<String, Boolean> = emptyMap(),
    val pinnedMessageId: String = "",
    val createdAt: Long = 0L
)

/**
 * Compatibility adapter: the Android UI keeps its existing repository API, but all cloud
 * reads/writes go through the CrazeChat HTTP API. Firebase SDK listeners are replaced by
 * lightweight polling because the HTTP API does not provide Firebase realtime streams.
 */
class FirebaseRepository(private val context: Context? = null) {
    companion object {
        private const val TAG = "CrazeApiRepository"
        private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()
        private const val POLL_MS = 2500L
        private data class TokenEntry(val value: String, val expiresAt: Long)
        private val tokenCache = ConcurrentHashMap<String, TokenEntry>()
    }

    private val baseUrl = BuildConfig.CRAZECHAT_API_BASE_URL.trimEnd('/')
    private val apiKey = BuildConfig.CRAZECHAT_API_ACCESS_KEY
    private val preferences = context?.let { UserPreferences(it) }
    private val http = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(10, TimeUnit.SECONDS)
        .callTimeout(20, TimeUnit.SECONDS)
        .build()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val listenerJobs = ConcurrentHashMap<ChildEventListener, Job>()

    private class ApiException(val status: Int, message: String) : IOException(message)

    private suspend fun activeUid(): String =
        preferences?.userIdFlow?.first()?.takeIf { it.isNotBlank() } ?: "device"

    private fun segment(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8.name()).replace("+", "%20")

    private fun millis(value: String?): Long = try {
        java.time.Instant.parse(value).toEpochMilli()
    } catch (_: Exception) {
        try { value?.toLong() ?: 0L } catch (_: Exception) { 0L }
    }

    private fun rawRequest(method: String, path: String, body: JSONObject?, bearer: String?): JSONObject {
        if (baseUrl.isBlank()) throw IOException("CrazeChat API base URL is missing.")
        val builder = Request.Builder().url(baseUrl + path)
            .header("Accept", "application/json")
        if (!bearer.isNullOrBlank()) builder.header("X-API-Token", bearer)
        if (body != null) builder.header("Content-Type", "application/json")
        val requestBody = body?.toString()?.toRequestBody(JSON_MEDIA)
        builder.method(method, when {
            method == "GET" || method == "HEAD" -> null
            requestBody != null -> requestBody
            method == "DELETE" -> ByteArray(0).toRequestBody(JSON_MEDIA)
            else -> "{}".toRequestBody(JSON_MEDIA)
        })
        http.newCall(builder.build()).execute().use { response ->
            val text = response.body?.string().orEmpty()
            val json = try { if (text.isBlank()) JSONObject() else JSONObject(text) } catch (_: Exception) { JSONObject().put("message", text.take(300)) }
            if (!response.isSuccessful) {
                throw ApiException(response.code, json.optString("error", json.optString("message", "API request failed (HTTP ${response.code})")))
            }
            return json
        }
    }

    private fun tokenFor(uid: String): String {
        if (apiKey.isBlank()) {
            throw IOException("API access key is not configured in this APK. Add the same value as Vercel ACCESS_KEY to GitHub Actions secret CRAZECHAT_API_ACCESS_KEY, then rebuild.")
        }
        val cached = tokenCache[uid]
        if (cached != null && cached.expiresAt > System.currentTimeMillis() + 30_000L) return cached.value
        val response = rawRequest(
            "POST", "/verify",
            JSONObject().put("password", apiKey).put("uid", uid),
            null
        )
        val value = response.optString("token")
        if (value.isBlank()) throw IOException("API verification succeeded without returning a token.")
        val ttl = response.optLong("expiresIn", 43_200L).coerceIn(60L, 86_400L)
        tokenCache[uid] = TokenEntry(value, System.currentTimeMillis() + ttl * 1000L - 30_000L)
        return value
    }

    private suspend fun api(uid: String, method: String, path: String, body: JSONObject? = null): JSONObject =
        withContext(Dispatchers.IO) {
            val firstToken = tokenFor(uid)
            try {
                rawRequest(method, path, body, firstToken)
            } catch (error: ApiException) {
                if (error.status != 401) throw error
                tokenCache.remove(uid)
                rawRequest(method, path, body, tokenFor(uid))
            }
        }

    private fun dto(value: JSONObject): FirebaseUserDto {
        val rawKey = value.optString("publicKey")
        return FirebaseUserDto(
            userId = value.optString("userId", value.optString("uid")),
            username = value.optString("username"),
            publicKey = rawKey.substringBefore("::ENC::"),
            encryptedBackup = if (rawKey.contains("::ENC::")) rawKey.substringAfter("::ENC::") else value.optString("encryptedBackup"),
            pfpUrl = value.optString("pfpUrl")
        )
    }

    private fun message(value: JSONObject): FirebaseMessageDto {
        val reactions = value.optJSONObject("reactions") ?: JSONObject()
        val edited = value.optString("editedAt")
        return FirebaseMessageDto(
            senderId = value.optString("senderUid", value.optString("senderId")),
            receiverId = value.optString("receiverId"),
            ciphertext = value.optString("ciphertext"),
            nonce = value.optString("nonce"),
            timestamp = millis(value.optString("createdAt").ifBlank { value.optString("timestamp") }),
            senderUsername = value.optString("senderUsername"),
            isEdited = edited.isNotBlank() && edited != "null",
            editedAt = millis(edited),
            isPinned = value.optBoolean("pinned", value.optBoolean("isPinned", false)),
            pinnedAt = millis(value.optString("pinnedAt")),
            isDeleted = value.optBoolean("isDeleted", false),
            reactionTargetId = value.optString("reactionTargetId"),
            reactionEmoji = value.optString("reactionEmoji"),
            replyToId = value.optString("replyToId"),
            replyToText = value.optString("replyToText"),
            replyToSender = value.optString("replyToSender"),
            reactionsJson = reactions.toString()
        )
    }

    private suspend fun users(uid: String): List<FirebaseUserDto> {
        val array = api(uid, "GET", "/api/chat/users").optJSONArray("users") ?: JSONArray()
        return (0 until array.length()).mapNotNull { i ->
            array.optJSONObject(i)?.let(::dto)?.takeIf { it.userId.isNotBlank() && it.username.isNotBlank() }
        }
    }

    private suspend fun chats(uid: String): List<JSONObject> {
        val array = api(uid, "GET", "/api/chat/chats").optJSONArray("chats") ?: JSONArray()
        return (0 until array.length()).mapNotNull { array.optJSONObject(it) }
    }

    private suspend fun messages(uid: String, chatId: String): List<JSONObject> {
        val response = api(uid, "GET", "/api/chat/messages?chatId=${segment(chatId)}&limit=100")
        val array = response.optJSONArray("messages") ?: JSONArray()
        return (0 until array.length()).mapNotNull { array.optJSONObject(it) }
    }

    private fun dummyListener(): ChildEventListener = object : ChildEventListener {
        override fun onChildAdded(snapshot: DataSnapshot, previousChildName: String?) {}
        override fun onChildChanged(snapshot: DataSnapshot, previousChildName: String?) {}
        override fun onChildRemoved(snapshot: DataSnapshot) {}
        override fun onChildMoved(snapshot: DataSnapshot, previousChildName: String?) {}
        override fun onCancelled(error: DatabaseError) { Log.w(TAG, "API polling listener cancelled: ${error.message}") }
    }

    private fun observe(listener: ChildEventListener, block: suspend () -> Unit): ChildEventListener {
        listenerJobs[listener] = scope.launch {
            while (isActive) {
                try { block() } catch (e: Exception) { Log.w(TAG, "API polling failed: ${e.message}") }
                delay(POLL_MS)
            }
        }
        return listener
    }

    suspend fun registerUser(userId: String, username: String, publicKey: String, encryptedBackup: String = ""): Boolean = try {
        val combinedKey = if (encryptedBackup.isNotBlank()) "$publicKey::ENC::$encryptedBackup" else publicKey
        api(userId, "PUT", "/api/chat/users/me", JSONObject()
            .put("username", username)
            .put("publicKey", combinedKey))
        true
    } catch (e: Exception) { Log.e(TAG, "registerUser failed", e); false }

    suspend fun getAllUsers(): List<FirebaseUserDto> = try { users(activeUid()) }
    catch (e: Exception) { Log.e(TAG, "getAllUsers failed", e); emptyList() }

    suspend fun updatePfpUrl(userId: String, encryptedPfpUrl: String): Boolean = try {
        api(userId, "PATCH", "/api/chat/users/me", JSONObject().put("pfpUrl", encryptedPfpUrl))
        true
    } catch (e: Exception) { Log.e(TAG, "updatePfpUrl failed", e); false }

    suspend fun findUser(query: String): FirebaseUserDto? {
        val clean = query.trim()
        if (clean.isBlank()) return null
        val uid = activeUid()
        try {
            val result = api(uid, "GET", "/api/chat/users/${segment(clean)}").optJSONObject("user")
            if (result != null) return dto(result)
        } catch (_: ApiException) {
            // If this was a username, fall back to exact username lookup.
        } catch (e: Exception) {
            Log.w(TAG, "ID lookup failed; trying username lookup: ${e.message}")
        }
        return try { users(uid).firstOrNull { it.username.equals(clean, ignoreCase = true) } }
        catch (e: Exception) { Log.e(TAG, "findUser failed", e); null }
    }

    suspend fun findUserByUsername(usernameQuery: String): FirebaseUserDto? =
        try { users(activeUid()).firstOrNull { it.username.equals(usernameQuery.trim(), ignoreCase = true) } }
        catch (e: Exception) { Log.e(TAG, "findUserByUsername failed", e); null }

    suspend fun findUserById(userId: String): FirebaseUserDto? = try {
        dto(api(activeUid(), "GET", "/api/chat/users/${segment(userId)}").getJSONObject("user"))
    } catch (e: Exception) { Log.w(TAG, "findUserById failed: ${e.message}"); null }

    suspend fun createDirectChat(chatId: String, userId: String, peerUserId: String): Boolean = try {
        api(userId, "GET", "/api/chat/chats/${segment(chatId)}")
        true
    } catch (e: ApiException) {
        if (e.status != 404) {
            Log.w(TAG, "Could not check direct chat: ${e.message}")
            false
        } else try {
            api(userId, "POST", "/api/chat/chats", JSONObject()
                .put("id", chatId)
                .put("title", "")
                .put("isGroup", false)
                .put("memberIds", JSONArray().put(userId).put(peerUserId)))
            true
        } catch (createError: Exception) { Log.e(TAG, "createDirectChat failed", createError); false }
    } catch (e: Exception) { Log.e(TAG, "createDirectChat failed", e); false }

    suspend fun sendMessage(
        chatId: String, messageId: String, senderId: String, receiverId: String,
        ciphertext: String, nonce: String, timestamp: Long, senderUsername: String = "",
        replyToId: String = "", replyToText: String = "", replyToSender: String = ""
    ): Boolean = try {
        api(senderId, "POST", "/api/chat/messages", JSONObject()
            .put("chatId", chatId).put("receiverId", receiverId)
            .put("ciphertext", ciphertext).put("nonce", nonce)
            .put("senderUsername", senderUsername).put("replyToId", replyToId)
            .put("replyToText", replyToText).put("replyToSender", replyToSender)
            .put("ttlMinutes", 1440))
        true
    } catch (e: Exception) { Log.e(TAG, "sendMessage failed", e); false }

    suspend fun sendReaction(
        chatId: String, reactionId: String, senderId: String, receiverId: String,
        targetMessageId: String, emoji: String, timestamp: Long, senderUsername: String = ""
    ): Boolean = try {
        api(senderId, "POST", "/api/chat/messages/${segment(targetMessageId)}/reactions", JSONObject().put("emoji", emoji))
        true
    } catch (e: Exception) { Log.e(TAG, "sendReaction failed", e); false }

    suspend fun editMessage(chatId: String, messageId: String, newCiphertext: String, newNonce: String): Boolean = try {
        api(activeUid(), "PATCH", "/api/chat/messages/${segment(messageId)}", JSONObject()
            .put("ciphertext", newCiphertext).put("nonce", newNonce))
        true
    } catch (e: Exception) { Log.e(TAG, "editMessage failed", e); false }

    suspend fun pinMessage(chatId: String, messageId: String, isPinned: Boolean): Boolean = try {
        api(activeUid(), "POST", "/api/chat/messages/${segment(messageId)}/pin", JSONObject().put("pinned", isPinned))
        true
    } catch (e: Exception) { Log.e(TAG, "pinMessage failed", e); false }

    suspend fun createGroup(chatId: String, groupName: String, ownerId: String, memberIds: List<String>): Boolean = try {
        api(ownerId, "POST", "/api/chat/chats", JSONObject()
            .put("id", chatId).put("title", groupName).put("isGroup", true)
            .put("memberIds", JSONArray((memberIds + ownerId).distinct())))
        true
    } catch (e: Exception) { Log.e(TAG, "createGroup failed", e); false }

    suspend fun addGroupMember(chatId: String, newMemberId: String): Boolean = try {
        api(activeUid(), "POST", "/api/chat/chats/${segment(chatId)}/members", JSONObject().put("memberId", newMemberId))
        true
    } catch (e: Exception) { Log.e(TAG, "addGroupMember failed", e); false }

    suspend fun getGroupInfo(chatId: String): FirebaseGroupDto? = try {
        val chat = api(activeUid(), "GET", "/api/chat/chats/${segment(chatId)}").optJSONObject("chat") ?: return null
        val memberObject = chat.optJSONObject("members") ?: JSONObject()
        val members = mutableMapOf<String, Boolean>()
        val keys = memberObject.keys()
        while (keys.hasNext()) members[keys.next()] = true
        FirebaseGroupDto(chatId, chat.optString("title"), chat.optString("createdBy"), members,
            chat.optString("pinnedMessageId"), millis(chat.optString("createdAt")))
    } catch (e: Exception) { Log.w(TAG, "getGroupInfo failed: ${e.message}"); null }

    suspend fun getUserGroupIds(userId: String): List<String> = try {
        chats(userId).filter { it.optBoolean("isGroup") }
            .filter { it.optJSONObject("members")?.has(userId) == true }
            .map { it.optString("id") }.filter { it.isNotBlank() }
    } catch (e: Exception) { Log.e(TAG, "getUserGroupIds failed", e); emptyList() }

    fun observeUserInbox(
        userId: String,
        onInboxReceived: (chatId: String, senderId: String, senderUsername: String, timestamp: Long) -> Unit
    ): ChildEventListener {
        val listener = dummyListener()
        val lastSeen = ConcurrentHashMap<String, Long>()
        return observe(listener) {
            for (chat in chats(userId).filterNot { it.optBoolean("isGroup") }) {
                val chatId = chat.optString("id")
                if (chatId.isBlank()) continue
                val latest = messages(userId, chatId).maxByOrNull { millis(it.optString("createdAt")) } ?: continue
                val sender = latest.optString("senderUid")
                val stamp = millis(latest.optString("createdAt"))
                if (sender.isNotBlank() && sender != userId && stamp > (lastSeen[chatId] ?: 0L)) {
                    lastSeen[chatId] = stamp
                    onInboxReceived(chatId, sender, latest.optString("senderUsername"), stamp)
                }
            }
        }
    }

    fun observeUserGroups(userId: String, onGroupAdded: (chatId: String, groupName: String) -> Unit): ChildEventListener {
        val listener = dummyListener()
        val known = ConcurrentHashMap<String, String>()
        return observe(listener) {
            for (chat in chats(userId).filter { it.optBoolean("isGroup") }) {
                val chatId = chat.optString("id")
                val name = chat.optString("title", "Group")
                if (chatId.isNotBlank() && known.put(chatId, name) != name) onGroupAdded(chatId, name.ifBlank { "Group" })
            }
        }
    }

    suspend fun deleteMessage(chatId: String, messageId: String): Boolean = try {
        api(activeUid(), "DELETE", "/api/chat/messages/${segment(messageId)}")
        true
    } catch (e: Exception) { Log.e(TAG, "deleteMessage failed", e); false }

    fun observeMessages(
        chatId: String,
        onMessageReceived: (String, FirebaseMessageDto) -> Unit,
        onMessageDeletedFromServer: (String) -> Unit,
        onMessageUpdated: ((String, FirebaseMessageDto) -> Unit)? = null
    ): ChildEventListener {
        val listener = dummyListener()
        val known = ConcurrentHashMap<String, FirebaseMessageDto>()
        return observe(listener) {
            val uid = activeUid()
            val fresh = messages(uid, chatId).associate { it.optString("id") to message(it) }.filterKeys { it.isNotBlank() }
            fresh.forEach { (messageId, dto) ->
                val previous = known.put(messageId, dto)
                if (previous == null) onMessageReceived(messageId, dto)
                else if (previous != dto) onMessageUpdated?.invoke(messageId, dto)
            }
            val removed = known.keys.filter { it !in fresh.keys }
            removed.forEach { messageId ->
                known.remove(messageId)
                onMessageDeletedFromServer(messageId)
            }
        }
    }

    fun observeReactions(chatId: String, onReactionsUpdated: (targetMessageId: String, reactionsJson: String) -> Unit): ChildEventListener {
        val listener = dummyListener()
        val known = ConcurrentHashMap<String, String>()
        return observe(listener) {
            val uid = activeUid()
            for (message in messages(uid, chatId)) {
                val messageId = message.optString("id")
                if (messageId.isBlank()) continue
                val value = (message.optJSONObject("reactions") ?: JSONObject()).toString()
                if (known.put(messageId, value) != value) onReactionsUpdated(messageId, value)
            }
        }
    }

    fun removeReactionListener(chatId: String, listener: ChildEventListener) { listenerJobs.remove(listener)?.cancel() }
    fun removeMessageListener(chatId: String, listener: ChildEventListener) { listenerJobs.remove(listener)?.cancel() }
}
