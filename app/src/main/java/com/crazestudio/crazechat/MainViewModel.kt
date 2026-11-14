package com.crazestudio.crazechat

import android.app.Application
import android.content.Context
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Base64
import androidx.documentfile.provider.DocumentFile
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.crazestudio.crazechat.data.ApiException
import com.crazestudio.crazechat.data.ChatSummary
import com.crazestudio.crazechat.data.CrazeChatApi
import com.crazestudio.crazechat.data.ChatUser
import com.crazestudio.crazechat.security.CryptoService
import com.crazestudio.crazechat.security.SecureVault
import com.google.firebase.installations.FirebaseInstallations
import com.google.android.gms.tasks.Tasks
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicLong

enum class AppPage { AUTH, INBOX, CHAT, PROFILE, SETTINGS, PRIVACY, STORAGE }

data class UiReply(val id: String, val senderId: String, val text: String)

data class UiMessage(
    val id: String,
    val senderId: String,
    val text: String,
    val createdAt: Long,
    val deliveryState: String = "sent",
    val mine: Boolean,
    val replyTo: UiReply? = null,
    val reactions: Map<String, String> = emptyMap()
)

data class SavedAccount(val userId: String, val username: String, val photoUrl: String?)

data class CrazeUiState(
    val ready: Boolean = false,
    val loading: Boolean = false,
    val refreshingChats: Boolean = false,
    val page: AppPage = AppPage.AUTH,
    val signup: Boolean = false,
    val username: String = "",
    val userId: String? = null,
    val photoUrl: String? = null,
    val chats: List<ChatSummary> = emptyList(),
    val filteredChats: List<ChatSummary> = emptyList(),
    val search: String = "",
    val currentChat: ChatSummary? = null,
    val messages: List<UiMessage> = emptyList(),
    val keyVerified: Boolean = false,
    val peerFingerprint: String? = null,
    val peerName: String? = null,
    val peerKeyChanged: Boolean = false,
    val composing: Boolean = false,
    val replyTarget: UiReply? = null,
    val chatSearch: String = "",
    val notificationsEnabled: Boolean = true,
    val soundEffectsEnabled: Boolean = true,
    val vibrationEnabled: Boolean = true,
    val screenSecureEnabled: Boolean = true,
    val themeMode: String = "dark",
    val savedAccounts: List<SavedAccount> = emptyList(),
    val needsPassphraseMigration: Boolean = false,
    val identityUsesSeparatePassphrase: Boolean = true,
    val storageBytes: Long = 0,
    val localFolderSelected: Boolean = false,
    val localSyncing: Boolean = false,
    val localSyncStatus: String? = null,
    val lastSyncAt: Long? = null,
    val bannerChatId: String? = null,
    val bannerName: String? = null,
    val bannerCount: Int = 0,
    val error: String? = null,
    val info: String? = null
)

private object CrazeSoundEffects {
    private var tone: ToneGenerator? = null

    fun play(incoming: Boolean) {
        runCatching {
            val generator = tone ?: ToneGenerator(AudioManager.STREAM_NOTIFICATION, 55).also { tone = it }
            generator.startTone(
                if (incoming) ToneGenerator.TONE_PROP_ACK else ToneGenerator.TONE_PROP_BEEP,
                if (incoming) 150 else 105
            )
        }
    }

    fun dispose() {
        runCatching { tone?.release() }
        tone = null
    }
}

class MainViewModel(application: Application) : AndroidViewModel(application) {
    private val appContext = application.applicationContext
    private val api = CrazeChatApi()
    private var vault = JSONObject()
    private var identityPrivate: ByteArray? = null
    private var currentChatKey: ByteArray? = null
    private var lastServerTimestamp: Long? = null
    private var realtime: WebSocket? = null
    private var pollJob: Job? = null
    private var autoSyncJob: Job? = null
    private var syncingArchive = false
    private var activePageBeforeChat = AppPage.INBOX
    private var bannerDismissJob: Job? = null
    private val bannerSerial = AtomicLong(0)

    private val mutableState = kotlinx.coroutines.flow.MutableStateFlow(CrazeUiState())
    val state: kotlinx.coroutines.flow.StateFlow<CrazeUiState> = mutableState

