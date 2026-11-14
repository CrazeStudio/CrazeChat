package com.crazestudio.crazechat.data

import org.json.JSONArray
import org.json.JSONObject

data class ChatUser(
    val id: String,
    val username: String,
    val publicKey: String,
    val photoUrl: String? = null
) {
    fun toJson() = JSONObject()
        .put("id", id)
        .put("username", username)
        .put("publicKey", publicKey)
        .put("photoUrl", photoUrl)
    companion object {
        fun fromJson(value: JSONObject) = ChatUser(
            id = value.optString("id"),
            username = value.optString("username"),
            publicKey = value.optString("publicKey"),
            photoUrl = value.optString("photoUrl").takeIf { it.isNotBlank() && it != "null" }
        )
    }
}

data class ChatSummary(
    val id: String,
    val members: List<ChatUser>,
    val updatedAt: Long
) {
    fun peer(myId: String) = members.firstOrNull { it.id != myId }
    companion object {
        fun fromJson(value: JSONObject): ChatSummary {
            val array = value.optJSONArray("members") ?: JSONArray()
            val users = (0 until array.length()).mapNotNull { index ->
                array.optJSONObject(index)?.let(ChatUser::fromJson)
            }
            return ChatSummary(
                id = value.optString("id"),
                members = users,
                updatedAt = value.optLong("lastMessageAt", value.optLong("updatedAt", value.optLong("createdAt")))
            )
        }
    }
}

data class ChatMessage(
    val id: String,
    val senderId: String,
    val ciphertext: String,
    val nonce: String,
    val mac: String,
    val createdAt: Long,
    val deliveryState: String,
    val clearText: String
) {
    fun toJson() = JSONObject()
        .put("id", id)
        .put("senderId", senderId)
        .put("format", "cc-e2ee-v1")
        .put("ciphertext", ciphertext)
        .put("nonce", nonce)
        .put("mac", mac)
        .put("createdAt", createdAt)
        .put("deliveryState", deliveryState)

    fun envelopeOnly() = JSONObject()
        .put("id", id)
        .put("senderId", senderId)
        .put("format", "cc-e2ee-v1")
        .put("ciphertext", ciphertext)
        .put("nonce", nonce)
        .put("mac", mac)
        .put("createdAt", createdAt)
        .put("deliveryState", deliveryState)

    companion object {
        fun fromJson(value: JSONObject, clearText: String = "") = ChatMessage(
            id = value.optString("id"),
            senderId = value.optString("senderId"),
            ciphertext = value.optString("ciphertext"),
            nonce = value.optString("nonce"),
            mac = value.optString("mac"),
            createdAt = value.optLong("createdAt"),
            deliveryState = value.optString("deliveryState", "sent"),
            clearText = clearText
        )
    }
}
