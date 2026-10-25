package com.example.viewmodel

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.data.*
import com.google.firebase.database.ChildEventListener
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.util.UUID

class ChatViewModel(application: Application, val chatId: String) : AndroidViewModel(application) {
    companion object {
        var activeChatId: String? = null
    }

    private val db = CrazeDatabase.getDatabase(application)
    private val messageDao = db.messageDao()
    private val chatDao = db.chatDao()
    private val userPrefs = UserPreferences(application)
    private val firebaseRepo = FirebaseRepository(application)
    private val soundEffects = SoundEffectsManager.getInstance(application)

    val messages: StateFlow<List<MessageEntity>> = messageDao.getMessagesForChat(chatId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val pinnedMessages: StateFlow<List<MessageEntity>> = messageDao.getPinnedMessages(chatId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private val _replyTargetMessage = MutableStateFlow<MessageEntity?>(null)
    val replyTargetMessage: StateFlow<MessageEntity?> = _replyTargetMessage.asStateFlow()

    private val _chat = MutableStateFlow<ChatEntity?>(null)
    val chat: StateFlow<ChatEntity?> = _chat.asStateFlow()

    val currentUserId: StateFlow<String> = userPrefs.userIdFlow
        .map { it ?: "" }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "")

    val currentUsername: StateFlow<String> = userPrefs.usernameFlow
        .map { it ?: "" }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "")