    init {
        viewModelScope.launch { PushEventBus.incoming.collectLatest { handleIncomingPush(it) } }
        viewModelScope.launch { PushEventBus.openChatRequests.collectLatest { openChatById(it) } }
        viewModelScope.launch {
            try {
                vault = withContext(Dispatchers.IO) { SecureVault.load(appContext) }
                api.token = vault.optString("token").takeIf { it.isNotBlank() }
                val username = vault.optString("username").takeIf { it.isNotBlank() }
                val userId = vault.optString("userId").takeIf { it.isNotBlank() }
                val photo = vault.optString("photoUrl").takeIf { it.isNotBlank() && it != "null" }
                val envelope = vault.optJSONObject("identityEnvelope")
                val manuallyLocked = vault.optBoolean("manualLock", false)
                val savedPrivate = if (manuallyLocked) null else privateKeyFor(userId)
                if (api.token != null && username != null && userId != null && envelope != null) {
                    if (savedPrivate != null) {
                        val bytes = Base64.decode(savedPrivate, Base64.DEFAULT)
                        if (bytes.size == 32 && MessageDigest.isEqual(
                                CryptoService.derivePublicKey(bytes),
                                Base64.decode(envelope.getString("publicKey"), Base64.DEFAULT)
                            )) {
                            identityPrivate = bytes
                        } else removePrivateKey(userId)
                    }
                    mutableState.value = mutableState.value.copy(
                        username = username,
                        userId = userId,
                        photoUrl = photo,
                        page = if (identityPrivate == null) AppPage.AUTH else AppPage.INBOX,
                        notificationsEnabled = vault.optBoolean("notificationsEnabled", true),
                        soundEffectsEnabled = vault.optBoolean("soundEffectsEnabled", true),
                        vibrationEnabled = vault.optBoolean("vibrationEnabled", true),
                        screenSecureEnabled = vault.optBoolean("screenSecureEnabled", true),
                        themeMode = vault.optString("themeMode", "dark"),
                        savedAccounts = savedAccountList(),
                        needsPassphraseMigration = envelope.optInt("version") != 2,
                        identityUsesSeparatePassphrase = envelope.optInt("version") == 2
                    )
                    if (identityPrivate != null) {
                        refreshChats()
                        restoreLocalSyncStatus()
                    }
                } else {
                    mutableState.value = mutableState.value.copy(
                        notificationsEnabled = vault.optBoolean("notificationsEnabled", true),
                        soundEffectsEnabled = vault.optBoolean("soundEffectsEnabled", true),
                        vibrationEnabled = vault.optBoolean("vibrationEnabled", true),
                        screenSecureEnabled = vault.optBoolean("screenSecureEnabled", true),
                        themeMode = vault.optString("themeMode", "dark"),
                        savedAccounts = savedAccountList()
                    )
                }
                mutableState.value = mutableState.value.copy(ready = true)
                updateStorageCount()
                if (api.token != null) {
                    viewModelScope.launch {
                        runCatching { api.restoreSession() }.onFailure { error ->
                            if (error is ApiException && error.statusCode == 401 &&
                                error.code != "UNAUTHORIZED" && error.code != "GATEWAY_NOT_CONFIGURED") {
                                clearActiveSession(keepSavedAccount = true)
                            }
                        }
                    }
                    configurePush()
                }
            } catch (error: Exception) {
                mutableState.value = mutableState.value.copy(
                    ready = true,
                    page = AppPage.AUTH,
                    error = "Could not open local secure storage: \${error.message ?: "unknown error"}"
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

    private fun privateKeys(): JSONObject = vault.optJSONObject("identityPrivateKeys") ?: JSONObject()

    private fun privateKeyFor(userId: String?): String? =
        userId?.let { privateKeys().optString(it).takeIf(String::isNotBlank) }

    private fun setPrivateKey(userId: String, privateKey: ByteArray) {
        val keys = privateKeys()
        keys.put(userId, Base64.encodeToString(privateKey, Base64.NO_WRAP))
        vault.put("identityPrivateKeys", keys)
    }

    private fun removePrivateKey(userId: String?) {
        if (userId == null) return
        val keys = privateKeys()
        keys.remove(userId)
        vault.put("identityPrivateKeys", keys)
    }

    private fun savedAccountList(): List<SavedAccount> {
        val array = vault.optJSONArray("accounts") ?: JSONArray()
        return (0 until array.length()).mapNotNull { index ->
            val item = array.optJSONObject(index) ?: return@mapNotNull null
            val id = item.optString("userId")
            val name = item.optString("username")
            if (id.isBlank() || name.isBlank()) null
            else SavedAccount(id, name, item.optString("photoUrl").takeIf { it.isNotBlank() && it != "null" })
        }
    }

    private fun saveAccountRecord(user: JSONObject) {
        val id = user.optString("id")
        val array = vault.optJSONArray("accounts") ?: JSONArray()
        val records = mutableListOf<JSONObject>()
        for (index in 0 until array.length()) {
            val item = array.optJSONObject(index) ?: continue
            if (item.optString("userId") != id) records.add(JSONObject(item.toString()))
        }
        val current = JSONObject()
            .put("userId", id)
            .put("username", user.optString("username"))
            .put("photoUrl", user.optString("photoUrl"))
            .put("token", vault.optString("token"))
            .put("identityEnvelope", vault.optJSONObject("identityEnvelope"))
        records.add(0, current)
        val bounded = JSONArray()
        records.take(2).forEach { bounded.put(it) }
        vault.put("accounts", bounded)
        mutableState.value = mutableState.value.copy(savedAccounts = savedAccountList())
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
                    CryptoService.validateIdentityEnvelope(envelope)
                    val savedId = user.getString("id")
                    val savedKey = privateKeyFor(savedId)
                    val material = if (savedKey != null) {
                        val privateBytes = Base64.decode(savedKey, Base64.DEFAULT)
                        val publicKey = CryptoService.derivePublicKey(privateBytes)
                        require(MessageDigest.isEqual(publicKey, Base64.decode(envelope.getString("publicKey"), Base64.DEFAULT))) {
                            "The saved identity does not match this account. Enter the encryption passphrase."
                        }
                        IdentityMaterial(privateBytes, publicKey, envelope)
                    } else {
                        CryptoService.unlockIdentity(envelope, passphrase.ifBlank { password })
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
        val userId = user.getString("id")
        vault.put("token", token)
            .put("username", user.getString("username"))
            .put("userId", userId)
            .put("photoUrl", user.optString("photoUrl"))
            .put("identityEnvelope", material.envelope)
            .put("manualLock", false)
        setPrivateKey(userId, material.privateKey)
        saveAccountRecord(user)
        saveVault()
        mutableState.value = mutableState.value.copy(
            page = AppPage.INBOX,
            username = user.getString("username"),
            userId = userId,
            photoUrl = user.optString("photoUrl").takeIf { it.isNotBlank() && it != "null" },
            messages = emptyList(),
            currentChat = null,
            savedAccounts = savedAccountList(),
            needsPassphraseMigration = material.envelope.optInt("version") != 2,
            identityUsesSeparatePassphrase = material.envelope.optInt("version") == 2,
            bannerChatId = null
        )
        refreshChats()
        restoreLocalSyncStatus()
        configurePush()
    }

    fun unlock(passphrase: String) {
        viewModelScope.launch {
            val envelope = vault.optJSONObject("identityEnvelope")
            val uid = vault.optString("userId").takeIf(String::isNotBlank)
            if (envelope == null || uid == null || passphrase.isEmpty()) {
                reportError("Enter the passphrase for this account's identity key.")
                return@launch
            }
            mutableState.value = mutableState.value.copy(loading = true)
            try {
                val material = CryptoService.unlockIdentity(envelope, passphrase)
                identityPrivate?.fill(0)
                identityPrivate = material.privateKey.copyOf()
                setPrivateKey(uid, material.privateKey)
                vault.put("manualLock", false)
                saveVault()
                mutableState.value = mutableState.value.copy(
                    page = AppPage.INBOX,
                    needsPassphraseMigration = envelope.optInt("version") != 2,
                    identityUsesSeparatePassphrase = envelope.optInt("version") == 2
                )
                refreshChats()
                configurePush()
                syncIfEnabled()
            } catch (_: Exception) {
                reportError("Incorrect passphrase or damaged encrypted identity backup.")
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
        vault.put("manualLock", true)
        autoSyncJob?.cancel()
        viewModelScope.launch {
            saveVault()
            mutableState.value = mutableState.value.copy(
                page = AppPage.AUTH,
                currentChat = null,
                messages = emptyList(),
                keyVerified = false,
                peerFingerprint = null,
                replyTarget = null,
                bannerChatId = null
            )
        }
    }

    private suspend fun clearActiveSession(keepSavedAccount: Boolean) {
        val uid = vault.optString("userId").takeIf(String::isNotBlank)
        identityPrivate?.fill(0)
        identityPrivate = null
        currentChatKey?.fill(0)
        currentChatKey = null
        closeRealtime()
        if (!keepSavedAccount) {
            removePrivateKey(uid)
            val accounts = vault.optJSONArray("accounts") ?: JSONArray()
            val remaining = JSONArray()
            for (i in 0 until accounts.length()) {
                val item = accounts.optJSONObject(i) ?: continue
                if (item.optString("userId") != uid) remaining.put(item)
            }
            vault.put("accounts", remaining)
        }
        vault.remove("token")
        vault.remove("username")
        vault.remove("userId")
        vault.remove("photoUrl")
        vault.remove("identityEnvelope")
        vault.put("manualLock", false)
        api.token = null
        saveVault()
        mutableState.value = CrazeUiState(ready = true, page = AppPage.AUTH, savedAccounts = savedAccountList())
    }

    fun signOut() {
        viewModelScope.launch {
            unregisterPush()
            clearActiveSession(keepSavedAccount = false)
        }
    }

    fun addAccount() {
        viewModelScope.launch {
            unregisterPush()
            clearActiveSession(keepSavedAccount = true)
            mutableState.value = mutableState.value.copy(page = AppPage.AUTH)
        }
    }

    fun switchAccount(targetId: String) {
        viewModelScope.launch {
            unregisterPush()
            val accounts = vault.optJSONArray("accounts") ?: JSONArray()
            val target = (0 until accounts.length()).mapNotNull { accounts.optJSONObject(it) }
                .firstOrNull { it.optString("userId") == targetId }
            if (target == null) {
                reportError("That saved account is no longer available on this device.")
                return@launch
            }
            identityPrivate?.fill(0)
            currentChatKey?.fill(0)
            closeRealtime()
            api.token = target.optString("token")
            val envelope = target.optJSONObject("identityEnvelope")
            vault.put("token", target.optString("token"))
                .put("username", target.optString("username"))
                .put("userId", targetId)
                .put("photoUrl", target.optString("photoUrl"))
                .put("identityEnvelope", envelope)
                .put("manualLock", false)
            identityPrivate = privateKeyFor(targetId)?.let { Base64.decode(it, Base64.DEFAULT) }
            val validPrivate = identityPrivate?.let { privateKey ->
                envelope != null && privateKey.size == 32 &&
                    MessageDigest.isEqual(CryptoService.derivePublicKey(privateKey), Base64.decode(envelope.getString("publicKey"), Base64.DEFAULT))
            } == true
            if (!validPrivate) identityPrivate = null
            saveVault()
            mutableState.value = CrazeUiState(
                ready = true,
                page = if (validPrivate) AppPage.INBOX else AppPage.AUTH,
                username = target.optString("username"),
                userId = targetId,
                photoUrl = target.optString("photoUrl").takeIf { it.isNotBlank() && it != "null" },
                savedAccounts = savedAccountList(),
                notificationsEnabled = vault.optBoolean("notificationsEnabled", true),
                soundEffectsEnabled = vault.optBoolean("soundEffectsEnabled", true),
                vibrationEnabled = vault.optBoolean("vibrationEnabled", true),
                screenSecureEnabled = vault.optBoolean("screenSecureEnabled", true),
                themeMode = vault.optString("themeMode", "dark"),
                needsPassphraseMigration = envelope?.optInt("version") != 2,
                identityUsesSeparatePassphrase = envelope?.optInt("version") == 2
            )
            if (validPrivate) {
                refreshChats()
                configurePush()
                restoreLocalSyncStatus()
            }
        }
    }

    fun refreshChats(silent: Boolean = false) {
        viewModelScope.launch {
            if (api.token.isNullOrBlank()) return@launch
            val showBlocking = mutableState.value.chats.isEmpty()
            mutableState.value = mutableState.value.copy(loading = showBlocking, refreshingChats = true)
            try {
                val result = api.listChats()
                val array = result.optJSONArray("chats") ?: JSONArray()
                val list = (0 until array.length()).mapNotNull { index ->
                    array.optJSONObject(index)?.let(ChatSummary::fromJson)
                }.sortedByDescending { it.updatedAt }
                mutableState.value = mutableState.value.copy(chats = list, loading = false, refreshingChats = false)
                filterChats()
            } catch (error: Exception) {
                mutableState.value = mutableState.value.copy(loading = false, refreshingChats = false)
                if (!silent) reportError((error as? ApiException)?.message ?: "Could not load conversations.")
            }
        }
    }

    fun setSearch(value: String) {
        mutableState.value = mutableState.value.copy(search = value)
        filterChats()
    }

    private fun filterChats() {
        val current = mutableState.value
        val text = current.search.trim().lowercase()
        val filtered = current.chats.filter { chat ->
            chat.peer(current.userId.orEmpty())?.username?.lowercase()?.contains(text) == true
        }
        mutableState.value = mutableState.value.copy(filteredChats = filtered)
    }

    fun searchUsers(query: String, callback: (List<ChatUser>) -> Unit) {
        viewModelScope.launch {
            if (query.trim().length < 2 || !Regex("^[a-zA-Z0-9_]{2,20}$").matches(query.trim())) {
                callback(emptyList())
                return@launch
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
                val chatJson = result.optJSONObject("chat") ?: throw IllegalStateException("The server did not return a conversation.")
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

    fun openChatById(chatId: String) {
        viewModelScope.launch {
            if (mutableState.value.chats.none { it.id == chatId }) {
                runCatching {
                    val result = api.listChats()
                    val array = result.optJSONArray("chats") ?: JSONArray()
                    val chats = (0 until array.length()).mapNotNull { array.optJSONObject(it)?.let(ChatSummary::fromJson) }
                    mutableState.value = mutableState.value.copy(chats = chats)
                }
            }
            mutableState.value.chats.firstOrNull { it.id == chatId }?.let(::openChat)
                ?: reportError("Open CrazeChat to sync this conversation.")
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
            page = AppPage.CHAT,
            currentChat = chat,
            messages = emptyList(),
            keyVerified = verified,
            peerFingerprint = fingerprint,
            peerName = peer.username,
            peerKeyChanged = savedFingerprint != null && !verified,
            replyTarget = null,
            chatSearch = ""
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
        val keys = vault.optJSONObject("trustedKeys") ?: JSONObject()
        keys.put(peer.id, fingerprint)
        vault.put("trustedKeys", keys)
        viewModelScope.launch {
            saveVault()
            mutableState.value = mutableState.value.copy(
                keyVerified = true,
                peerKeyChanged = false,
                info = "Contact key verified on this device."
            )
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

    private fun tombstonesForChat(chatId: String): MutableSet<String> {
        val all = vault.optJSONObject("messageTombstones") ?: JSONObject()
        val array = all.optJSONArray(chatId) ?: JSONArray()
        return (0 until array.length()).mapNotNull { array.optString(it).takeIf(String::isNotBlank) }.toMutableSet()
    }

    private suspend fun saveEnvelope(chatId: String, message: JSONObject) {
        val id = message.optString("id")
        if (id.isBlank() || tombstonesForChat(chatId).contains(id)) return
        val all = vault.optJSONObject("messageCache") ?: JSONObject()
        val list = cacheForChat(chatId)
        val replacement = JSONArray()
        var found = false
        for (index in 0 until list.length()) {
            val item = list.optJSONObject(index) ?: continue
            if (item.optString("id") == id) {
                replacement.put(message)
                found = true
            } else replacement.put(item)
        }
        if (!found) replacement.put(message)
        val bounded = JSONArray()
        val start = (replacement.length() - 10000).coerceAtLeast(0)
        for (index in start until replacement.length()) bounded.put(replacement.getJSONObject(index))
        all.put(chatId, bounded)
        vault.put("messageCache", all)
        saveVault()
        updateStorageCount()
        scheduleAutomaticFolderSync()
    }

    private suspend fun removeCachedMessage(chatId: String, messageId: String, recordTombstone: Boolean) {
        val all = vault.optJSONObject("messageCache") ?: JSONObject()
        val old = cacheForChat(chatId)
        val next = JSONArray()
        for (index in 0 until old.length()) {
            val item = old.optJSONObject(index) ?: continue
            if (item.optString("id") != messageId) next.put(item)
        }
        all.put(chatId, next)
        vault.put("messageCache", all)
        if (recordTombstone) {
            val allTombstones = vault.optJSONObject("messageTombstones") ?: JSONObject()
            val ids = tombstonesForChat(chatId)
            ids.add(messageId)
            allTombstones.put(chatId, JSONArray(ids.toList()))
            vault.put("messageTombstones", allTombstones)
        }
        saveVault()
        scheduleAutomaticFolderSync()
    }

    private data class DecodedPayload(
        val type: String,
        val text: String = "",
        val replyTo: UiReply? = null,
        val targetId: String? = null,
        val emoji: String = ""
    )

    private fun decodePayload(clear: String): DecodedPayload {
        return try {
            val payload = JSONObject(clear)
            when (payload.optString("__cc_type")) {
                "reaction" -> DecodedPayload(
                    type = "reaction",
                    targetId = payload.optString("targetId").takeIf(String::isNotBlank),
                    emoji = payload.optString("emoji")
                )
                "message" -> {
                    val quote = payload.optJSONObject("replyTo")
                    DecodedPayload(
                        type = "message",
                        text = payload.optString("text"),
                        replyTo = quote?.let {
                            UiReply(it.optString("id"), it.optString("senderId"), it.optString("text"))
                        }
                    )
                }
                else -> DecodedPayload("message", clear)
            }
        } catch (_: Exception) {
            DecodedPayload("message", clear)
        }
    }

    private suspend fun loadLocalMessages(chatId: String) {
        val list = cacheForChat(chatId)
        val key = currentChatKey ?: return
        val reactions = mutableMapOf<String, MutableMap<String, String>>()
        val rendered = mutableListOf<UiMessage>()
        val sorted = (0 until list.length()).mapNotNull { list.optJSONObject(it) }.sortedBy { it.optLong("createdAt") }
        for (envelope in sorted) {
            runCatching {
                val clear = CryptoService.decryptMessage(envelope, key, chatId)
                val parsed = decodePayload(clear)
                val senderId = envelope.optString("senderId")
                if (parsed.type == "reaction") {
                    val targetId = parsed.targetId ?: return@runCatching
                    val byUser = reactions.getOrPut(targetId) { mutableMapOf() }
                    if (parsed.emoji.isBlank()) byUser.remove(senderId) else byUser[senderId] = parsed.emoji
                } else {
                    rendered += UiMessage(
                        id = envelope.getString("id"),
                        senderId = senderId,
                        text = parsed.text,
                        createdAt = envelope.optLong("createdAt"),
                        deliveryState = envelope.optString("deliveryState", "sent"),
                        mine = senderId == mutableState.value.userId,
                        replyTo = parsed.replyTo
                    )
                }
            }
        }
        val complete = rendered.map { it.copy(reactions = reactions[it.id]?.toMap().orEmpty()) }
        mutableState.value = mutableState.value.copy(messages = complete.sortedBy { it.createdAt })
    }

    private suspend fun processRemoteMessage(chatId: String, raw: JSONObject, acknowledgeRead: Boolean) {
        val id = raw.optString("id")
        val senderId = raw.optString("senderId")
        if (!Regex("^[a-f0-9]{32}$").matches(id) || senderId.isBlank()) return
        if (tombstonesForChat(chatId).contains(id)) return
        val key = currentChatKey ?: return
        val alreadyCached = cacheForChat(chatId).let { array ->
            (0 until array.length()).any { array.optJSONObject(it)?.optString("id") == id }
        }
        if (alreadyCached) return
        val clear = CryptoService.decryptMessage(raw, key, chatId)
        val payload = decodePayload(clear)
        val envelope = JSONObject(raw.toString()).put("deliveryState", if (senderId == mutableState.value.userId) "sent" else "saved")
        // The encrypted envelope is durable before a read ACK purges the server copy.
        saveEnvelope(chatId, envelope)
        if (payload.type == "reaction") {
            val targetId = payload.targetId
            if (targetId != null) {
                mutableState.value = mutableState.value.copy(
                    messages = mutableState.value.messages.map { item ->
                        if (item.id == targetId) {
                            val reactions = item.reactions.toMutableMap()
                            if (payload.emoji.isBlank()) reactions.remove(senderId) else reactions[senderId] = payload.emoji
                            item.copy(reactions = reactions)
                        } else item
                    }
                )
            }
        } else {
            val item = UiMessage(
                id = id,
                senderId = senderId,
                text = payload.text,
                createdAt = raw.optLong("createdAt"),
                deliveryState = envelope.optString("deliveryState"),
                mine = senderId == mutableState.value.userId,
                replyTo = payload.replyTo
            )
            mutableState.value = mutableState.value.copy(
                messages = (mutableState.value.messages.filterNot { it.id == id } + item).sortedBy { it.createdAt }
            )
            if (senderId != mutableState.value.userId) {
                if (mutableState.value.soundEffectsEnabled) CrazeSoundEffects.play(incoming = true)
                if (mutableState.value.vibrationEnabled) vibrate()
            }
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
                if (timestamp > 0 && (lastServerTimestamp == null || timestamp > lastServerTimestamp!!)) lastServerTimestamp = timestamp
                if (message.optString("senderId") != mutableState.value.userId) incomingIds += message.optString("id")
                processRemoteMessage(chat.id, message, acknowledgeRead = false)
            }
            // Every message is cached above before the server is asked to purge it.
            if (incomingIds.isNotEmpty()) runCatching { api.acknowledgeMessages(chat.id, incomingIds, "read") }
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
                response.put("deliveryState", "sent")
                saveEnvelope(chatId, response)
            }
        }
        loadLocalMessages(chatId)
    }

    private suspend fun connectRealtime(chatId: String) {
        realtime?.close(1000, "reconnecting")
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
                                val readIds = (0 until ids.length()).map { ids.optString(it) }.toSet()
                                mutableState.value = mutableState.value.copy(
                                    messages = mutableState.value.messages.map { item ->
                                        if (item.mine && readIds.contains(item.id)) item.copy(deliveryState = "read") else item
                                    }
                                )
                            }
                        }
                    }
                }
            }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) { realtime = null }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) { realtime = null }
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
            while (isActive && mutableState.value.page == AppPage.CHAT && mutableState.value.currentChat?.id == chatId) {
                delay(if (realtime == null) 5000 else 30000)
                if (mutableState.value.keyVerified) loadRemoteMessages()
                if (realtime == null && mutableState.value.keyVerified) runCatching { connectRealtime(chatId) }
            }
        }
    }

    fun setReplyTarget(message: UiMessage) {
        mutableState.value = mutableState.value.copy(replyTarget = UiReply(message.id, message.senderId, message.text))
    }

    fun clearReplyTarget() { mutableState.value = mutableState.value.copy(replyTarget = null) }
    fun setChatSearch(value: String) { mutableState.value = mutableState.value.copy(chatSearch = value) }

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
        val reply = mutableState.value.replyTarget
        viewModelScope.launch {
            mutableState.value = mutableState.value.copy(composing = true)
            try {
                val payload = JSONObject()
                    .put("__cc_type", "message")
                    .put("text", text)
                    .put("replyTo", reply?.let {
                        JSONObject().put("id", it.id).put("senderId", it.senderId).put("text", it.text)
                    } ?: JSONObject.NULL)
                    .toString()
                val encrypted = CryptoService.encryptMessage(payload, key, chat.id, sender)
                val id = CryptoService.createMessageId()
                val now = System.currentTimeMillis()
                val queued = JSONObject(encrypted.toString())
                    .put("id", id).put("senderId", sender).put("createdAt", now).put("deliveryState", "queued")
                saveEnvelope(chat.id, queued)
                val ui = UiMessage(id, sender, text, now, "queued", true, replyTo = reply)
                mutableState.value = mutableState.value.copy(messages = mutableState.value.messages + ui, replyTarget = null)
                if (mutableState.value.soundEffectsEnabled) CrazeSoundEffects.play(incoming = false)
                if (mutableState.value.vibrationEnabled) vibrate()
                try {
                    val response = api.sendMessage(chat.id, JSONObject()
                        .put("id", id).put("format", queued.getString("format"))
                        .put("ciphertext", queued.getString("ciphertext"))
                        .put("nonce", queued.getString("nonce")).put("mac", queued.getString("mac")))
                    val serverMessage = response.getJSONObject("message").put("deliveryState", "sent")
                    saveEnvelope(chat.id, serverMessage)
                    mutableState.value = mutableState.value.copy(messages = mutableState.value.messages.map {
                        if (it.id == id) it.copy(createdAt = serverMessage.optLong("createdAt", now), deliveryState = "sent") else it
                    })
                } catch (_: Exception) {
                    reportError("Saved to your encrypted outbox. CrazeChat will retry when the connection returns.")
                }
            } catch (error: Exception) {
                reportError(error.message ?: "Could not encrypt the message.")
            } finally {
                mutableState.value = mutableState.value.copy(composing = false)
            }
        }
    }

    fun reactToMessage(message: UiMessage, emoji: String) {
        val chat = mutableState.value.currentChat ?: return
        val sender = mutableState.value.userId ?: return
        val key = currentChatKey ?: return
        if (!mutableState.value.keyVerified) {
            reportError("Verify this contact's fingerprint before sending reactions.")
            return
        }
        viewModelScope.launch {
            val nextEmoji = if (message.reactions[sender] == emoji) "" else emoji
            try {
                val payload = JSONObject().put("__cc_type", "reaction").put("targetId", message.id).put("emoji", nextEmoji).toString()
                val encrypted = CryptoService.encryptMessage(payload, key, chat.id, sender)
                val id = CryptoService.createMessageId()
                val queued = JSONObject(encrypted.toString())
                    .put("id", id).put("senderId", sender).put("createdAt", System.currentTimeMillis()).put("deliveryState", "queued")
                saveEnvelope(chat.id, queued)
                mutableState.value = mutableState.value.copy(messages = mutableState.value.messages.map { item ->
                    if (item.id == message.id) {
                        val reactions = item.reactions.toMutableMap()
                        if (nextEmoji.isBlank()) reactions.remove(sender) else reactions[sender] = nextEmoji
                        item.copy(reactions = reactions)
                    } else item
                })
                val response = api.sendMessage(chat.id, JSONObject()
                    .put("id", id).put("format", queued.getString("format"))
                    .put("ciphertext", queued.getString("ciphertext"))
                    .put("nonce", queued.getString("nonce")).put("mac", queued.getString("mac")))
                response.optJSONObject("message")?.let { it.put("deliveryState", "sent"); saveEnvelope(chat.id, it) }
            } catch (_: Exception) {
                reportError("Reaction saved in the encrypted outbox and will retry when connected.")
            }
        }
    }

    fun deleteMessage(message: UiMessage) {
        val chat = mutableState.value.currentChat ?: return
        if (!message.mine) return
        viewModelScope.launch {
            try {
                api.deleteMessage(chat.id, message.id)
                removeCachedMessage(chat.id, message.id, recordTombstone = true)
                mutableState.value = mutableState.value.copy(
                    messages = mutableState.value.messages.filterNot { it.id == message.id },
                    info = "Message deleted."
                )
            } catch (error: Exception) {
                reportError((error as? ApiException)?.message ?: "Could not delete this message.")
            }
        }
    }

    fun backFromChat() {
        closeRealtime()
        currentChatKey?.fill(0)
        currentChatKey = null
        mutableState.value = mutableState.value.copy(
            page = activePageBeforeChat.takeIf { it != AppPage.CHAT } ?: AppPage.INBOX,
            currentChat = null,
            messages = emptyList(),
            keyVerified = false,
            peerFingerprint = null,
            peerKeyChanged = false,
            peerName = null,
            replyTarget = null,
            chatSearch = ""
        )
        refreshChats(silent = true)
    }

    fun openProfile() { mutableState.value = mutableState.value.copy(page = AppPage.PROFILE) }
    fun openSettings() { mutableState.value = mutableState.value.copy(page = AppPage.SETTINGS) }
    fun openPrivacy() { mutableState.value = mutableState.value.copy(page = AppPage.PRIVACY) }
    fun openStorage() { mutableState.value = mutableState.value.copy(page = AppPage.STORAGE); updateStorageCount() }
    fun backToInbox() { mutableState.value = mutableState.value.copy(page = AppPage.INBOX) }

    fun setThemeMode(value: String) {
        if (value !in setOf("system", "light", "dark")) return
        mutableState.value = mutableState.value.copy(themeMode = value)
        vault.put("themeMode", value)
        viewModelScope.launch { saveVault() }
    }

    fun setScreenSecure(value: Boolean) {
        mutableState.value = mutableState.value.copy(screenSecureEnabled = value)
        vault.put("screenSecureEnabled", value)
        viewModelScope.launch { saveVault() }
    }

    fun setNotificationsEnabled(value: Boolean) {
        mutableState.value = mutableState.value.copy(notificationsEnabled = value)
        vault.put("notificationsEnabled", value)
        viewModelScope.launch { saveVault(); if (value) configurePush() else unregisterPush() }
    }

    fun setSoundEffectsEnabled(value: Boolean) {
        mutableState.value = mutableState.value.copy(soundEffectsEnabled = value)
        vault.put("soundEffectsEnabled", value)
        viewModelScope.launch { saveVault(); refreshPushPreferences() }
    }

    fun setVibrationEnabled(value: Boolean) {
        mutableState.value = mutableState.value.copy(vibrationEnabled = value)
        vault.put("vibrationEnabled", value)
        viewModelScope.launch { saveVault(); refreshPushPreferences() }
    }

    private fun pushFids(): JSONObject = vault.optJSONObject("pushFids") ?: JSONObject()

    private suspend fun currentPushFid(): String? {
        val uid = mutableState.value.userId ?: return null
        val stored = pushFids().optString(uid).takeIf(String::isNotBlank)
        if (stored != null) return stored
        val fid = withContext(Dispatchers.IO) { Tasks.await(FirebaseInstallations.getInstance().id) }
        pushFids().put(uid, fid)
        vault.put("pushFids", pushFids())
        saveVault()
        return fid
    }

    private suspend fun configurePush() {
        if (!mutableState.value.notificationsEnabled || api.token.isNullOrBlank()) return
        runCatching {
            val fid = currentPushFid() ?: return@runCatching
            api.registerPush(fid, sound = mutableState.value.soundEffectsEnabled, vibration = mutableState.value.vibrationEnabled)
        }
    }

    private suspend fun refreshPushPreferences() {
        if (!mutableState.value.notificationsEnabled || api.token.isNullOrBlank()) return
        runCatching {
            val fid = currentPushFid() ?: return@runCatching
            api.registerPush(fid, sound = mutableState.value.soundEffectsEnabled, vibration = mutableState.value.vibrationEnabled)
        }
    }

    private suspend fun unregisterPush() {
        runCatching {
            val fid = currentPushFid() ?: return@runCatching
            api.unregisterPush(fid)
        }
    }

    private fun vibrate() {
        runCatching {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                appContext.getSystemService(VibratorManager::class.java).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                appContext.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (!vibrator.hasVibrator()) return@runCatching
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) vibrator.vibrate(VibrationEffect.createOneShot(35, VibrationEffect.DEFAULT_AMPLITUDE))
            else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(35)
            }
        }
    }

