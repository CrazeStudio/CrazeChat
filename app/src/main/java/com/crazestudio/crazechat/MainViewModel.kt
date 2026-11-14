package com.crazestudio.crazechat

import android.app.Application
import android.util.Base64
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.crazestudio.crazechat.data.ApiException
import com.crazestudio.crazechat.data.ChatMessage
import com.crazestudio.crazechat.data.ChatSummary
import com.crazestudio.crazechat.data.CrazeChatApi
import com.crazestudio.crazechat.data.ChatUser
import com.crazestudio.crazechat.security.CryptoService
import com.crazestudio.crazechat.security.IdentityMaterial
import com.crazestudio.crazechat.security.SecureVault
import com.google.firebase.installations.FirebaseInstallations
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

enum class AppPage { AUTH, INBOX, CHAT, PROFILE, SETTINGS, PRIVACY, STORAGE }

data class UiMessage(
    val id: String,
    val senderId: String,
    val text: String,
    val createdAt: Long,
    val deliveryState: String = "sent",
    val mine: Boolean
)

data class CrazeUiState(
    val ready: Boolean = false,
    val loading: Boolean = false,
    val page: AppPage = AppPage.AUTH,
    val signup: Boolean = false,
    val username: String = "",
    val userId: String? = null,
    val photoUrl: String? = null,
    val chats: List<ChatSummary> = emptyList(),
    val filteredChats: List<ChatSummary> = emptyList(),
    val search: String = "",
    val unreadOnly: Boolean = false,
    val currentChat: ChatSummary? = null,
    val messages: List<UiMessage> = emptyList(),
    val keyVerified: Boolean = false,
    val peerFingerprint: String? = null,
    val peerName: String? = null,
    val composing: Boolean = false,
    val notificationsEnabled: Boolean = true,
    val darkMode: Boolean = true,
    val language: String = "English",
    val storageBytes: Long = 0,
    val error: String? = null,
    val info: String? = null
)

class MainViewModel(application: Application) : AndroidViewModel(application) {
    private val appContext = application.applicationContext
    private val api = CrazeChatApi()
    private var vault = JSONObject()
    private var identityPrivate: ByteArray? = null
    private var currentChatKey: ByteArray? = null
    private var lastServerTimestamp: Long? = null
    private var realtime: WebSocket? = null
    private var pollJob: Job? = null
    private var activePageBeforeChat = AppPage.INBOX

    private val mutableState = kotlinx.coroutines.flow.MutableStateFlow(CrazeUiState())
    val state: kotlinx.coroutines.flow.StateFlow<CrazeUiState> = mutableState

    init {
        viewModelScope.launch {
            try {
                vault = withContext(Dispatchers.IO) { SecureVault.load(appContext) }
                api.token = vault.optString("token").takeIf { it.isNotBlank() }
                val username = vault.optString("username").takeIf { it.isNotBlank() }
                val userId = vault.optString("userId").takeIf { it.isNotBlank() }
                val photo = vault.optString("photoUrl").takeIf { it.isNotBlank() && it != "null" }
                val manuallyLocked = vault.optBoolean("manualLock", false)
                val savedPrivate = vault.optString("identityPrivateKey").takeIf { it.isNotBlank() }
                if (api.token != null && username != null && userId != null) {
                    mutableState.value = mutableState.value.copy(
                        username = username, userId = userId, photoUrl = photo,
                        page = if (manuallyLocked || savedPrivate == null) AppPage.AUTH else AppPage.INBOX,
                        signup = false
                    )
                    if (!manuallyLocked && savedPrivate != null) {
                        val bytes = Base64.decode(savedPrivate, Base64.DEFAULT)
                        val envelope = vault.optJSONObject("identityEnvelope")
                        if (envelope != null && bytes.size == 32) {
                            val derived = ByteArray(32)
                            org.bouncycastle.math.ec.rfc7748.X25519.generatePublicKey(bytes, 0, derived, 0)
                            if (MessageDigest.isEqual(derived, Base64.decode(envelope.getString("publicKey"), Base64.DEFAULT))) {
                                identityPrivate = bytes
                                refreshChats()
                            } else {
                                vault.remove("identityPrivateKey")
                                vault.put("manualLock", true)
                                saveVault()
                            }
                        }
                    }
                    if (api.token != null) {
                        runCatching { api.restoreSession() }.onFailure { error ->
                            if (error is ApiException && error.statusCode == 401) {
                                signOut(localOnly = true)
                            }
                        }
                    }
                }
                mutableState.value = mutableState.value.copy(
                    ready = true,
                    page = when {
                        api.token == null -> AppPage.AUTH
                        identityPrivate == null -> AppPage.AUTH
                        else -> AppPage.INBOX
                    },
                    notificationsEnabled = vault.optBoolean("notificationsEnabled", true),
                    darkMode = vault.optBoolean("darkMode", true),
                    language = vault.optString("language", "English")
                )
                updateStorageCount()
            } catch (error: Exception) {
                mutableState.value = mutableState.value.copy(
                    ready = true,
                    page = AppPage.AUTH,
                    error = "Could not open local secure storage: ${error.message ?: "unknown error"}"
                )
            }
        }
    }

