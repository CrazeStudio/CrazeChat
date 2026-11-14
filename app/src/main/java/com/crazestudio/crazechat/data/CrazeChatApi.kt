package com.crazestudio.crazechat.data

import com.crazestudio.crazechat.security.NativeBridge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

class ApiException(
    override val message: String,
    val statusCode: Int? = null,
    val code: String? = null
) : Exception(message)

class CrazeChatApi {
    private val origin = NativeBridge.nativeApiOrigin().trim()
    private val gatewayKey = NativeBridge.nativeGatewayKey().trim()
    @Volatile var token: String? = null

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .followRedirects(false)
        .followSslRedirects(false)
        .build()

    private fun baseUrl(): HttpUrl {
        if (origin.isBlank()) throw ApiException("CrazeChat API origin is not configured.")
        val base = origin.toHttpUrlOrNull()
            ?: throw ApiException("Invalid CrazeChat API origin.")
        val local = base.host in setOf("localhost", "127.0.0.1", "10.0.2.2")
        if (base.scheme != "https" && !(local && base.scheme == "http")) {
            throw ApiException("CrazeChat only accepts HTTPS API origins.")
        }
        if (base.username.isNotEmpty() || base.password.isNotEmpty() ||
            base.encodedPath !in setOf("", "/") || base.query != null || base.fragment != null) {
            throw ApiException("BURL must be an origin without a path, credentials, query or fragment.")
        }
        if (gatewayKey.isBlank()) {
            throw ApiException("CrazeChat is not configured. Add the KEY build secret to the Gradle build.")
        }
        return base
    }

    private suspend fun request(
        method: String,
        path: String,
        body: JSONObject? = null,
        query: Map<String, String> = emptyMap()
    ): JSONObject = withContext(Dispatchers.IO) {
        val urlBuilder = baseUrl().newBuilder().addPathSegments("db/$path")
        query.forEach { (key, value) -> urlBuilder.addQueryParameter(key, value) }
        val builder = Request.Builder()
            .url(urlBuilder.build())
            .header("Accept", "application/json")
            .header("X-Access-Key", gatewayKey)
        token?.takeIf { it.isNotBlank() }?.let { builder.header("Authorization", "Bearer $it") }
        if (body != null) builder.header("Content-Type", "application/json")
        val requestBody = body?.toString()?.toRequestBody("application/json; charset=utf-8".toMediaType())
        val request = when (method) {
            "GET" -> builder.get().build()
            "POST" -> builder.post(requireNotNull(requestBody)).build()
            "DELETE" -> builder.delete().build()
            else -> throw ApiException("Unsupported request method.")
        }
        try {
            client.newCall(request).execute().use { response ->
                val raw = response.body?.string().orEmpty()
                val root = if (raw.isBlank()) JSONObject() else runCatching { JSONObject(raw) }
                    .getOrElse { throw ApiException("CrazeStudio-Web returned invalid JSON.") }
                val errorCode = root.optString("error").takeIf { it.isNotBlank() }
                if (!response.isSuccessful || root.optBoolean("ok") == false) {
                    throw ApiException(
                        root.optString("message").ifBlank {
                            root.optString("error").ifBlank { "CrazeChat request failed (HTTP ${response.code})." }
                        },
                        response.code,
                        errorCode
                    )
                }
                root.optJSONObject("result") ?: root
            }
        } catch (error: ApiException) {
            throw error
        } catch (error: IOException) {
            throw ApiException("Could not connect to CrazeStudio-Web. Check your internet connection.")
        }
    }

    suspend fun register(username: String, password: String, envelope: JSONObject): JSONObject =
        request("POST", "auth/register", JSONObject()
            .put("username", username)
            .put("password", password)
            .put("publicKey", envelope.getString("publicKey"))
            .put("identityEnvelope", envelope))

    suspend fun login(username: String, password: String) =
        request("POST", "auth/login", JSONObject().put("username", username).put("password", password))

    suspend fun restoreSession() = request("GET", "auth/session")

    suspend fun changePassword(
        currentPassword: String,
        newPassword: String,
        identityEnvelope: JSONObject
    ) = request("POST", "auth/change-password", JSONObject()
        .put("currentPassword", currentPassword)
        .put("newPassword", newPassword)
        .put("identityEnvelope", identityEnvelope))

    suspend fun updateIdentityEnvelope(identityEnvelope: JSONObject) =
        request("POST", "auth/update-identity", JSONObject()
            .put("identityEnvelope", identityEnvelope))
    suspend fun listChats() = request("GET", "chats")
    suspend fun createChat(username: String) = request("POST", "chats", JSONObject().put("username", username))
    suspend fun searchUsers(query: String) = request("GET", "users/search", query = mapOf("query" to query))
    suspend fun getMessages(chatId: String, since: Long?) = request(
        "GET", "chats/$chatId/messages",
        query = buildMap {
            put("limit", "100")
            if (since != null && since > 0) put("since", since.toString())
        }
    )

    suspend fun sendMessage(chatId: String, message: JSONObject) =
        request("POST", "chats/$chatId/messages", JSONObject().put("message", message))

    suspend fun acknowledgeMessages(chatId: String, ids: List<String>, status: String) {
        if (ids.isEmpty()) return
        request("POST", "chats/$chatId/messages/acknowledge",
            JSONObject().put("status", status).put("messageIds", org.json.JSONArray(ids)))
    }

    suspend fun deleteMessage(chatId: String, messageId: String) =
        request("DELETE", "chats/$chatId/messages/$messageId")

    suspend fun updatePhoto(url: String?) =
        request("POST", "profile", JSONObject().put("photoUrl", url))

    suspend fun registerPush(fid: String, sound: Boolean, vibration: Boolean) =
        request("POST", "push/register", JSONObject()
            .put("fid", fid)
            .put("soundEnabled", sound)
            .put("vibrationEnabled", vibration))

    suspend fun unregisterPush(fid: String) =
        request("POST", "push/unregister", JSONObject().put("fid", fid))

    fun openRealtime(chatId: String, listener: WebSocketListener): WebSocket {
        val base = baseUrl()
        val scheme = if (base.scheme == "https") "wss://" else "ws://"
        val portSuffix = if ((base.scheme == "https" && base.port != 443) ||
            (base.scheme == "http" && base.port != 80)) ":${base.port}" else ""
        val url = scheme + base.host + portSuffix + "/api/realtime/$chatId"
        val request = Request.Builder().url(url)
            .header("X-Access-Key", gatewayKey)
            .header("Authorization", "Bearer ${token.orEmpty()}")
            .build()
        return client.newWebSocket(request, listener)
    }
}