    fun updateProfilePhoto(url: String?) {
        viewModelScope.launch {
            try {
                val normalized = url?.trim()?.takeIf(String::isNotBlank)
                require(normalized == null || (normalized.startsWith("https://") && normalized.length <= 2048)) {
                    "Profile photo must be a valid HTTPS URL."
                }
                val result = api.updatePhoto(normalized)
                val user = result.getJSONObject("user")
                val photo = user.optString("photoUrl").takeIf { it.isNotBlank() && it != "null" }
                vault.put("photoUrl", photo)
                val accounts = vault.optJSONArray("accounts") ?: JSONArray()
                val updated = JSONArray()
                for (i in 0 until accounts.length()) {
                    val item = accounts.optJSONObject(i) ?: continue
                    val copy = JSONObject(item.toString())
                    if (copy.optString("userId") == mutableState.value.userId) copy.put("photoUrl", photo)
                    updated.put(copy)
                }
                vault.put("accounts", updated)
                saveVault()
                mutableState.value = mutableState.value.copy(photoUrl = photo, savedAccounts = savedAccountList())
            } catch (error: Exception) {
                reportError((error as? ApiException)?.message ?: error.message ?: "Could not update profile photo.")
            }
        }
    }

    fun changePassword(currentPassword: String, newPassword: String, confirmation: String) {
        viewModelScope.launch {
            val privateKey = identityPrivate
            val userId = mutableState.value.userId
            if (privateKey == null || userId == null || vault.optJSONObject("identityEnvelope") == null) {
                reportError("Unlock your identity before changing the password.")
                return@launch
            }
            if (newPassword.length < 12 || newPassword != confirmation || newPassword == currentPassword) {
                reportError("Use a different password with at least 12 characters and confirm it.")
                return@launch
            }
            mutableState.value = mutableState.value.copy(loading = true)
            try {
                // The current Worker requires an account-password-v3 envelope
                // on this endpoint, so the new password also unlocks the key.
                val publicKey = CryptoService.derivePublicKey(privateKey)
                val material = CryptoService.rewrapIdentity(privateKey, publicKey, newPassword, separatePassphrase = false)
                api.changePassword(currentPassword, newPassword, material.envelope)
                vault.put("identityEnvelope", material.envelope)
                saveAccountRecord(JSONObject().put("id", userId)
                    .put("username", mutableState.value.username)
                    .put("photoUrl", mutableState.value.photoUrl))
                saveVault()
                mutableState.value = mutableState.value.copy(
                    needsPassphraseMigration = true,
                    identityUsesSeparatePassphrase = false,
                    info = "Password updated. The new account password now unlocks the identity key."
                )
            } catch (error: Exception) {
                reportError((error as? ApiException)?.message ?: error.message ?: "Password update failed. Your old password remains active.")
            } finally {
                mutableState.value = mutableState.value.copy(loading = false)
            }
        }
    }