    private suspend fun saveVault() {
        withContext(Dispatchers.IO) { SecureVault.save(appContext, vault) }
    }

    private fun reportError(message: String?) {
        mutableState.value = mutableState.value.copy(error = message)
    }

    fun consumeMessage() {
        mutableState.value = mutableState.value.copy(error = null, info = null)
    }

    fun setSignup(value: Boolean) {
        mutableState.value = mutableState.value.copy(signup = value, error = null)
    }

    fun authenticate(usernameInput: String, password: String, passphrase: String, signup: Boolean) {
        viewModelScope.launch {
            if (mutableState.value.loading) return@launch
            val username = usernameInput.trim()
            if (!Regex("^[a-zA-Z0-9_]{3,20}$").matches(username)) {
                reportError("Username must contain 3–20 letters, numbers or underscores.")
                return@launch
            }
            if (password.length < 12) {
                reportError("Use an account password with at least 12 characters.")
                return@launch
            }
            if (signup && (passphrase.length < 12 || passphrase == password)) {
                reportError("Use a different encryption passphrase with at least 12 characters.")
                return@launch
            }
            mutableState.value = mutableState.value.copy(loading = true, error = null)
            try {
                if (signup) {
                    val material = CryptoService.createIdentity(passphrase)
                    val result = api.register(username, password, material.envelope)
                    acceptSession(result, material)
                } else {
                    val result = api.login(username, password)
                    val user = result.getJSONObject("user")
                    val envelope = result.getJSONObject("identityEnvelope")
                    val savedId = user.optString("id")
                    val savedKey = vault.optString("identityPrivateKey").takeIf { it.isNotBlank() }
                    val material = if (savedKey != null && vault.optString("userId") == savedId) {
                        val privateBytes = Base64.decode(savedKey, Base64.DEFAULT)
                        val expectedPublic = Base64.decode(envelope.getString("publicKey"), Base64.DEFAULT)
                        val derivedPublic = ByteArray(32)
                        org.bouncycastle.math.ec.rfc7748.X25519.generatePublicKey(privateBytes, 0, derivedPublic, 0)
                        require(MessageDigest.isEqual(expectedPublic, derivedPublic)) {
                            "Saved identity does not match this account. Enter your encryption passphrase."
                        }
                        IdentityMaterial(privateBytes, expectedPublic, envelope)
                    } else {
                        val keyPassword = passphrase.ifBlank { password }
                        CryptoService.unlockIdentity(envelope, keyPassword)
                    }
                    acceptSession(result, material)
                }
            } catch (error: Exception) {
                reportError((error as? ApiException)?.message ?: error.message ?: "Authentication failed.")
            } finally {
                mutableState.value = mutableState.value.copy(loading = false)
            }
        }
    }

