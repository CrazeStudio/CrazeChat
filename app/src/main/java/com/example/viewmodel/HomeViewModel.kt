package com.example.viewmodel

import android.app.Application
import android.graphics.Bitmap
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.data.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

@OptIn(ExperimentalCoroutinesApi::class)
class HomeViewModel(application: Application) : AndroidViewModel(application) {
    private val db = CrazeDatabase.getDatabase(application)
    private val chatDao = db.chatDao()
    private val messageDao = db.messageDao()
    private val profileDao = db.profileDao()
    private val firebaseRepo = FirebaseRepository()
    private val userPrefs = UserPreferences(application)
    private val pfpManager = ProfileImageManager.getInstance(application)

    private val _currentUserPfp = MutableStateFlow<Bitmap?>(null)
    val currentUserPfp: StateFlow<Bitmap?> = _currentUserPfp.asStateFlow()

    val currentUserId: StateFlow<String> = userPrefs.userIdFlow
        .map { it ?: "" }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "")

    val currentUsername: StateFlow<String> = userPrefs.usernameFlow
        .map { it ?: "" }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "")

    val privateKey: StateFlow<String> = userPrefs.privateKeyFlow
        .map { it ?: "" }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "")

    val profiles: StateFlow<List<AccountProfileEntity>> = profileDao.getAllProfilesFlow()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val canAddProfile: StateFlow<Boolean> = profiles.map { it.size < 2 }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)

    val chats: StateFlow<List<ChatEntity>> = userPrefs.userIdFlow.flatMapLatest { uid ->
        if (uid.isNullOrEmpty()) flowOf(emptyList()) else chatDao.getChatsForUser(uid)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private val _searchResult = MutableStateFlow<FirebaseUserDto?>(null)
    val searchResult: StateFlow<FirebaseUserDto?> = _searchResult.asStateFlow()

    private val _searchError = MutableStateFlow<String?>(null)
    val searchError: StateFlow<String?> = _searchError.asStateFlow()

    private val _availableUsers = MutableStateFlow<List<FirebaseUserDto>>(emptyList())
    val availableUsers: StateFlow<List<FirebaseUserDto>> = _availableUsers.asStateFlow()

    private val _isLoadingUsers = MutableStateFlow(false)
    val isLoadingUsers: StateFlow<Boolean> = _isLoadingUsers.asStateFlow()

    private val activeObservedChats = java.util.Collections.synchronizedSet(mutableSetOf<String>())
    private val soundEffects = SoundEffectsManager.getInstance(application)

    init {
        observeCurrentUserPfp()
        observeRealtimeInbox()
        observeRealtimeGroups()
        syncPendingCloudMessages()
        observeLocalChatsForMessages()
    }

    private fun observeLocalChatsForMessages() {
        viewModelScope.launch {
            chats.collect { chatList ->
                val myId = userPrefs.userIdFlow.first() ?: return@collect
                val privateKeyVal = userPrefs.privateKeyFlow.first() ?: return@collect
                for (chat in chatList) {
                    startObservingChatMessages(
                        chatId = chat.chatId,
                        myId = myId,
                        peerUserId = chat.peerUserId,
                        peerPublicKey = chat.peerPublicKey,
                        privateKeyVal = privateKeyVal,
                        isGroup = chat.isGroup
                    )
                }
            }
        }
    }

    private fun observeRealtimeInbox() {
        viewModelScope.launch {
            userPrefs.userIdFlow.collect { myId ->
                if (myId.isNullOrBlank()) return@collect
                val privateKeyVal = userPrefs.privateKeyFlow.first() ?: ""

                firebaseRepo.observeUserInbox(myId) { chatId, senderId, senderUsername, timestamp ->
                    viewModelScope.launch {
                        try {
                            val existingChat = chatDao.getChatById(ownerUserId = myId, chatId = chatId)
                            var peerKey = existingChat?.peerPublicKey ?: ""
                            var peerName = if (existingChat != null && existingChat.peerUsername.isNotBlank()) {
                                existingChat.peerUsername
                            } else {
                                senderUsername
                            }

                            if (peerKey.isBlank()) {
                                val senderUser = firebaseRepo.findUserById(senderId)
                                if (senderUser != null) {
                                    peerKey = senderUser.publicKey
                                    if (peerName.isBlank()) peerName = senderUser.username
                                }
                            }

                            val newOrUpdatedChat = (existingChat ?: ChatEntity(
                                ownerUserId = myId,
                                chatId = chatId,
                                peerUserId = senderId,
                                peerUsername = peerName.ifBlank { "User" },
                                peerPublicKey = peerKey,
                                lastMessage = "New encrypted message",
                                lastTimestamp = timestamp,
                                unreadCount = 0
                            )).copy(
                                lastTimestamp = timestamp,
                                peerUsername = peerName.ifBlank { "User" },
                                peerPublicKey = peerKey,
                                unreadCount = if (ChatViewModel.activeChatId == chatId) 0 else (existingChat?.unreadCount ?: 1)
                            )
                            chatDao.insertChat(newOrUpdatedChat)

                            // Start listening to messages for this incoming chat immediately
                            startObservingChatMessages(
                                chatId = chatId,
                                myId = myId,
                                peerUserId = senderId,
                                peerPublicKey = peerKey,
                                privateKeyVal = privateKeyVal,
                                isGroup = false
                            )
                        } catch (e: Exception) {
                            Log.e("HomeViewModel", "Error processing inbox item: ${e.message}")
                        }
                    }
                }
            }
        }
    }

    private fun observeRealtimeGroups() {
        viewModelScope.launch {
            userPrefs.userIdFlow.collect { myId ->
                if (myId.isNullOrBlank()) return@collect
                firebaseRepo.observeUserGroups(myId) { chatId, groupName ->
                    viewModelScope.launch {
                        try {
                            val existing = chatDao.getChatById(ownerUserId = myId, chatId = chatId)
                            if (existing == null) {
                                val groupInfo = firebaseRepo.getGroupInfo(chatId)
                                val newGroupChat = ChatEntity(
                                    ownerUserId = myId,
                                    chatId = chatId,
                                    peerUserId = "",
                                    peerUsername = groupName,
                                    peerPublicKey = "",
                                    lastMessage = "Encrypted group chat",
                                    lastTimestamp = groupInfo?.createdAt ?: System.currentTimeMillis(),
                                    unreadCount = 0,
                                    isGroup = true,
                                    groupName = groupInfo?.groupName ?: groupName,
                                    groupOwnerId = groupInfo?.groupOwnerId ?: "",
                                    memberIdsJson = groupInfo?.members?.keys?.joinToString(",") ?: "",
                                    pinnedMessageId = groupInfo?.pinnedMessageId ?: ""
                                )
                                chatDao.insertChat(newGroupChat)
                            }
                        } catch (e: Exception) {
                            Log.e("HomeViewModel", "Error processing group item: ${e.message}")
                        }
                    }
                }
            }
        }
    }

    private fun startObservingChatMessages(
        chatId: String,
        myId: String,
        peerUserId: String,
        peerPublicKey: String,
        privateKeyVal: String,
        isGroup: Boolean = false
    ) {
        if (!activeObservedChats.add(chatId)) return

        firebaseRepo.observeMessages(
            chatId = chatId,
            onMessageReceived = { msgId, msgDto ->
                if (msgDto.senderId != myId) {
                    viewModelScope.launch {
                        try {
                            val existingMsg = messageDao.getMessageById(msgId)
                            if (existingMsg == null) {
                                val decryptedText = if (isGroup) {
                                    CryptoManager.decryptGroupMessage(chatId, msgDto.ciphertext, msgDto.nonce)
                                } else {
                                    val keyToUse = peerPublicKey.ifBlank {
                                        firebaseRepo.findUserById(msgDto.senderId)?.publicKey ?: ""
                                    }
                                    if (keyToUse.isNotBlank() && privateKeyVal.isNotBlank()) {
                                        CryptoManager.decryptMessage(
                                            myPrivateKeyBase64 = privateKeyVal,
                                            theirPublicKeyBase64 = keyToUse,
                                            ciphertextBase64 = msgDto.ciphertext,
                                            nonceBase64 = msgDto.nonce
                                        )
                                    } else ""
                                }

                                if (decryptedText.isNotBlank()) {
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
                                        isDeleted = msgDto.isDeleted
                                    )
                                    messageDao.insertMessage(newMsg)
                                    soundEffects.playMessageReceived()

                                    val existingChat = chatDao.getChatById(ownerUserId = myId, chatId = chatId)
                                    if (existingChat != null) {
                                        val displayMsg = if (msgDto.senderId == myId) {
                                            "You: $decryptedText"
                                        } else if (isGroup) {
                                            if (msgDto.senderUsername.isNotBlank()) "${msgDto.senderUsername}: $decryptedText" else decryptedText
                                        } else {
                                            decryptedText
                                        }
                                        chatDao.insertChat(existingChat.copy(
                                            lastMessage = displayMsg,
                                            lastTimestamp = msgDto.timestamp,
                                            unreadCount = if (ChatViewModel.activeChatId == chatId) 0 else existingChat.unreadCount + 1
                                        ))
                                    }
                                }
                            }

                            // Auto-delete 1-on-1 messages from cloud server immediately
                            if (!isGroup) {
                                firebaseRepo.deleteMessage(chatId, msgId)
                            }
                        } catch (e: Exception) {
                            Log.e("HomeViewModel", "Error in onMessageReceived for $chatId: ${e.message}")
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
            }
        )
    }

    private fun observeCurrentUserPfp() {
        viewModelScope.launch {
            currentUserId.collect { uid ->
                if (uid.isNotBlank()) {
                    _currentUserPfp.value = pfpManager.getPfpBitmap(uid)
                } else {
                    _currentUserPfp.value = null
                }
            }
        }
        viewModelScope.launch {
            pfpManager.pfpVersion.collect {
                val uid = currentUserId.value
                if (uid.isNotBlank()) {
                    _currentUserPfp.value = pfpManager.getPfpBitmap(uid)
                }
            }
        }
    }

    fun switchProfile(profile: AccountProfileEntity) {
        viewModelScope.launch {
            userPrefs.setActiveProfile(profile)
            syncPendingCloudMessages()
        }
    }

    fun loadAvailableUsers() {
        viewModelScope.launch {
            _isLoadingUsers.value = true
            try {
                // Boost privacy: Do not load or expose other users from the server to the user's client list
                _availableUsers.value = emptyList()
                syncPendingCloudMessages()
            } catch (e: Exception) {
                // Ignore
            } finally {
                _isLoadingUsers.value = false
            }
        }
    }

    private fun syncPendingCloudMessages() {
        viewModelScope.launch {
            try {
                val myId = userPrefs.userIdFlow.first() ?: return@launch
                val privateKeyVal = userPrefs.privateKeyFlow.first() ?: return@launch
                val allUsers = firebaseRepo.getAllUsers().filter { it.userId != myId }

                for (peer in allUsers) {
                    val sorted = listOf(myId, peer.userId).sorted()
                    val chatId = "chat_${sorted[0]}_${sorted[1]}"

                    // Listen for any incoming messages that are pending on the cloud
                    firebaseRepo.observeMessages(
                        chatId = chatId,
                        onMessageReceived = { msgId, msgDto ->
                            if (msgDto.receiverId == myId) {
                                viewModelScope.launch {
                                    val existing = messageDao.getMessageById(msgId)
                                    if (existing == null) {
                                        val decrypted = CryptoManager.decryptMessage(
                                            myPrivateKeyBase64 = privateKeyVal,
                                            theirPublicKeyBase64 = peer.publicKey,
                                            ciphertextBase64 = msgDto.ciphertext,
                                            nonceBase64 = msgDto.nonce
                                        )

                                        if (decrypted.isNotBlank()) {
                                            messageDao.insertMessage(
                                                MessageEntity(
                                                    messageId = msgId,
                                                    chatId = chatId,
                                                    senderId = msgDto.senderId,
                                                    receiverId = msgDto.receiverId,
                                                    plaintext = "",
                                                    ciphertext = msgDto.ciphertext,
                                                    nonce = msgDto.nonce,
                                                    timestamp = msgDto.timestamp,
                                                    status = "READ"
                                                )
                                            )

                                            val existingChat = chatDao.getChatById(ownerUserId = myId, chatId = chatId)
                                            val displayMsg = if (msgDto.senderId == myId) {
                                                "You: $decrypted"
                                            } else {
                                                decrypted
                                            }
                                            chatDao.insertChat(
                                                (existingChat ?: ChatEntity(
                                                    ownerUserId = myId,
                                                    chatId = chatId,
                                                    peerUserId = peer.userId,
                                                    peerUsername = peer.username,
                                                    peerPublicKey = peer.publicKey,
                                                    lastMessage = "",
                                                    lastTimestamp = 0L,
                                                    unreadCount = 0
                                                )).copy(
                                                    lastMessage = displayMsg,
                                                    lastTimestamp = msgDto.timestamp,
                                                    unreadCount = if (ChatViewModel.activeChatId == chatId) 0 else (existingChat?.unreadCount ?: 0) + 1
                                                )
                                            )
                                        }
                                    }
                                    // Immediate Auto-Server Delete: Clean up cloud copy immediately
                                    firebaseRepo.deleteMessage(chatId, msgId)
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
                        }
                    )
                }

                // Also check for any group chats this user belongs to
                val userGroupIds = firebaseRepo.getUserGroupIds(myId)
                for (gId in userGroupIds) {
                    val groupInfo = firebaseRepo.getGroupInfo(gId)
                    if (groupInfo != null) {
                        val existingChat = chatDao.getChatById(ownerUserId = myId, chatId = gId)
                        if (existingChat == null) {
                            val newGroupChat = ChatEntity(
                                ownerUserId = myId,
                                chatId = gId,
                                peerUserId = "",
                                peerUsername = groupInfo.groupName,
                                peerPublicKey = "",
                                lastMessage = "Encrypted group chat",
                                lastTimestamp = groupInfo.createdAt,
                                unreadCount = 0,
                                isGroup = true,
                                groupName = groupInfo.groupName,
                                groupOwnerId = groupInfo.groupOwnerId,
                                memberIdsJson = groupInfo.members.keys.joinToString(","),
                                pinnedMessageId = groupInfo.pinnedMessageId
                            )
                            chatDao.insertChat(newGroupChat)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e("HomeViewModel", "Error in syncPendingCloudMessages: ${e.message}")
            }
        }
    }

    suspend fun createGroupChat(groupName: String, memberIds: List<String>): String {
        val myId = userPrefs.userIdFlow.first() ?: ""
        val uniqueId = java.util.UUID.randomUUID().toString().take(8)
        val chatId = "group_${System.currentTimeMillis()}_$uniqueId"

        val allMembers = (memberIds + myId).distinct()
        val success = firebaseRepo.createGroup(
            chatId = chatId,
            groupName = groupName,
            ownerId = myId,
            memberIds = allMembers
        )

        val newGroupChat = ChatEntity(
            ownerUserId = myId,
            chatId = chatId,
            peerUserId = "",
            peerUsername = groupName,
            peerPublicKey = "",
            lastMessage = "Group created",
            lastTimestamp = System.currentTimeMillis(),
            unreadCount = 0,
            isGroup = true,
            groupName = groupName,
            groupOwnerId = myId,
            memberIdsJson = allMembers.joinToString(","),
            pinnedMessageId = ""
        )
        chatDao.insertChat(newGroupChat)

        SoundEffectsManager.getInstance(getApplication()).playClick()
        return chatId
    }

    fun searchUser(query: String) {
        viewModelScope.launch {
            _searchError.value = null
            _searchResult.value = null
            try {
                val user = firebaseRepo.findUser(query)
                if (user == null) {
                    _searchError.value = "User not found"
                } else {
                    val myId = userPrefs.userIdFlow.first()
                    if (user.userId == myId) {
                        _searchError.value = "Cannot chat with yourself"
                    } else {
                        _searchResult.value = user
                    }
                }
            } catch (e: Exception) {
                _searchError.value = e.localizedMessage ?: "Search failed"
            }
        }
    }

    suspend fun getOrCreateChatWithUser(peerUser: FirebaseUserDto): String {
        val myId = userPrefs.userIdFlow.first() ?: ""
        val sortedIds = listOf(myId, peerUser.userId).sorted()
        val chatId = "chat_${sortedIds[0]}_${sortedIds[1]}"

        val existingChat = chatDao.getChatById(ownerUserId = myId, chatId = chatId)
        if (existingChat == null) {
            val newChat = ChatEntity(
                ownerUserId = myId,
                chatId = chatId,
                peerUserId = peerUser.userId,
                peerUsername = peerUser.username,
                peerPublicKey = peerUser.publicKey,
                lastMessage = "End-to-end encrypted chat started",
                lastTimestamp = System.currentTimeMillis(),
                unreadCount = 0
            )
            chatDao.insertChat(newChat)
        }
        return chatId
    }

    fun deleteChat(chatId: String) {
        viewModelScope.launch {
            val myId = userPrefs.userIdFlow.first() ?: ""
            chatDao.deleteChat(myId, chatId)
            messageDao.deleteAllMessagesForChat(chatId)
        }
    }
}