    fun updateEncryptionPassphrase(newPassphrase: String, confirmation: String) {
        viewModelScope.launch {
            val privateKey = identityPrivate
            val uid = mutableState.value.userId
            if (privateKey == null || uid == null) {
                reportError("Unlock your identity before changing its encryption passphrase.")
                return@launch
            }
            if (newPassphrase.length < 12 || newPassphrase != confirmation) {
                reportError("Use at least 12 characters and confirm the same passphrase.")
                return@launch
            }
            try {
                val publicKey = CryptoService.derivePublicKey(privateKey)
                val material = CryptoService.rewrapIdentity(privateKey, publicKey, newPassphrase, separatePassphrase = true)
                api.updateIdentityEnvelope(material.envelope)
                vault.put("identityEnvelope", material.envelope)
                saveAccountRecord(JSONObject().put("id", uid)
                    .put("username", mutableState.value.username)
                    .put("photoUrl", mutableState.value.photoUrl))
                saveVault()
                mutableState.value = mutableState.value.copy(
                    needsPassphraseMigration = false,
                    identityUsesSeparatePassphrase = true,
                    info = "Separate encryption passphrase updated. Keep it somewhere safe."
                )
            } catch (error: Exception) {
                reportError((error as? ApiException)?.message ?: error.message ?: "Could not update the encryption passphrase.")
            }
        }
    }