    private suspend fun acceptSession(result: JSONObject, material: IdentityMaterial) {
        val user = result.getJSONObject("user")
        val token = result.getString("token")
        api.token = token
        identityPrivate?.fill(0)
        identityPrivate = material.privateKey.copyOf()
        vault.put("token", token)
            .put("username", user.getString("username"))
            .put("userId", user.getString("id"))
            .put("photoUrl", user.optString("photoUrl"))
            .put("identityEnvelope", material.envelope)
            .put("identityPrivateKey", Base64.encodeToString(material.privateKey, Base64.NO_WRAP))
            .put("manualLock", false)
        saveVault()
        mutableState.value = mutableState.value.copy(
            page = AppPage.INBOX,
            username = user.getString("username"),
            userId = user.getString("id"),
            photoUrl = user.optString("photoUrl").takeIf { it.isNotBlank() && it != "null" },
            messages = emptyList(),
            currentChat = null
        )
        refreshChats()
        configurePush()
    }

    fun unlock(passphrase: String) {
        viewModelScope.launch {
            val envelope = vault.optJSONObject("identityEnvelope")
            if (envelope == null || passphrase.isEmpty()) {
                reportError("Enter the encryption passphrase for this account.")
                return@launch
            }
            mutableState.value = mutableState.value.copy(loading = true)
            try {
                val material = CryptoService.unlockIdentity(envelope, passphrase)
                identityPrivate?.fill(0)
                identityPrivate = material.privateKey.copyOf()
                vault.put("identityPrivateKey", Base64.encodeToString(material.privateKey, Base64.NO_WRAP))
                    .put("manualLock", false)
                saveVault()
                mutableState.value = mutableState.value.copy(page = AppPage.INBOX)
                refreshChats()
            } catch (_: Exception) {
                reportError("Incorrect encryption passphrase or damaged identity backup.")
            } finally {
                mutableState.value = mutableState.value.copy(loading = false)
            }
        }
    }

    fun lock() {
        closeRealtime()
        currentChatKey?.fill(0)
        currentChatKey = null
        identityPrivate?.fill(0)
        identityPrivate = null
        vault.remove("identityPrivateKey")
        vault.put("manualLock", true)
        viewModelScope.launch {
            saveVault()
            mutableState.value = mutableState.value.copy(
                page = AppPage.AUTH, currentChat = null, messages = emptyList(),
                keyVerified = false, peerFingerprint = null
            )
        }
    }

    fun signOut(localOnly: Boolean = false) {
        closeRealtime()
        identityPrivate?.fill(0)
        identityPrivate = null
        currentChatKey?.fill(0)
        currentChatKey = null
        api.token = null
        pollJob?.cancel()
        vault.remove("token")
        vault.remove("username")
        vault.remove("userId")
        vault.remove("photoUrl")
        vault.remove("identityEnvelope")
        vault.remove("identityPrivateKey")
        vault.remove("messageCache")
        vault.remove("trustedKeys")
        vault.put("manualLock", false)
        viewModelScope.launch {
            runCatching { if (!localOnly) saveVault() }
            if (localOnly) runCatching { saveVault() }
            mutableState.value = CrazeUiState(ready = true, page = AppPage.AUTH)
        }
    }

    fun refreshChats() {
        viewModelScope.launch {
            if (api.token.isNullOrBlank()) return@launch
            mutableState.value = mutableState.value.copy(loading = true)
            try {
                val result = api.listChats()
                val array = result.optJSONArray("chats") ?: JSONArray()
                val list = (0 until array.length()).mapNotNull { index ->
                    array.optJSONObject(index)?.let(ChatSummary::fromJson)
                }.sortedByDescending { it.updatedAt }
                mutableState.value = mutableState.value.copy(chats = list, loading = false)
                filterChats()
            } catch (error: Exception) {
                mutableState.value = mutableState.value.copy(loading = false)
                reportError((error as? ApiException)?.message ?: "Could not load conversations.")
            }
        }
    }

    fun setSearch(value: String) {
        mutableState.value = mutableState.value.copy(search = value)
        filterChats()
    }

    fun setUnreadOnly(value: Boolean) {
        mutableState.value = mutableState.value.copy(unreadOnly = value)
        filterChats()
    }

    private fun filterChats() {
        val current = mutableState.value
        val text = current.search.trim().lowercase()
        val filtered = current.chats.filter { chat ->
            val peer = chat.peer(current.userId.orEmpty())
            val matches = peer?.username?.lowercase()?.contains(text) == true
            val unread = unreadChatIds().contains(chat.id)
            matches && (!current.unreadOnly || unread)
        }
        mutableState.value = mutableState.value.copy(filteredChats = filtered)
    }