    val privateKey: StateFlow<String> = userPrefs.privateKeyFlow
        .map { it ?: "" }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "")

    private val _groupInfo = MutableStateFlow<FirebaseGroupDto?>(null)
    val groupInfo: StateFlow<FirebaseGroupDto?> = _groupInfo.asStateFlow()

    private var firebaseMessageListener: ChildEventListener? = null
    private var firebaseReactionListener: ChildEventListener? = null
    private var observationJob: Job? = null

    init {
        activeChatId = chatId
        loadChatDetails()
        loadGroupDetailsIfGroup()
        startObservingFirebaseMessages()
        markAsSeen()
    }

    fun markAsSeen() {
        viewModelScope.launch {
            userPrefs.userIdFlow.first()?.let { myId ->
                val entity = chatDao.getChatById(ownerUserId = myId, chatId = chatId)
                if (entity != null && entity.unreadCount > 0) {
                    chatDao.insertChat(entity.copy(unreadCount = 0))
                }
            }
        }
    }

    fun clearAllChatMessages() {
        viewModelScope.launch {
            messageDao.deleteAllMessagesForChat(chatId)
            soundEffects.playMessageDeleted()
        }
    }

    private fun loadChatDetails() {
        viewModelScope.launch {
            userPrefs.userIdFlow.collect { myId ->
                if (!myId.isNullOrEmpty()) {
                    val entity = chatDao.getChatById(ownerUserId = myId, chatId = chatId)
                    if (entity != null) {
                        if (entity.unreadCount > 0) {
                            val resetChat = entity.copy(unreadCount = 0)
                            chatDao.insertChat(resetChat)
                            _chat.value = resetChat
                        } else {
                            _chat.value = entity
                        }
                        if (entity.isGroup) {
                            loadGroupDetailsIfGroup()
                        }
                    }
                }
            }
        }
    }

    private fun loadGroupDetailsIfGroup() {
        viewModelScope.launch {
            if (chatId.startsWith("group_")) {
                val info = firebaseRepo.getGroupInfo(chatId)
                if (info != null) {
                    _groupInfo.value = info
                    val myId = userPrefs.userIdFlow.first() ?: return@launch
                    val current = _chat.value
                    if (current != null) {
                        val updated = current.copy(
                            isGroup = true,
                            groupName = info.groupName,
                            groupOwnerId = info.groupOwnerId,
                            pinnedMessageId = info.pinnedMessageId,
                            memberIdsJson = info.members.keys.joinToString(",")
                        )
                        chatDao.insertChat(updated)
                        _chat.value = updated
                    }
                }
            }
        }
    }

    private fun startObservingFirebaseMessages() {
        observationJob?.cancel()
        observationJob = viewModelScope.launch {
            combine(userPrefs.userIdFlow, userPrefs.privateKeyFlow) { uid, privKey ->
                if (uid != null && privKey != null) Pair(uid, privKey) else null
            }.filterNotNull().collect { (myId, privateKeyVal) ->
                if (firebaseMessageListener != null) return@collect

                val chatEntity = chatDao.getChatById(ownerUserId = myId, chatId = chatId)
                val isGroup = chatEntity?.isGroup == true || chatId.startsWith("group_")
                var peerPublicKey = chatEntity?.peerPublicKey ?: ""

                firebaseMessageListener = firebaseRepo.observeMessages(
                    chatId = chatId,
                    onMessageReceived = { msgId, msgDto ->
                        viewModelScope.launch {
                            // In group chat, accept messages from anyone other than me.
                            // In 1-on-1 chat, accept messages addressed to me.
                            val isForMe = if (isGroup) {
                                msgDto.senderId != myId
                            } else {
                                msgDto.receiverId == myId
                            }

                            if (isForMe) {
                                val existing = messageDao.getMessageById(msgId)

                                // Handle reaction signaling messages defensively: malformed/stale reactions
                                // must never crash the chat screen or its message-observer coroutine.
                                if (msgDto.reactionTargetId.isNotBlank()) {
                                    try {
                                        val targetMsg = messageDao.getMessageById(msgDto.reactionTargetId)
                                        if (targetMsg != null && msgDto.senderId.isNotBlank() && msgDto.reactionEmoji.isNotBlank()) {
                                            val reactions = try {
                                                JSONObject(targetMsg.reactionsJson.ifBlank { "{}" })
                                            } catch (_: Exception) {
                                                JSONObject()
                                            }
                                            reactions.put(msgDto.senderId, msgDto.reactionEmoji)
                                            messageDao.updateReactions(targetMsg.messageId, reactions.toString())
                                        }
                                    } catch (e: Exception) {
                                        Log.e("ChatViewModel", "Could not apply reaction $msgId: ${e.message}", e)
                                    } finally {
                                        // Best-effort cleanup; failure to delete a transient event is non-fatal.
                                        try {
                                            firebaseRepo.deleteMessage(chatId, msgId)
                                        } catch (e: Exception) {
                                            Log.w("ChatViewModel", "Could not clean up reaction $msgId: ${e.message}")
                                        }
                                    }
                                    return@launch
                                }

                                if (existing == null) {
                                    try {
                                        val decryptedText = if (isGroup) {
                                            CryptoManager.decryptGroupMessage(chatId, msgDto.ciphertext, msgDto.nonce)
                                        } else {
                                            if (peerPublicKey.isBlank()) {
                                                val senderUser = firebaseRepo.findUserById(msgDto.senderId)
                                                if (senderUser != null) {
                                                    peerPublicKey = senderUser.publicKey
                                                }
                                            }
                                            CryptoManager.decryptMessage(
                                                myPrivateKeyBase64 = privateKeyVal,
                                                theirPublicKeyBase64 = peerPublicKey,
                                                ciphertextBase64 = msgDto.ciphertext,
                                                nonceBase64 = msgDto.nonce
                                            )
                                        }

                                        if (decryptedText.isNotBlank()) {
                                            val decryptedReplyText = decryptReplyPreview(
                                                encodedPreview = msgDto.replyToText,
                                                isGroup = isGroup,
                                                privateKey = privateKeyVal,
                                                peerPublicKey = peerPublicKey
                                            )
                                            val newMsg = MessageEntity(
                                                messageId = msgId,
                                                chatId = chatId,
                                                senderId = msgDto.senderId,
                                                receiverId = msgDto.receiverId,
                                                plaintext = "",
                                                ciphertext = msgDto.ciphertext,
                                                nonce = msgDto.nonce,
                                                timestamp = msgDto.timestamp,
                                                status = "READ",
                                                senderUsername = msgDto.senderUsername,
                                                isEdited = msgDto.isEdited,
                                                editedAt = msgDto.editedAt,
                                                isPinned = msgDto.isPinned,
                                                pinnedAt = msgDto.pinnedAt,
                                                isDeleted = msgDto.isDeleted,
                                                replyToId = msgDto.replyToId,
                                                replyToText = decryptedReplyText,
                                                replyToSender = msgDto.replyToSender,
                                                reactionsJson = msgDto.reactionsJson
                                            )
                                            messageDao.insertMessage(newMsg)

                                            // Play pleasant receive sound effect
                                            soundEffects.playMessageReceived()

                                            // Update chat entity
                                            val displayMsg = if (msgDto.senderId == myId) {
                                                "You: $decryptedText"
                                            } else if (isGroup) {
                                                if (msgDto.senderUsername.isNotBlank()) "${msgDto.senderUsername}: $decryptedText" else decryptedText
                                            } else {
                                                decryptedText
                                            }
                                            val updatedChat = (chatEntity ?: ChatEntity(
                                                ownerUserId = myId,
                                                chatId = chatId,
                                                peerUserId = msgDto.senderId,
                                                peerUsername = msgDto.senderUsername.ifBlank { "User" },
                                                peerPublicKey = peerPublicKey,
                                                lastMessage = "",
                                                lastTimestamp = 0L,
                                                unreadCount = 0,
                                                isGroup = isGroup
                                            )).copy(
                                                lastMessage = displayMsg,
                                                lastTimestamp = msgDto.timestamp,
                                                unreadCount = 0
                                            )
                                            chatDao.insertChat(updatedChat)
                                        }
                                    } catch (e: Exception) {
                                        Log.e("ChatViewModel", "Decryption failed for $msgId: ${e.message}")
                                    }
                                }

                                // Auto server delete for 1-on-1 messages and ALL replies to maintain strict cloud privacy
                                if (!isGroup || msgDto.replyToId.isNotBlank()) {
                                    firebaseRepo.deleteMessage(chatId, msgId)
                                }
                            }
                        }
                    },
                    onMessageDeletedFromServer = { msgId ->
                        viewModelScope.launch {
                            val existing = messageDao.getMessageById(msgId)
                            if (existing != null && existing.senderId == myId) {
                                messageDao.updateMessageStatus(msgId, "SERVER_DELETED")
                            }
                        }
                    },
                    onMessageUpdated = { msgId, updatedDto ->
                        viewModelScope.launch {
                            val existing = messageDao.getMessageById(msgId)
                            if (existing != null) {
                                val updated = existing.copy(
                                    ciphertext = updatedDto.ciphertext,
                                    nonce = updatedDto.nonce,
                                    isEdited = updatedDto.isEdited,
                                    editedAt = updatedDto.editedAt,
                                    isPinned = updatedDto.isPinned,
                                    pinnedAt = updatedDto.pinnedAt,
                                    isDeleted = updatedDto.isDeleted,
                                    reactionsJson = if (
                                        updatedDto.reactionsJson.isBlank() || updatedDto.reactionsJson == "{}"
                                    ) existing.reactionsJson else updatedDto.reactionsJson
                                )
                                messageDao.insertMessage(updated)

                                if (updatedDto.isPinned && !existing.isPinned) {
                                    soundEffects.playMessagePinned()
                                }
                            }
                        }
                    }
                )

                // Reactions have their own listener because delivered direct-chat messages
                // can be deleted from Firebase before someone reacts to them.
                firebaseReactionListener = firebaseRepo.observeReactions(chatId) { targetMessageId, reactionsJson ->
                    viewModelScope.launch {
                        try {
                            if (messageDao.getMessageById(targetMessageId) != null) {
                                messageDao.updateReactions(targetMessageId, reactionsJson)
                            }
                        } catch (e: Exception) {
                            Log.e("ChatViewModel", "Could not sync reactions for $targetMessageId: ${e.message}", e)
                        }
                    }
                }
            }
        }
    }

    private fun encryptReplyPreview(
        preview: String,
        isGroup: Boolean,
        chatId: String,
        privateKey: String,
        peerPublicKey: String
    ): String {
        if (preview.isBlank()) return ""
        return try {
            val payload = if (isGroup) {
                CryptoManager.encryptGroupMessage(chatId, preview)
            } else {
                CryptoManager.encryptMessage(
                    myPrivateKeyBase64 = privateKey,
                    theirPublicKeyBase64 = peerPublicKey,
                    plaintext = preview
                )
            }
            // Base64 payloads don't contain '|', so this is safe to split on receive.
            "ENCv1|${payload.nonce}|${payload.ciphertext}"
        } catch (e: Exception) {
            Log.e("ChatViewModel", "Reply preview encryption failed: ${e.message}", e)
            // Fail closed: don't send a plaintext preview if encryption fails.
            ""
        }
    }

    private fun decryptReplyPreview(
        encodedPreview: String,
        isGroup: Boolean,
        privateKey: String,
        peerPublicKey: String
    ): String {
        if (encodedPreview.isBlank()) return ""
        // Older messages used plaintext reply previews. Keep those readable for compatibility;
        // all newly sent reply previews use the encrypted ENCv1 format.
        if (!encodedPreview.startsWith("ENCv1|")) return encodedPreview

        return try {
            val parts = encodedPreview.split("|", limit = 3)
            if (parts.size != 3 || parts[1].isBlank() || parts[2].isBlank()) return ""
            if (isGroup) {
                CryptoManager.decryptGroupMessage(chatId, parts[2], parts[1])
            } else {
                CryptoManager.decryptMessage(
                    myPrivateKeyBase64 = privateKey,
                    theirPublicKeyBase64 = peerPublicKey,
                    ciphertextBase64 = parts[2],
                    nonceBase64 = parts[1]
                )
            }
        } catch (e: Exception) {
            Log.e("ChatViewModel", "Reply preview decryption failed: ${e.message}", e)
            ""
        }
    }

    fun sendMessage(plaintext: String, replyToPreviewText: String = "") {
        if (plaintext.isBlank()) return

        viewModelScope.launch {
            val myId = userPrefs.userIdFlow.first() ?: return@launch
            val myUsername = userPrefs.usernameFlow.first() ?: "User"
            val privateKeyVal = userPrefs.privateKeyFlow.first() ?: return@launch
            val chatEntity = _chat.value ?: return@launch
            val isGroup = chatEntity.isGroup || chatId.startsWith("group_")

            val messageId = UUID.randomUUID().toString()
            val timestamp = System.currentTimeMillis()
            val replyTarget = _replyTargetMessage.value

            try {
                val encrypted = if (isGroup) {
                    CryptoManager.encryptGroupMessage(chatId, plaintext)
                } else {
                    CryptoManager.encryptMessage(
                        myPrivateKeyBase64 = privateKeyVal,
                        theirPublicKeyBase64 = chatEntity.peerPublicKey,
                        plaintext = plaintext
                    )
                }

                // Keep the readable preview locally, but never upload it as plaintext.
                val encryptedReplyPreview = encryptReplyPreview(
                    preview = replyToPreviewText,
                    isGroup = isGroup,
                    chatId = chatId,
                    privateKey = privateKeyVal,
                    peerPublicKey = chatEntity.peerPublicKey
                )

                val localMsg = MessageEntity(
                    messageId = messageId,
                    chatId = chatId,
                    senderId = myId,
                    receiverId = if (isGroup) "" else chatEntity.peerUserId,
                    plaintext = plaintext, // Store plaintext locally
                    ciphertext = encrypted.ciphertext,
                    nonce = encrypted.nonce,
                    timestamp = timestamp,
                    status = "SENDING",
                    senderUsername = myUsername,
                    replyToSender = replyTarget?.senderUsername ?: "",
                    replyToText = replyToPreviewText
                )
                messageDao.insertMessage(localMsg)

                // Play sound effect immediately for responsive feel
                soundEffects.playMessageSent()

                val sentSuccessfully = firebaseRepo.sendMessage(
                    chatId = chatId,
                    messageId = messageId,
                    senderId = myId,
                    receiverId = if (isGroup) "" else chatEntity.peerUserId,
                    ciphertext = encrypted.ciphertext,
                    nonce = encrypted.nonce,
                    timestamp = timestamp,
                    senderUsername = myUsername,
                    replyToId = replyTarget?.messageId ?: "",
                    replyToText = encryptedReplyPreview,
                    replyToSender = replyTarget?.senderUsername ?: ""
                )

                // Clear reply target after sending
                _replyTargetMessage.value = null

                messageDao.updateMessageStatus(
                    messageId,
                    if (sentSuccessfully) "SENT" else "FAILED"
                )

                chatDao.insertChat(chatEntity.copy(
                    lastMessage = "You: $plaintext",
                    lastTimestamp = timestamp
                ))
            } catch (e: Exception) {
                Log.e("ChatViewModel", "Send message failed: ${e.message}", e)
                runCatching { messageDao.updateMessageStatus(messageId, "FAILED") }
            }
        }
    }

    /**
     * Retry a message that previously failed to upload.
     * Reuses its existing encrypted payload and message ID to avoid duplicate messages.
     */
    fun retryMessage(messageId: String) {
        viewModelScope.launch {
            val message = messageDao.getMessageById(messageId) ?: return@launch
            if (message.senderId != userPrefs.userIdFlow.first() || message.status != "FAILED") return@launch
            val chatEntity = _chat.value ?: return@launch
            val privateKeyVal = userPrefs.privateKeyFlow.first() ?: return@launch
            val isGroup = chatEntity.isGroup || chatId.startsWith("group_")

            messageDao.updateMessageStatus(messageId, "SENDING")
            try {
                val encryptedReplyPreview = encryptReplyPreview(
                    preview = message.replyToText,
                    isGroup = isGroup,
                    chatId = chatId,
                    privateKey = privateKeyVal,
                    peerPublicKey = chatEntity.peerPublicKey
                )
                val sent = firebaseRepo.sendMessage(
                    chatId = chatId,
                    messageId = message.messageId,
                    senderId = message.senderId,
                    receiverId = message.receiverId,
                    ciphertext = message.ciphertext,
                    nonce = message.nonce,
                    timestamp = message.timestamp,
                    senderUsername = message.senderUsername,
                    replyToId = message.replyToId,
                    replyToText = encryptedReplyPreview,
                    replyToSender = message.replyToSender
                )
                messageDao.updateMessageStatus(messageId, if (sent) "SENT" else "FAILED")
            } catch (e: Exception) {
                Log.e("ChatViewModel", "Retry send failed for $messageId: ${e.message}", e)
                messageDao.updateMessageStatus(messageId, "FAILED")
            }
        }
    }

    /**
     * Edit message: allowed strictly within 10 minutes of creation by sender
     */
    fun editMessage(messageId: String, newPlaintext: String, onResult: (Boolean, String?) -> Unit) {
        if (newPlaintext.isBlank()) {
            onResult(false, "Message cannot be empty")
            return
        }

        viewModelScope.launch {
            val myId = userPrefs.userIdFlow.first() ?: return@launch
            val privateKeyVal = userPrefs.privateKeyFlow.first() ?: return@launch
            val chatEntity = _chat.value ?: return@launch
            val isGroup = chatEntity.isGroup || chatId.startsWith("group_")

            val existing = messageDao.getMessageById(messageId)
            if (existing == null) {
                onResult(false, "Message not found")
                return@launch
            }

            if (existing.senderId != myId) {
                onResult(false, "You can only edit your own messages")
                return@launch
            }

            // Check 10-minute limit (10 * 60 * 1000 ms = 600,000 ms)
            val elapsed = System.currentTimeMillis() - existing.timestamp
            if (elapsed > 10 * 60 * 1000L) {
                onResult(false, "Edit window expired (10 minutes limit)")
                return@launch
            }

            try {
                val encrypted = if (isGroup) {
                    CryptoManager.encryptGroupMessage(chatId, newPlaintext)
                } else {
                    CryptoManager.encryptMessage(
                        myPrivateKeyBase64 = privateKeyVal,
                        theirPublicKeyBase64 = chatEntity.peerPublicKey,
                        plaintext = newPlaintext
                    )
                }

                val now = System.currentTimeMillis()
                messageDao.updateMessageContent(messageId, encrypted.ciphertext, encrypted.nonce, now)
                firebaseRepo.editMessage(chatId, messageId, encrypted.ciphertext, encrypted.nonce)

                chatDao.insertChat(chatEntity.copy(
                    lastMessage = "You: $newPlaintext (edited)",
                    lastTimestamp = now
                ))

                soundEffects.playClick()
                onResult(true, null)
            } catch (e: Exception) {
                onResult(false, e.localizedMessage ?: "Failed to edit")
            }
        }
    }

    /**
     * Delete message: "forEveryone" or "forMe"
     */
    fun deleteMessage(messageId: String, forEveryone: Boolean) {
        viewModelScope.launch {
            val myId = userPrefs.userIdFlow.first() ?: return@launch
            val existing = messageDao.getMessageById(messageId) ?: return@launch

            if (forEveryone) {
                // Delete from cloud or mark deleted
                firebaseRepo.deleteMessage(chatId, messageId)
                // Mark locally or delete
                messageDao.deleteMessageById(messageId)
            } else {
                messageDao.deleteMessageById(messageId)
            }
            soundEffects.playMessageDeleted()
        }
    }

    /**
     * Toggle pin message: pins/unpins in local database and cloud
     */
    fun togglePinMessage(messageId: String) {
        viewModelScope.launch {
            val myId = userPrefs.userIdFlow.first() ?: return@launch
            val existing = messageDao.getMessageById(messageId) ?: return@launch
            val newPinState = !existing.isPinned
            val now = if (newPinState) System.currentTimeMillis() else 0L

            messageDao.updatePinStatus(messageId, newPinState, now)
            firebaseRepo.pinMessage(chatId, messageId, newPinState)

            val currentChat = _chat.value
            if (currentChat != null) {
                val updatedPinnedId = if (newPinState) messageId else ""
                chatDao.updatePinnedMessageId(myId, chatId, updatedPinnedId)
                _chat.value = currentChat.copy(pinnedMessageId = updatedPinnedId)
            }

            soundEffects.playMessagePinned()
        }
    }

    fun setReplyTarget(message: MessageEntity?) {
        _replyTargetMessage.value = message
    }

    fun clearReplyTarget() {
        _replyTargetMessage.value = null
    }

    fun sendReaction(targetMessageId: String, emoji: String) {
        if (targetMessageId.isBlank() || emoji.isBlank()) return

        viewModelScope.launch {
            try {
                val myId = userPrefs.userIdFlow.first()
                if (myId.isNullOrBlank()) return@launch
                val myUsername = userPrefs.usernameFlow.first() ?: "User"
                val chatEntity = _chat.value ?: return@launch
                val targetMsg = messageDao.getMessageById(targetMessageId) ?: return@launch

                // Update locally first so a transient network failure does not crash or block the UI.
                val reactions = try {
                    JSONObject(targetMsg.reactionsJson.ifBlank { "{}" })
                } catch (_: Exception) {
                    JSONObject()
                }
                reactions.put(myId, emoji)
                messageDao.updateReactions(targetMessageId, reactions.toString())

                val reactionId = "react_" + UUID.randomUUID().toString()
                firebaseRepo.sendReaction(
                    chatId = chatId,
                    reactionId = reactionId,
                    senderId = myId,
                    receiverId = if (chatEntity.isGroup || chatId.startsWith("group_")) "" else chatEntity.peerUserId,
                    targetMessageId = targetMessageId,
                    emoji = emoji,
                    timestamp = System.currentTimeMillis(),
                    senderUsername = myUsername
                )
            } catch (e: Exception) {
                Log.e("ChatViewModel", "Send reaction failed: ${e.message}", e)
            }
        }
    }

    fun addMemberToGroup(newMemberId: String, onResult: (Boolean, String?) -> Unit) {
        viewModelScope.launch {
            val cleanId = newMemberId.trim()
            if (cleanId.isBlank()) {
                onResult(false, "User ID cannot be empty")
                return@launch
            }

            val user = firebaseRepo.findUserById(cleanId)
            if (user == null) {
                onResult(false, "User not found with this ID")
                return@launch
            }

            val success = firebaseRepo.addGroupMember(chatId, cleanId)
            if (success) {
                loadGroupDetailsIfGroup()
                soundEffects.playClick()
                onResult(true, "Added ${user.username} to group")
            } else {
                onResult(false, "Failed to add user to group")
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        firebaseMessageListener?.let { firebaseRepo.removeMessageListener(chatId, it) }
        firebaseReactionListener?.let { firebaseRepo.removeReactionListener(chatId, it) }
        observationJob?.cancel()
        if (activeChatId == chatId) {
            activeChatId = null
        }
    }
}