    // ---- Encrypted local folder backup (same archive envelope as the Flutter app) ----

    private fun folderUris(): JSONObject = vault.optJSONObject("syncFolderUris") ?: JSONObject()
    private fun currentFolderUri(): String? =
        mutableState.value.userId?.let { folderUris().optString(it).takeIf(String::isNotBlank) }

    private suspend fun restoreLocalSyncStatus() {
        val uid = mutableState.value.userId
        val selected = currentFolderUri() != null
        val last = uid?.let { vault.optLong("lastLocalSync_$it").takeIf { value -> value > 0 } }
        mutableState.value = mutableState.value.copy(localFolderSelected = selected, lastSyncAt = last)
    }

    fun setLocalFolder(uri: String) {
        val uid = mutableState.value.userId ?: return
        folderUris().put(uid, uri)
        vault.put("syncFolderUris", folderUris())
        viewModelScope.launch {
            saveVault()
            mutableState.value = mutableState.value.copy(localFolderSelected = true)
            syncNow()
        }
    }

    fun syncIfEnabled() {
        if (currentFolderUri() == null || identityPrivate == null) return
        syncNow()
    }

    private fun scheduleAutomaticFolderSync() {
        if (syncingArchive || currentFolderUri() == null || identityPrivate == null) return
        autoSyncJob?.cancel()
        autoSyncJob = viewModelScope.launch {
            delay(3000)
            syncNow()
        }
    }