    private fun unreadChatIds(): Set<String> {
        val array = vault.optJSONArray("unreadChats") ?: JSONArray()
        return (0 until array.length()).mapNotNull { array.optString(it).takeIf(String::isNotBlank) }.toSet()
    }

    fun searchUsers(query: String, callback: (List<ChatUser>) -> Unit) {
        viewModelScope.launch {
            if (query.trim().length < 2 || !Regex("^[a-zA-Z0-9_]{2,20}$").matches(query.trim())) {
                callback(emptyList()); return@launch
            }
            try {
                val result = api.searchUsers(query.trim().lowercase())
                val array = result.optJSONArray("users") ?: JSONArray()
                callback((0 until array.length()).mapNotNull { array.optJSONObject(it)?.let(ChatUser::fromJson) })
            } catch (error: Exception) {
                reportError((error as? ApiException)?.message ?: "User search failed.")
                callback(emptyList())
            }
        }
    }

    fun startChat(username: String) {
        viewModelScope.launch {
            try {
                val result = api.createChat(username)
                val chatJson = result.optJSONObject("chat")
                    ?: throw IllegalStateException("The server did not return a conversation.")
                val chat = ChatSummary.fromJson(chatJson)
                val next = (mutableState.value.chats.filterNot { it.id == chat.id } + chat)
                mutableState.value = mutableState.value.copy(chats = next)
                filterChats()
                openChat(chat)
            } catch (error: Exception) {
                reportError((error as? ApiException)?.message ?: "Could not start this conversation.")
            }
        }
    }

    fun openChat(chat: ChatSummary) {
        val privateKey = identityPrivate
        val myId = mutableState.value.userId.orEmpty()
        val peer = chat.peer(myId)
        if (privateKey == null || peer == null || peer.publicKey.isBlank()) {
            reportError("This conversation is missing a valid encryption identity.")
            return
        }
        activePageBeforeChat = mutableState.value.page
        closeRealtime()
        currentChatKey?.fill(0)
        currentChatKey = null
        lastServerTimestamp = null
        val fingerprint = CryptoService.fingerprint(peer.publicKey)
        val savedFingerprint = vault.optJSONObject("trustedKeys")?.optString(peer.id)
        val verified = savedFingerprint == fingerprint
        mutableState.value = mutableState.value.copy(
            page = AppPage.CHAT, currentChat = chat, messages = emptyList(),
            keyVerified = verified, peerFingerprint = fingerprint, peerName = peer.username
        )
        viewModelScope.launch {
            try {
                currentChatKey = CryptoService.deriveChatKey(privateKey, peer.publicKey, chat.id)
                loadLocalMessages(chat.id)
                if (verified) {
                    loadRemoteMessages()
                    connectRealtime(chat.id)
                    startPolling(chat.id)
                }
            } catch (error: Exception) {
                reportError(error.message ?: "Could not prepare encrypted conversation.")
            }
        }
    }

    fun verifyPeerKey() {
        val chat = mutableState.value.currentChat ?: return
        val peer = chat.peer(mutableState.value.userId.orEmpty()) ?: return
        val fingerprint = mutableState.value.peerFingerprint ?: return
        vault.optJSONObject("trustedKeys")?.let { } // force validation before replacing an existing trust record
        val keys = vault.optJSONObject("trustedKeys") ?: JSONObject()
        keys.put(peer.id, fingerprint)
        vault.put("trustedKeys", keys)
        viewModelScope.launch {
            saveVault()
            mutableState.value = mutableState.value.copy(keyVerified = true, info = "Contact key verified on this device.")
            loadRemoteMessages()
            connectRealtime(chat.id)
            startPolling(chat.id)
        }
    }

    private fun cacheForChat(chatId: String): JSONArray {
        val all = vault.optJSONObject("messageCache") ?: JSONObject()
        val existing = all.optJSONArray(chatId) ?: JSONArray()
        return JSONArray(existing.toString())
    }

