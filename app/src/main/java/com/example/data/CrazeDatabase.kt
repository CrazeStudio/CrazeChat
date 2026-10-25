package com.example.data

import android.content.Context
import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Entity(tableName = "account_profiles")
data class AccountProfileEntity(
    @PrimaryKey val userId: String,
    val username: String,
    val password: String,
    val publicKey: String,
    /** AES-GCM ciphertext at rest; decrypt only when the app needs the key. */
    val privateKey: String,
    val createdAt: Long = System.currentTimeMillis()
) {
    val privateKeyPlain: String get() = SecureVault.decrypt(privateKey).orEmpty()
}

@Dao
interface ProfileDao {
    @Query("SELECT * FROM account_profiles ORDER BY createdAt ASC")
    fun getAllProfilesFlow(): Flow<List<AccountProfileEntity>>

    @Query("SELECT * FROM account_profiles ORDER BY createdAt ASC")
    suspend fun getAllProfiles(): List<AccountProfileEntity>

    @Query("SELECT * FROM account_profiles WHERE userId = :userId")
    suspend fun getProfile(userId: String): AccountProfileEntity?

    @Query("SELECT * FROM account_profiles WHERE username = :username")
    suspend fun getProfileByUsername(username: String): AccountProfileEntity?

    @Query("SELECT COUNT(*) FROM account_profiles")
    suspend fun getProfileCount(): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertProfile(profile: AccountProfileEntity)

    @Delete
    suspend fun deleteProfile(profile: AccountProfileEntity)

    @Query("DELETE FROM account_profiles WHERE userId = :userId")
    suspend fun deleteProfileById(userId: String)
}

@Entity(tableName = "chats", primaryKeys = ["ownerUserId", "chatId"])
data class ChatEntity(
    val ownerUserId: String,
    val chatId: String,
    val peerUserId: String,
    val peerUsername: String,
    val peerPublicKey: String,
    val lastMessage: String,
    val lastTimestamp: Long,
    val unreadCount: Int = 0,
    val isGroup: Boolean = false,
    val groupName: String = "",
    val groupOwnerId: String = "",
    val memberIdsJson: String = "",
    val pinnedMessageId: String = ""
)

@Dao
interface ChatDao {
    @Query("SELECT * FROM chats WHERE ownerUserId = :ownerUserId ORDER BY lastTimestamp DESC")
    fun getChatsForUser(ownerUserId: String): Flow<List<ChatEntity>>

    @Query("SELECT * FROM chats WHERE ownerUserId = :ownerUserId AND chatId = :chatId")
    suspend fun getChatById(ownerUserId: String, chatId: String): ChatEntity?

    @Query("SELECT * FROM chats WHERE ownerUserId = :ownerUserId AND peerUserId = :peerUserId")
    suspend fun getChatByPeerUserId(ownerUserId: String, peerUserId: String): ChatEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertChat(chat: ChatEntity)

    @Query("UPDATE chats SET pinnedMessageId = :pinnedMessageId WHERE ownerUserId = :ownerUserId AND chatId = :chatId")
    suspend fun updatePinnedMessageId(ownerUserId: String, chatId: String, pinnedMessageId: String)

    @Query("DELETE FROM chats WHERE ownerUserId = :ownerUserId AND chatId = :chatId")
    suspend fun deleteChat(ownerUserId: String, chatId: String)

    @Query("DELETE FROM chats WHERE ownerUserId = :ownerUserId")
    suspend fun deleteChatsForUser(ownerUserId: String)
}

@Entity(tableName = "messages")
data class MessageEntity(
    @PrimaryKey val messageId: String,
    val chatId: String,
    val senderId: String,
    val receiverId: String,
    val plaintext: String,
    val ciphertext: String,
    val nonce: String,
    val timestamp: Long,
    val status: String = "RECEIVED", // SENDING, SENT, DELIVERED, READ, SERVER_DELETED
    val senderUsername: String = "",
    val isEdited: Boolean = false,
    val editedAt: Long = 0L,
    val isPinned: Boolean = false,
    val pinnedAt: Long = 0L,
    val isDeleted: Boolean = false,
    val reactionsJson: String = "", // JSON map of userId to emoji
    val replyToId: String = "",
    val replyToText: String = "",
    val replyToSender: String = ""
) {
    /** Decrypted only on demand; persisted plaintext uses Android Keystore AES-GCM. */
    val plaintextValue: String get() = SecureVault.decrypt(plaintext).orEmpty()
    val replyToTextValue: String get() =
        if (replyToText.startsWith("ENCv1|")) replyToText else SecureVault.decrypt(replyToText).orEmpty()
}

@Dao
interface MessageDao {
    @Query("SELECT * FROM messages WHERE chatId = :chatId ORDER BY timestamp ASC")
    fun getMessagesForChat(chatId: String): Flow<List<MessageEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertMessage(message: MessageEntity)

    @Query("SELECT * FROM messages")
    suspend fun getAllMessagesForMigration(): List<MessageEntity>

    @Query("UPDATE messages SET status = :status WHERE messageId = :messageId")
    suspend fun updateMessageStatus(messageId: String, status: String)

    @Query("UPDATE messages SET plaintext = :plaintext, ciphertext = :ciphertext, nonce = :nonce, isEdited = 1, editedAt = :editedAt WHERE messageId = :messageId")
    suspend fun updateMessageContent(messageId: String, plaintext: String, ciphertext: String, nonce: String, editedAt: Long)

    @Query("UPDATE messages SET isPinned = :isPinned, pinnedAt = :pinnedAt WHERE messageId = :messageId")
    suspend fun updatePinStatus(messageId: String, isPinned: Boolean, pinnedAt: Long)

    @Query("UPDATE messages SET isDeleted = :isDeleted WHERE messageId = :messageId")
    suspend fun updateDeletedStatus(messageId: String, isDeleted: Boolean)

    @Query("UPDATE messages SET reactionsJson = :reactionsJson WHERE messageId = :messageId")
    suspend fun updateReactions(messageId: String, reactionsJson: String)

    @Query("SELECT * FROM messages WHERE chatId = :chatId AND isPinned = 1 ORDER BY pinnedAt DESC")
    fun getPinnedMessages(chatId: String): Flow<List<MessageEntity>>

    @Query("SELECT * FROM messages WHERE messageId = :messageId")
    suspend fun getMessageById(messageId: String): MessageEntity?

    @Query("DELETE FROM messages WHERE messageId = :messageId")
    suspend fun deleteMessageById(messageId: String)

    @Query("DELETE FROM messages WHERE chatId = :chatId AND status IN ('READ', 'SERVER_DELETED')")
    suspend fun deleteReadMessages(chatId: String)

    @Query("DELETE FROM messages WHERE chatId = :chatId")
    suspend fun deleteAllMessagesForChat(chatId: String)
}

@Database(entities = [AccountProfileEntity::class, ChatEntity::class, MessageEntity::class], version = 5, exportSchema = false)
abstract class CrazeDatabase : RoomDatabase() {
    abstract fun profileDao(): ProfileDao
    abstract fun chatDao(): ChatDao
    abstract fun messageDao(): MessageDao

    companion object {
        @Volatile
        private var INSTANCE: CrazeDatabase? = null

        fun getDatabase(context: Context): CrazeDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    CrazeDatabase::class.java,
                    "craze_chat_db"
                )
                    .fallbackToDestructiveMigration()
                    .build()
                INSTANCE = instance
                instance
            }
        }
    }
}