    fun syncNow() {
        if (syncingArchive) return
        viewModelScope.launch {
            val uid = mutableState.value.userId ?: return@launch
            val privateKey = identityPrivate?.copyOf() ?: run {
                reportError("Unlock your identity before backing up messages.")
                return@launch
            }
            val uri = currentFolderUri() ?: run {
                reportError("Choose a local folder first.")
                return@launch
            }
            syncingArchive = true
            mutableState.value = mutableState.value.copy(localSyncing = true, localSyncStatus = "Checking encrypted backup…")
            try {
                val document = withContext(Dispatchers.IO) {
                    val tree = DocumentFile.fromTreeUri(appContext, Uri.parse(uri))
                        ?: throw IllegalStateException("The selected folder is no longer available.")
                    tree.findFile("crazechat-encrypted-backup.json")
                }
                if (document != null) {
                    val bytes = withContext(Dispatchers.IO) {
                        appContext.contentResolver.openInputStream(document.uri)?.use { input ->
                            val output = ByteArrayOutputStream()
                            val buffer = ByteArray(8192)
                            var total = 0
                            while (true) {
                                val read = input.read(buffer)
                                if (read < 0) break
                                total += read
                                require(total <= 64 * 1024 * 1024) { "The local backup is larger than the 64 MB limit." }
                                output.write(buffer, 0, read)
                            }
                            output.toByteArray()
                        } ?: throw IllegalStateException("Could not read the selected backup file.")
                    }
                    if (bytes.isNotEmpty()) {
                        val envelope = JSONObject(String(bytes, Charsets.UTF_8))
                        val archiveBytes = CryptoService.decryptLocalBackup(envelope, privateKey, uid)
                        mergeEncryptedArchive(JSONObject(String(archiveBytes, Charsets.UTF_8)), uid)
                    }
                }

                mutableState.value = mutableState.value.copy(localSyncStatus = "Encrypting message envelopes…")
                val archive = exportEncryptedArchive(uid)
                val archiveBytes = archive.toString().toByteArray(Charsets.UTF_8)
                require(archiveBytes.size <= 64 * 1024 * 1024) { "The backup exceeds the 64 MB limit." }
                val encrypted = CryptoService.encryptLocalBackup(archiveBytes, privateKey, uid)
                val encoded = encrypted.toString().toByteArray(Charsets.UTF_8)
                require(encoded.size <= 64 * 1024 * 1024) { "The encrypted backup exceeds the 64 MB limit." }
                mutableState.value = mutableState.value.copy(localSyncStatus = "Saving encrypted backup…")
                withContext(Dispatchers.IO) {
                    val tree = DocumentFile.fromTreeUri(appContext, Uri.parse(uri))
                        ?: throw IllegalStateException("The selected folder is no longer available.")
                    val target = tree.findFile("crazechat-encrypted-backup.json")
                        ?: tree.createFile("application/json", "crazechat-encrypted-backup.json")
                        ?: throw IllegalStateException("Could not create the backup file.")
                    appContext.contentResolver.openOutputStream(target.uri, "wt")?.use { output ->
                        output.write(encoded)
                        output.flush()
                    } ?: throw IllegalStateException("Could not write the backup file.")
                }
                val now = System.currentTimeMillis()
                vault.put("lastLocalSync_$uid", now)
                saveVault()
                mutableState.value = mutableState.value.copy(lastSyncAt = now, localSyncStatus = "Encrypted backup updated.")
            } catch (error: Exception) {
                mutableState.value = mutableState.value.copy(localSyncStatus = "Sync needs attention: \${error.message}")
            } finally {
                privateKey.fill(0)
                syncingArchive = false
                mutableState.value = mutableState.value.copy(localSyncing = false)
                updateStorageCount()
            }
        }
    }