    private suspend fun saveEnvelope(chatId: String, message: JSONObject) {
        val all = vault.optJSONObject("messageCache") ?: JSONObject()
        val list = all.optJSONArray(chatId) ?: JSONArray()
        val id = message.optString("id")
        val newList = JSONArray()
        var found = false
        for (index in 0 until list.length()) {
            val item = list.optJSONObject(index) ?: continue
            if (item.optString("id") == id) {
                newList.put(message)
                found = true
            } else newList.put(item)
        }
        if (!found) newList.put(message)
        // Bound the local cache to the most recent 10,000 encrypted envelopes per conversation.
        val bounded = JSONArray()
        val start = (newList.length() - 10000).coerceAtLeast(0)
        for (index in start until newList.length()) bounded.put(newList.getJSONObject(index))
        all.put(chatId, bounded)
        vault.put("messageCache", all)
        saveVault()
        updateStorageCount()
    }

    private suspend fun loadLocalMessages(chatId: String) {
        val list = cacheForChat(chatId)
        val key = currentChatKey ?: return
        val rendered = mutableListOf<UiMessage>()
        for (index in 0 until list.length()) {
            val envelope = list.optJSONObject(index) ?: continue
            runCatching {
                val text = CryptoService.decryptMessage(envelope, key, chatId)
                val parsed = decodeTextPayload(text) ?: return@runCatching
                rendered += UiMessage(
                    envelope.getString("id"), envelope.getString("senderId"), parsed,
                    envelope.optLong("createdAt"), envelope.optString("deliveryState", "sent"),
                    envelope.optString("senderId") == mutableState.value.userId
                )
            }
        }
        mutableState.value = mutableState.value.copy(messages = rendered.sortedBy { it.createdAt })
    }

    private fun decodeTextPayload(clear: String): String? {
        return try {
            val payload = JSONObject(clear)
            when (payload.optString("__cc_type")) {
                "message" -> payload.optString("text", "")
                "reaction" -> null
                else -> clear
            }
        } catch (_: Exception) { clear }
    }

    private suspend fun processRemoteMessage(chatId: String, raw: JSONObject, acknowledgeRead: Boolean) {
        val id = raw.optString("id")
        val senderId = raw.optString("senderId")
        if (!Regex("^[a-f0-9]{32}$").matches(id) || senderId.isBlank()) return
        val key = currentChatKey ?: return
        val alreadyCached = cacheForChat(chatId).let { array ->
            (0 until array.length()).any { array.optJSONObject(it)?.optString("id") == id }
        }
        if (alreadyCached) return
        val clear = CryptoService.decryptMessage(raw, key, chatId)
        val text = decodeTextPayload(clear)
        val envelope = JSONObject(raw.toString()).put(
            "deliveryState", if (senderId == mutableState.value.userId) "sent" else "saved"
        )
        // CRITICAL: Persist encrypted envelope locally before read ACK. The server deletes
        // the message node after a successful read acknowledgement.
        saveEnvelope(chatId, envelope)
        if (text != null) {
            val item = UiMessage(
                id, senderId, text, raw.optLong("createdAt"),
                envelope.optString("deliveryState"),
                senderId == mutableState.value.userId
            )
            mutableState.value = mutableState.value.copy(
                messages = (mutableState.value.messages.filterNot { it.id == id } + item).sortedBy { it.createdAt }
            )
        }
        if (acknowledgeRead && senderId != mutableState.value.userId) {
            runCatching { api.acknowledgeMessages(chatId, listOf(id), "read") }
        }
    }

    private suspend fun loadRemoteMessages() {
        val chat = mutableState.value.currentChat ?: return
        if (!mutableState.value.keyVerified || currentChatKey == null) return
        try {
            val result = api.getMessages(chat.id, lastServerTimestamp?.minus(1)?.coerceAtLeast(0))
            val array = result.optJSONArray("messages") ?: JSONArray()
            val incomingIds = mutableListOf<String>()
            for (index in 0 until array.length()) {
                val message = array.optJSONObject(index) ?: continue
                val timestamp = message.optLong("createdAt")
                if (timestamp > 0 && (lastServerTimestamp == null || timestamp > lastServerTimestamp!!)) {
                    lastServerTimestamp = timestamp
                }
                if (message.optString("senderId") != mutableState.value.userId) {
                    incomingIds += message.optString("id")
                }
                processRemoteMessage(chat.id, message, acknowledgeRead = false)
            }
            // processRemoteMessage has saved each envelope. Only now may the server purge the payload.
            if (incomingIds.isNotEmpty()) {
                runCatching { api.acknowledgeMessages(chat.id, incomingIds, "read") }
            }
            retryQueued(chat.id)
        } catch (error: Exception) {
            if (error is ApiException) reportError(error.message)
        }
    }

