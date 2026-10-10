package com.example.data

import org.json.JSONObject

import android.util.Log
import com.example.BuildConfig
import com.google.firebase.database.ChildEventListener
import com.google.firebase.database.DataSnapshot
import com.google.firebase.database.DatabaseError
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ValueEventListener
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume

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
    val reactionsJson: String = ""
)

data class FirebaseGroupDto(
    val chatId: String = "",
    val groupName: String = "",
    val groupOwnerId: String = "",
    val members: Map<String, Boolean> = emptyMap(),
    val pinnedMessageId: String = "",
    val createdAt: Long = 0L
)

class FirebaseRepository {
    private val databaseUrl = SecureConfig.getDatabaseUrl()

    private val httpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(5, TimeUnit.SECONDS)
            .writeTimeout(5, TimeUnit.SECONDS)
            .readTimeout(5, TimeUnit.SECONDS)
            .build()
    }

    private val db: FirebaseDatabase? by lazy {
        try {
            FirebaseDatabase.getInstance(databaseUrl)
        } catch (e: Exception) {
            Log.e("FirebaseRepository", "FirebaseDatabase instance error: ${e.message}", e)
            try {
                FirebaseDatabase.getInstance()
            } catch (e2: Exception) {
                null
            }
        }
    }

    suspend fun registerUser(userId: String, username: String, publicKey: String, encryptedBackup: String = ""): Boolean {
        val database = db
        if (database == null) {
            Log.e("FirebaseRepository", "registerUser: db is null")
            return false
        }

        val combinedPublicKey = if (encryptedBackup.isNotBlank()) {
            "$publicKey::ENC::$encryptedBackup"
        } else {
            publicKey
        }

        return withTimeoutOrNull(10000L) {
            try {
                val userMap = mapOf(
                    "userId" to userId,
                    "username" to username,
                    "publicKey" to combinedPublicKey
                )
                Log.d("FirebaseRepository", "Writing user to /users/$userId")
                database.getReference("users").child(userId).setValue(userMap).await()
                Log.d("FirebaseRepository", "User $username ($userId) successfully written to Firebase")
                true
            } catch (e: Exception) {
                Log.e("FirebaseRepository", "registerUser failed: ${e.message}", e)
                false
            }
        } ?: false
    }

    suspend fun getAllUsers(): List<FirebaseUserDto> {
        val database = db ?: return emptyList()
        return withTimeoutOrNull(8000L) {
            suspendCancellableCoroutine<List<FirebaseUserDto>> { continuation ->
                database.getReference("users").addListenerForSingleValueEvent(object : ValueEventListener {
                    override fun onDataChange(snapshot: DataSnapshot) {
                        val list = mutableListOf<FirebaseUserDto>()
                        for (child in snapshot.children) {
                            val uid = child.child("userId").getValue(String::class.java) ?: child.key ?: ""
                            val name = child.child("username").getValue(String::class.java) ?: ""
                            val rawKey = child.child("publicKey").getValue(String::class.java) ?: ""

                             if (name.isNotBlank()) {
                                val actualKey = rawKey.substringBefore("::ENC::")
                                val backup = if (rawKey.contains("::ENC::")) rawKey.substringAfter("::ENC::") else ""
                                val pUrl = child.child("pfpUrl").getValue(String::class.java) ?: ""
                                list.add(FirebaseUserDto(userId = uid, username = name, publicKey = actualKey, encryptedBackup = backup, pfpUrl = pUrl))
                            }
                        }
                        continuation.resume(list)
                    }

                    override fun onCancelled(error: DatabaseError) {
                        Log.e("FirebaseRepository", "getAllUsers cancelled: ${error.message}")
                        continuation.resume(emptyList())
                    }
                })
            }
        } ?: emptyList()
    }

    suspend fun updatePfpUrl(userId: String, encryptedPfpUrl: String): Boolean {
        val database = db ?: return false
        return withTimeoutOrNull(6000L) {
            try {
                database.getReference("users").child(userId).child("pfpUrl").setValue(encryptedPfpUrl).await()
                true
            } catch (e: Exception) {
                Log.e("FirebaseRepository", "updatePfpUrl failed: ${e.message}")
                false
            }
        } ?: false
    }

    suspend fun findUser(query: String): FirebaseUserDto? {
        val cleanQuery = query.trim()
        if (cleanQuery.isBlank()) return null

        // Boost privacy & security: Only allow adding user by exact, complete User ID. No partial matching, no username lookup.
        val database = db ?: return null
        return withTimeoutOrNull(5000L) {
            try {
                val snapshot = database.getReference("users").child(cleanQuery).get().await()
                if (snapshot.exists()) {
                    val uid = snapshot.child("userId").getValue(String::class.java) ?: snapshot.key ?: ""
                    val name = snapshot.child("username").getValue(String::class.java) ?: ""
                    val rawKey = snapshot.child("publicKey").getValue(String::class.java) ?: ""
                    val pUrl = snapshot.child("pfpUrl").getValue(String::class.java) ?: ""
                    if (uid.isNotBlank() && name.isNotBlank()) {
                        val actualKey = rawKey.substringBefore("::ENC::")
                        val backup = if (rawKey.contains("::ENC::")) rawKey.substringAfter("::ENC::") else ""
                        FirebaseUserDto(userId = uid, username = name, publicKey = actualKey, encryptedBackup = backup, pfpUrl = pUrl)
                    } else null
                } else null
            } catch (e: Exception) {
                Log.e("FirebaseRepository", "findUser by ID failed: ${e.message}")
                null
            }
        }
    }

    suspend fun findUserByUsername(usernameQuery: String): FirebaseUserDto? {
        val cleanQuery = usernameQuery.trim()
        if (cleanQuery.isBlank()) return null
        val allUsers = getAllUsers()
        return allUsers.firstOrNull { it.username.equals(cleanQuery, ignoreCase = true) }
    }

    suspend fun findUserById(userId: String): FirebaseUserDto? {
        return findUser(userId)
    }

    suspend fun sendMessage(
        chatId: String,
        messageId: String,
        senderId: String,
        receiverId: String,
        ciphertext: String,
        nonce: String,
        timestamp: Long,
        senderUsername: String = "",
        replyToId: String = "",
        replyToText: String = "",
        replyToSender: String = ""
    ): Boolean {
        val database = db ?: return false
        return withTimeoutOrNull(8000L) {
            try {
                val chatRef = database.getReference("chats").child(chatId)
                val participants = mutableMapOf<String, Any>(
                    senderId to true
                )
                if (receiverId.isNotBlank()) {
                    participants[receiverId] = true
                }
                chatRef.child("participants").updateChildren(participants).await()

                val messageMap = mapOf(
                    "senderId" to senderId,
                    "receiverId" to receiverId,
                    "ciphertext" to ciphertext,
                    "nonce" to nonce,
                    "timestamp" to timestamp,
                    "senderUsername" to senderUsername,
                    "isEdited" to false,
                    "isPinned" to false,
                    "isDeleted" to false,
                    "replyToId" to replyToId,
                    "replyToText" to replyToText,
                    "replyToSender" to replyToSender
                )
                chatRef.child("messages").child(messageId).setValue(messageMap).await()

                // Notify receiver directly so incoming messages appear immediately without needing to add them first!
                if (receiverId.isNotBlank()) {
                    try {
                        val inboxData = mapOf<String, Any>(
                            "chatId" to chatId,
                            "senderId" to senderId,
                            "senderUsername" to senderUsername,
                            "timestamp" to timestamp
                        )
                        database.getReference("users").child(receiverId).child("inbox").child(chatId).setValue(inboxData)
                    } catch (eInbox: Exception) {
                        Log.w("FirebaseRepository", "Inbox notification failed: ${eInbox.message}")
                    }
                }
                true
            } catch (e: Exception) {
                Log.e("FirebaseRepository", "sendMessage error: ${e.message}", e)
                false
            }
        } ?: false
    }

    suspend fun sendReaction(
        chatId: String,
        reactionId: String,
        senderId: String,
        receiverId: String,
        targetMessageId: String,
        emoji: String,
        timestamp: Long,
        senderUsername: String = ""
    ): Boolean {
        val database = db ?: return false
        if (chatId.isBlank() || targetMessageId.isBlank() || senderId.isBlank() || emoji.isBlank()) return false
        return withTimeoutOrNull(8000L) {
            try {
                // Persist on the target message instead of creating transient message events.
                // This avoids reaction-event/delete loops that can freeze the chat UI.
                database.getReference("chats")
                    .child(chatId)
                    .child("messages")
                    .child(targetMessageId)
                    .child("reactions")
                    .child(senderId)
                    .setValue(emoji)
                    .await()
                true
            } catch (e: Exception) {
                Log.e("FirebaseRepository", "sendReaction failed: ${e.message}", e)
                false
            }
        } ?: false
    }

    suspend fun editMessage(
        chatId: String,
        messageId: String,
        newCiphertext: String,
        newNonce: String
    ): Boolean {
        val database = db ?: return false
        return withTimeoutOrNull(8000L) {
            try {
                val msgRef = database.getReference("chats").child(chatId).child("messages").child(messageId)
                val updates = mapOf<String, Any>(
                    "ciphertext" to newCiphertext,
                    "nonce" to newNonce,
                    "isEdited" to true,
                    "editedAt" to System.currentTimeMillis()
                )
                msgRef.updateChildren(updates).await()
                true
            } catch (e: Exception) {
                Log.e("FirebaseRepository", "editMessage error: ${e.message}", e)
                false
            }
        } ?: false
    }

    suspend fun pinMessage(
        chatId: String,
        messageId: String,
        isPinned: Boolean
    ): Boolean {
        val database = db ?: return false
        return withTimeoutOrNull(8000L) {
            try {
                val chatRef = database.getReference("chats").child(chatId)
                val msgRef = chatRef.child("messages").child(messageId)
                val msgUpdates = mapOf<String, Any>(
                    "isPinned" to isPinned,
                    "pinnedAt" to (if (isPinned) System.currentTimeMillis() else 0L)
                )
                msgRef.updateChildren(msgUpdates).await()

                val infoUpdates = mapOf<String, Any>(
                    "pinnedMessageId" to (if (isPinned) messageId else "")
                )
                chatRef.child("info").updateChildren(infoUpdates).await()
                true
            } catch (e: Exception) {
                Log.e("FirebaseRepository", "pinMessage error: ${e.message}", e)
                false
            }
        } ?: false
    }

    suspend fun createGroup(
        chatId: String,
        groupName: String,
        ownerId: String,
        memberIds: List<String>
    ): Boolean {
        val database = db ?: return false
        return withTimeoutOrNull(10000L) {
            try {
                val allMemberIds = (memberIds + ownerId).distinct()
                val chatRef = database.getReference("chats").child(chatId)

                // Write info
                val membersMap = allMemberIds.associateWith { true }
                val infoMap = mapOf(
                    "chatId" to chatId,
                    "isGroup" to true,
                    "groupName" to groupName,
                    "groupOwnerId" to ownerId,
                    "members" to membersMap,
                    "pinnedMessageId" to "",
                    "createdAt" to System.currentTimeMillis()
                )
                chatRef.child("info").setValue(infoMap).await()

                // Write participants for fast lookup
                chatRef.child("participants").setValue(membersMap).await()

                // Also record in each member's user/groups node for synchronization
                for (uid in allMemberIds) {
                    database.getReference("users").child(uid).child("groups").child(chatId).setValue(groupName)
                }
                true
            } catch (e: Exception) {
                Log.e("FirebaseRepository", "createGroup error: ${e.message}", e)
                false
            }
        } ?: false
    }

    suspend fun addGroupMember(chatId: String, newMemberId: String): Boolean {
        val database = db ?: return false
        return withTimeoutOrNull(8000L) {
            try {
                val chatRef = database.getReference("chats").child(chatId)
                chatRef.child("info").child("members").child(newMemberId).setValue(true).await()
                chatRef.child("participants").child(newMemberId).setValue(true).await()
                database.getReference("users").child(newMemberId).child("groups").child(chatId).setValue(true).await()
                true
            } catch (e: Exception) {
                Log.e("FirebaseRepository", "addGroupMember error: ${e.message}", e)
                false
            }
        } ?: false
    }

    suspend fun getGroupInfo(chatId: String): FirebaseGroupDto? {
        val database = db ?: return null
        return withTimeoutOrNull(6000L) {
            try {
                val snapshot = database.getReference("chats").child(chatId).child("info").get().await()
                if (snapshot.exists()) {
                    val name = snapshot.child("groupName").getValue(String::class.java) ?: ""
                    val owner = snapshot.child("groupOwnerId").getValue(String::class.java) ?: ""
                    val pinned = snapshot.child("pinnedMessageId").getValue(String::class.java) ?: ""
                    val created = snapshot.child("createdAt").getValue(Long::class.java) ?: 0L
                    val membersMap = mutableMapOf<String, Boolean>()
                    for (memberSnap in snapshot.child("members").children) {
                        memberSnap.key?.let { membersMap[it] = true }
                    }
                    FirebaseGroupDto(chatId, name, owner, membersMap, pinned, created)
                } else null
            } catch (e: Exception) {
                Log.e("FirebaseRepository", "getGroupInfo error: ${e.message}")
                null
            }
        }
    }

    suspend fun getUserGroupIds(userId: String): List<String> {
        val database = db ?: return emptyList()
        return withTimeoutOrNull(6000L) {
            try {
                val snapshot = database.getReference("users").child(userId).child("groups").get().await()
                snapshot.children.mapNotNull { it.key }
            } catch (e: Exception) {
                emptyList()
            }
        } ?: emptyList()
    }

    fun observeUserInbox(
        userId: String,
        onInboxReceived: (chatId: String, senderId: String, senderUsername: String, timestamp: Long) -> Unit
    ): ChildEventListener? {
        val database = db ?: return null
        val ref = database.getReference("users").child(userId).child("inbox")
        val listener = object : ChildEventListener {
            override fun onChildAdded(snapshot: DataSnapshot, previousChildName: String?) {
                handleSnapshot(snapshot)
            }

            override fun onChildChanged(snapshot: DataSnapshot, previousChildName: String?) {
                handleSnapshot(snapshot)
            }

            private fun handleSnapshot(snapshot: DataSnapshot) {
                val chatId = snapshot.child("chatId").getValue(String::class.java) ?: snapshot.key ?: return
                val senderId = snapshot.child("senderId").getValue(String::class.java) ?: ""
                val senderUsername = snapshot.child("senderUsername").getValue(String::class.java) ?: ""
                val timestamp = snapshot.child("timestamp").getValue(Long::class.java) ?: System.currentTimeMillis()
                if (chatId.isNotBlank() && senderId.isNotBlank()) {
                    onInboxReceived(chatId, senderId, senderUsername, timestamp)
                }
            }

            override fun onChildRemoved(snapshot: DataSnapshot) {}
            override fun onChildMoved(snapshot: DataSnapshot, previousChildName: String?) {}
            override fun onCancelled(error: DatabaseError) {
                Log.e("FirebaseRepository", "observeUserInbox cancelled: ${error.message}")
            }
        }
        ref.addChildEventListener(listener)
        return listener
    }

    fun observeUserGroups(
        userId: String,
        onGroupAdded: (chatId: String, groupName: String) -> Unit
    ): ChildEventListener? {
        val database = db ?: return null
        val ref = database.getReference("users").child(userId).child("groups")
        val listener = object : ChildEventListener {
            override fun onChildAdded(snapshot: DataSnapshot, previousChildName: String?) {
                val chatId = snapshot.key ?: return
                val groupName = snapshot.getValue(String::class.java) ?: "Group"
                onGroupAdded(chatId, groupName)
            }

            override fun onChildChanged(snapshot: DataSnapshot, previousChildName: String?) {
                val chatId = snapshot.key ?: return
                val groupName = snapshot.getValue(String::class.java) ?: "Group"
                onGroupAdded(chatId, groupName)
            }

            override fun onChildRemoved(snapshot: DataSnapshot) {}
            override fun onChildMoved(snapshot: DataSnapshot, previousChildName: String?) {}
            override fun onCancelled(error: DatabaseError) {
                Log.e("FirebaseRepository", "observeUserGroups cancelled: ${error.message}")
            }
        }
        ref.addChildEventListener(listener)
        return listener
    }

    /**
     * Deletes the message from the Firebase Realtime Database cloud server.
     * Uses both direct HTTP REST DELETE (guaranteed instant removal) and SDK removeValue().
     */
    suspend fun deleteMessage(chatId: String, messageId: String): Boolean {
        return withContext(Dispatchers.IO) {
            var isDeleted = false
            try {
                Log.d("FirebaseRepository", "Executing server delete on /chats/$chatId/messages/$messageId")
                
                // 1. Direct REST DELETE via OkHttp (guaranteed immediate cloud deletion on Google Cloud)
                val url = "$databaseUrl/chats/$chatId/messages/$messageId.json"
                val request = Request.Builder().url(url).delete().build()
                httpClient.newCall(request).execute().use { response ->
                    Log.d("FirebaseRepository", "REST delete result: ${response.code} (success=${response.isSuccessful})")
                    if (response.isSuccessful) {
                        isDeleted = true
                    }
                }
            } catch (e: Exception) {
                Log.e("FirebaseRepository", "REST delete error: ${e.message}", e)
            }

            try {
                // 2. Firebase SDK removeValue to trigger onChildRemoved for active client sockets
                db?.getReference("chats")?.child(chatId)?.child("messages")?.child(messageId)?.removeValue()
                isDeleted = true
            } catch (e: Exception) {
                Log.e("FirebaseRepository", "SDK removeValue error: ${e.message}", e)
            }
            isDeleted
        }
    }

    fun observeMessages(
        chatId: String,
        onMessageReceived: (String, FirebaseMessageDto) -> Unit,
        onMessageDeletedFromServer: (String) -> Unit,
        onMessageUpdated: ((String, FirebaseMessageDto) -> Unit)? = null
    ): ChildEventListener? {
        val database = db ?: return null
        val ref = database.getReference("chats").child(chatId).child("messages")
        val listener = object : ChildEventListener {
            override fun onChildAdded(snapshot: DataSnapshot, previousChildName: String?) {
                val msgId = snapshot.key ?: return
                val senderId = snapshot.child("senderId").getValue(String::class.java) ?: ""
                val receiverId = snapshot.child("receiverId").getValue(String::class.java) ?: ""
                val ciphertext = snapshot.child("ciphertext").getValue(String::class.java) ?: ""
                val nonce = snapshot.child("nonce").getValue(String::class.java) ?: ""
                val timestamp = snapshot.child("timestamp").getValue(Long::class.java) ?: 0L
                val senderUsername = snapshot.child("senderUsername").getValue(String::class.java) ?: ""
                val isEdited = snapshot.child("isEdited").getValue(Boolean::class.java) ?: false
                val editedAt = snapshot.child("editedAt").getValue(Long::class.java) ?: 0L
                val isPinned = snapshot.child("isPinned").getValue(Boolean::class.java) ?: false
                val pinnedAt = snapshot.child("pinnedAt").getValue(Long::class.java) ?: 0L
                val isDeleted = snapshot.child("isDeleted").getValue(Boolean::class.java) ?: false
                val reactionTargetId = snapshot.child("reactionTargetId").getValue(String::class.java) ?: ""
                val reactionEmoji = snapshot.child("reactionEmoji").getValue(String::class.java) ?: ""
                val replyToId = snapshot.child("replyToId").getValue(String::class.java) ?: ""
                val replyToText = snapshot.child("replyToText").getValue(String::class.java) ?: ""
                val replyToSender = snapshot.child("replyToSender").getValue(String::class.java) ?: ""
                val reactionsJson = JSONObject().apply {
                    snapshot.child("reactions").children.forEach { reaction ->
                        val uid = reaction.key
                        val emoji = reaction.getValue(String::class.java)
                        if (!uid.isNullOrBlank() && !emoji.isNullOrBlank()) put(uid, emoji)
                    }
                }.toString()

                if (ciphertext.isNotBlank() || reactionTargetId.isNotBlank() || snapshot.child("reactions").exists()) {
                    onMessageReceived(
                        msgId,
                        FirebaseMessageDto(
                            senderId,
                            receiverId,
                            ciphertext,
                            nonce,
                            timestamp,
                            senderUsername,
                            isEdited,
                            editedAt,
                            isPinned,
                            pinnedAt,
                            isDeleted,
                            reactionTargetId,
                            reactionEmoji,
                            replyToId,
                            replyToText,
                            replyToSender,
                            reactionsJson
                        )
                    )
                }
            }

            override fun onChildChanged(snapshot: DataSnapshot, previousChildName: String?) {
                val msgId = snapshot.key ?: return
                val senderId = snapshot.child("senderId").getValue(String::class.java) ?: ""
                val receiverId = snapshot.child("receiverId").getValue(String::class.java) ?: ""
                val ciphertext = snapshot.child("ciphertext").getValue(String::class.java) ?: ""
                val nonce = snapshot.child("nonce").getValue(String::class.java) ?: ""
                val timestamp = snapshot.child("timestamp").getValue(Long::class.java) ?: 0L
                val senderUsername = snapshot.child("senderUsername").getValue(String::class.java) ?: ""
                val isEdited = snapshot.child("isEdited").getValue(Boolean::class.java) ?: false
                val editedAt = snapshot.child("editedAt").getValue(Long::class.java) ?: 0L
                val isPinned = snapshot.child("isPinned").getValue(Boolean::class.java) ?: false
                val pinnedAt = snapshot.child("pinnedAt").getValue(Long::class.java) ?: 0L
                val isDeleted = snapshot.child("isDeleted").getValue(Boolean::class.java) ?: false
                val reactionTargetId = snapshot.child("reactionTargetId").getValue(String::class.java) ?: ""
                val reactionEmoji = snapshot.child("reactionEmoji").getValue(String::class.java) ?: ""
                val replyToId = snapshot.child("replyToId").getValue(String::class.java) ?: ""
                val replyToText = snapshot.child("replyToText").getValue(String::class.java) ?: ""
                val replyToSender = snapshot.child("replyToSender").getValue(String::class.java) ?: ""
                val reactionsJson = JSONObject().apply {
                    snapshot.child("reactions").children.forEach { reaction ->
                        val uid = reaction.key
                        val emoji = reaction.getValue(String::class.java)
                        if (!uid.isNullOrBlank() && !emoji.isNullOrBlank()) put(uid, emoji)
                    }
                }.toString()

                if (ciphertext.isNotBlank() || reactionTargetId.isNotBlank() || snapshot.child("reactions").exists()) {
                    val dto = FirebaseMessageDto(
                        senderId,
                        receiverId,
                        ciphertext,
                        nonce,
                        timestamp,
                        senderUsername,
                        isEdited,
                        editedAt,
                        isPinned,
                        pinnedAt,
                        isDeleted,
                        reactionTargetId,
                        reactionEmoji,
                        replyToId,
                        replyToText,
                        replyToSender,
                        reactionsJson
                    )
                    onMessageUpdated?.invoke(msgId, dto)
                }
            }

            override fun onChildRemoved(snapshot: DataSnapshot) {
                val msgId = snapshot.key ?: return
                onMessageDeletedFromServer(msgId)
            }

            override fun onChildMoved(snapshot: DataSnapshot, previousChildName: String?) {}

            override fun onCancelled(error: DatabaseError) {
                Log.e("FirebaseRepository", "observeMessages cancelled: ${error.message}")
            }
        }
        ref.addChildEventListener(listener)
        return listener
    }

    fun removeMessageListener(chatId: String, listener: ChildEventListener) {
        db?.getReference("chats")?.child(chatId)?.child("messages")?.removeEventListener(listener)
    }
}