    private suspend fun exportEncryptedArchive(uid: String): JSONObject {
        require(uid == mutableState.value.userId && identityPrivate != null) { "The active account changed during backup." }
        val all = vault.optJSONObject("messageCache") ?: JSONObject()
        val tombstones = vault.optJSONObject("messageTombstones") ?: JSONObject()
        val chats = JSONArray()
        val ids = mutableSetOf<String>()
        all.keys().forEach { id -> if (Regex("^[a-f0-9]{32}$").matches(id)) ids.add(id) }
        tombstones.keys().forEach { id -> if (Regex("^[a-f0-9]{32}$").matches(id)) ids.add(id) }
        ids.sorted().forEach { chatId ->
            val rawMessages = all.optJSONArray(chatId) ?: JSONArray()
            val messages = JSONArray()
            for (i in 0 until rawMessages.length()) {
                val message = rawMessages.optJSONObject(i) ?: continue
                if (Regex("^[a-f0-9]{32}$").matches(message.optString("id"))) messages.put(JSONObject(message.toString()))
            }
            val deleted = JSONArray()
            tombstonesForChat(chatId).sorted().forEach { deleted.put(it) }
            chats.put(JSONObject().put("chatId", chatId).put("messages", messages).put("deletedMessageIds", deleted))
        }
        return JSONObject().put("version", 1).put("userId", uid).put("chats", chats)
    }