    private suspend fun retryQueued(chatId: String) {
        val list = cacheForChat(chatId)
        for (index in 0 until list.length()) {
            val item = list.optJSONObject(index) ?: continue
            if (item.optString("senderId") != mutableState.value.userId || item.optString("deliveryState") != "queued") continue
            runCatching {
                val body = JSONObject()
                    .put("id", item.getString("id"))
                    .put("format", item.getString("format"))
                    .put("ciphertext", item.getString("ciphertext"))
                    .put("nonce", item.getString("nonce"))
                    .put("mac", item.getString("mac"))
                val response = api.sendMessage(chatId, body).getJSONObject("message")
                saveEnvelope(chatId, response.put("deliveryState", "sent"))
            }
        }
        loadLocalMessages(chatId)
    }

    private suspend fun connectRealtime(chatId: String) {
        closeRealtime()
        realtime = api.openRealtime(chatId, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                viewModelScope.launch {
                    runCatching {
                        val event = JSONObject(text)
                        when (event.optString("type")) {
                            "message" -> event.optJSONObject("message")?.let {
                                processRemoteMessage(chatId, it, acknowledgeRead = true)
                            }
                            "message_deleted" -> {
                                val ids = event.optJSONArray("messageIds") ?: JSONArray()
                                val current = mutableState.value.messages
                                mutableState.value = mutableState.value.copy(
                                    messages = current.map { item ->
                                        if (item.mine && (0 until ids.length()).any { ids.optString(it) == item.id }) item.copy(deliveryState = "read") else item
                                    }
                                )
                            }
                        }
                    }
                }
            }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                realtime = null
            }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                realtime = null
            }
        })
    }

    private fun closeRealtime() {
        realtime?.close(1000, "screen closed")
        realtime = null
        pollJob?.cancel()
        pollJob = null
    }

    private fun startPolling(chatId: String) {
        pollJob?.cancel()
        pollJob = viewModelScope.launch {
            while (isActive && mutableState.value.page == AppPage.CHAT &&
                mutableState.value.currentChat?.id == chatId) {
                delay(if (realtime == null) 5000 else 30000)
                if (mutableState.value.keyVerified) loadRemoteMessages()
                if (realtime == null && mutableState.value.keyVerified) runCatching { connectRealtime(chatId) }
            }
        }
    }

    fun sendMessage(textInput: String) {
        val text = textInput.trim()
        val chat = mutableState.value.currentChat ?: return
        val sender = mutableState.value.userId ?: return
        val key = currentChatKey ?: return
        if (!mutableState.value.keyVerified) {
            reportError("Verify the contact's fingerprint before sending messages.")
            return
        }
        if (text.isEmpty() || text.length > 1500 || mutableState.value.composing) return
        viewModelScope.launch {
            mutableState.value = mutableState.value.copy(composing = true)
            try {
                val payload = JSONObject()
                    .put("__cc_type", "message")
                    .put("text", text)
                    .put("replyTo", JSONObject.NULL)
                    .toString()
                val encrypted = CryptoService.encryptMessage(payload, key, chat.id, sender)
                val id = CryptoService.createMessageId()
                val now = System.currentTimeMillis()
                val queued = JSONObject(encrypted.toString())
                    .put("id", id)
                    .put("senderId", sender)
                    .put("createdAt", now)
                    .put("deliveryState", "queued")
                // Durable local encrypted outbox before network submission.
                saveEnvelope(chat.id, queued)
                val ui = UiMessage(id, sender, text, now, "queued", true)
                mutableState.value = mutableState.value.copy(
                    messages = mutableState.value.messages + ui
                )
                val response = api.sendMessage(chat.id, JSONObject()
                    .put("id", id)
                    .put("format", queued.getString("format"))
                    .put("ciphertext", queued.getString("ciphertext"))
                    .put("nonce", queued.getString("nonce"))
                    .put("mac", queued.getString("mac")))
                val serverMessage = response.getJSONObject("message")
                saveEnvelope(chat.id, serverMessage.put("deliveryState", "sent"))
                mutableState.value = mutableState.value.copy(
                    messages = mutableState.value.messages.map {
                        if (it.id == id) it.copy(createdAt = serverMessage.optLong("createdAt", now), deliveryState = "sent") else it
                    }
                )
            } catch (error: Exception) {
                reportError((error as? ApiException)?.message ?: "Message saved in the encrypted outbox; it will retry when connected.")
            } finally {
                mutableState.value = mutableState.value.copy(composing = false)
            }
        }
    }

    fun backFromChat() {
        closeRealtime()
        currentChatKey?.fill(0)
        currentChatKey = null
        mutableState.value = mutableState.value.copy(
            page = activePageBeforeChat.takeIf { it != AppPage.CHAT } ?: AppPage.INBOX,
            currentChat = null, messages = emptyList(), keyVerified = false,
            peerFingerprint = null, peerName = null
        )
        refreshChats()
    }

    fun openProfile() { mutableState.value = mutableState.value.copy(page = AppPage.PROFILE) }
    fun openSettings() { mutableState.value = mutableState.value.copy(page = AppPage.SETTINGS) }
    fun openPrivacy() { mutableState.value = mutableState.value.copy(page = AppPage.PRIVACY) }
    fun openStorage() { mutableState.value = mutableState.value.copy(page = AppPage.STORAGE); updateStorageCount() }
    fun backToInbox() { mutableState.value = mutableState.value.copy(page = AppPage.INBOX) }

    fun setDarkMode(value: Boolean) {
        mutableState.value = mutableState.value.copy(darkMode = value)
        vault.put("darkMode", value)
        viewModelScope.launch { saveVault() }
    }

    fun setNotificationsEnabled(value: Boolean) {
        mutableState.value = mutableState.value.copy(notificationsEnabled = value)
        vault.put("notificationsEnabled", value)
        viewModelScope.launch {
            saveVault()
            if (value) configurePush() else unregisterPush()
        }
    }

    private suspend fun configurePush() {
        if (!mutableState.value.notificationsEnabled || api.token.isNullOrBlank()) return
        runCatching {
            val fid = withContext(Dispatchers.IO) {
                com.google.android.gms.tasks.Tasks.await(FirebaseInstallations.getInstance().id)
            }
            api.registerPush(fid, sound = true, vibration = true)
        }
    }

    private suspend fun unregisterPush() {
        runCatching {
            val fid = withContext(Dispatchers.IO) {
                com.google.android.gms.tasks.Tasks.await(FirebaseInstallations.getInstance().id)
            }
            api.unregisterPush(fid)
        }
    }

    fun updateProfilePhoto(url: String) {
        viewModelScope.launch {
            try {
                val normalized = url.trim()
                require(normalized.startsWith("https://") && normalized.length <= 2048) {
                    "Profile photo must be a valid HTTPS URL."
                }
                val result = api.updatePhoto(normalized)
                val user = result.getJSONObject("user")
                val photo = user.optString("photoUrl").takeIf(String::isNotBlank)
                vault.put("photoUrl", photo)
                saveVault()
                mutableState.value = mutableState.value.copy(photoUrl = photo)
            } catch (error: Exception) {
                reportError((error as? ApiException)?.message ?: error.message ?: "Could not update profile photo.")
            }
        }
    }

    fun updateStorageCount() {
        viewModelScope.launch(Dispatchers.IO) {
            val prefs = appContext.getSharedPreferences("crazechat_secure_vault", 0)
            val bytes = prefs.getString("encrypted_v1", null)?.toByteArray()?.size?.toLong() ?: 0L
            mutableState.value = mutableState.value.copy(storageBytes = bytes)
        }
    }

    fun showInfo(message: String) {
        mutableState.value = mutableState.value.copy(info = message)
    }

    override fun onCleared() {
        closeRealtime()
        identityPrivate?.fill(0)
        currentChatKey?.fill(0)
        super.onCleared()
    }
}