    private suspend fun mergeEncryptedArchive(archive: JSONObject, expectedUserId: String) {
        require(archive.optInt("version") == 1 && archive.optString("userId") == expectedUserId && archive.optJSONArray("chats") != null) {
            "This encrypted backup does not match the active CrazeChat account."
        }
        val chats = archive.getJSONArray("chats")
        require(chats.length() <= 2000) { "The backup contains too many conversations." }
        var totalMessages = 0
        for (i in 0 until chats.length()) {
            val chat = chats.optJSONObject(i) ?: throw IllegalArgumentException("Invalid chat in backup.")
            val chatId = chat.optString("chatId")
            require(Regex("^[a-f0-9]{32}$").matches(chatId)) { "Invalid conversation ID in backup." }
            val messages = chat.optJSONArray("messages") ?: JSONArray()
            val deleted = chat.optJSONArray("deletedMessageIds") ?: JSONArray()
            totalMessages += messages.length()
            require(totalMessages <= 200000) { "The backup contains too many messages." }
            val tombstoneIds = (0 until deleted.length()).map { deleted.optString(it) }
            tombstoneIds.forEach { id ->
                require(Regex("^[a-f0-9]{32}$").matches(id)) { "Invalid deletion marker in backup." }
                removeCachedMessage(chatId, id, recordTombstone = true)
            }
            val existing = cacheForChat(chatId)
            val existingIds = (0 until existing.length()).mapNotNull { existing.optJSONObject(it)?.optString("id") }.toSet()
            for (j in 0 until messages.length()) {
                val envelope = messages.optJSONObject(j) ?: throw IllegalArgumentException("Invalid message in backup.")
                val id = envelope.optString("id")
                require(Regex("^[a-f0-9]{32}$").matches(id)) { "Invalid message ID in backup." }
                require(envelope.optString("format") == "cc-e2ee-v1") { "Unsupported encrypted message format in backup." }
                require(Base64.decode(envelope.optString("nonce"), Base64.DEFAULT).size == 12)
                require(Base64.decode(envelope.optString("mac"), Base64.DEFAULT).size == 16)
                require(Base64.decode(envelope.optString("ciphertext"), Base64.DEFAULT).isNotEmpty())
                if (!existingIds.contains(id) && !tombstonesForChat(chatId).contains(id)) saveEnvelope(chatId, JSONObject(envelope.toString()))
            }
        }
    }

    private fun handleIncomingPush(chatId: String) {
        if (mutableState.value.currentChat?.id == chatId && mutableState.value.page == AppPage.CHAT) return
        val serial = bannerSerial.incrementAndGet()
        val peer = mutableState.value.chats.firstOrNull { it.id == chatId }?.peer(mutableState.value.userId.orEmpty())
        mutableState.value = mutableState.value.copy(
            bannerChatId = chatId,
            bannerName = peer?.username ?: "New message",
            bannerCount = if (mutableState.value.bannerChatId == chatId) mutableState.value.bannerCount + 1 else 1
        )
        if (mutableState.value.soundEffectsEnabled) CrazeSoundEffects.play(incoming = true)
        if (mutableState.value.vibrationEnabled) vibrate()
        bannerDismissJob?.cancel()
        bannerDismissJob = viewModelScope.launch {
            delay(5000)
            if (bannerSerial.get() == serial) dismissBanner()
        }
    }

    fun dismissBanner() {
        bannerDismissJob?.cancel()
        mutableState.value = mutableState.value.copy(bannerChatId = null, bannerName = null, bannerCount = 0)
    }

    fun openBannerChat() {
        val chatId = mutableState.value.bannerChatId ?: return
        dismissBanner()
        openChatById(chatId)
    }

    fun showInfoMessage(message: String) {
        mutableState.value = mutableState.value.copy(info = message)
    }

    fun updateStorageCount() {
        viewModelScope.launch(Dispatchers.IO) {
            val prefs = appContext.getSharedPreferences("crazechat_secure_vault", 0)
            val bytes = prefs.getString("encrypted_v1", null)?.toByteArray()?.size?.toLong() ?: 0L
            mutableState.value = mutableState.value.copy(storageBytes = bytes)
        }
    }

    override fun onCleared() {
        closeRealtime()
        autoSyncJob?.cancel()
        bannerDismissJob?.cancel()
        identityPrivate?.fill(0)
        currentChatKey?.fill(0)
        CrazeSoundEffects.dispose()
        super.onCleared()
    }
}
