package com.example.data

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.first

val Context.dataStore by preferencesDataStore(name = "craze_chat_prefs")

class UserPreferences(private val context: Context) {

    companion object {
        val KEY_USER_ID = stringPreferencesKey("user_id")
        val KEY_USERNAME = stringPreferencesKey("username")
        val KEY_PUBLIC_KEY = stringPreferencesKey("public_key")
        val KEY_PRIVATE_KEY = stringPreferencesKey("private_key")
        val KEY_ACTIVE_USER_ID = stringPreferencesKey("active_user_id")
        val KEY_THEME_MODE = stringPreferencesKey("theme_mode")
        val KEY_SOUND_EFFECTS = booleanPreferencesKey("sound_effects_enabled")
        val KEY_HAPTIC_FEEDBACK = booleanPreferencesKey("haptic_feedback_enabled")
    }

    val themeModeFlow: Flow<String?> = context.dataStore.data.map { prefs -> prefs[KEY_THEME_MODE] ?: "light" }
    val soundEffectsEnabledFlow: Flow<Boolean> = context.dataStore.data.map { prefs -> prefs[KEY_SOUND_EFFECTS] ?: true }
    val hapticFeedbackEnabledFlow: Flow<Boolean> = context.dataStore.data.map { prefs -> prefs[KEY_HAPTIC_FEEDBACK] ?: true }
    val activeUserIdFlow: Flow<String?> = context.dataStore.data.map { prefs -> prefs[KEY_ACTIVE_USER_ID] ?: prefs[KEY_USER_ID] }
    val userIdFlow: Flow<String?> = context.dataStore.data.map { prefs -> prefs[KEY_USER_ID] }
    val usernameFlow: Flow<String?> = context.dataStore.data.map { prefs -> prefs[KEY_USERNAME] }
    val publicKeyFlow: Flow<String?> = context.dataStore.data.map { prefs -> prefs[KEY_PUBLIC_KEY] }
    val privateKeyFlow: Flow<String?> = context.dataStore.data.map { prefs -> SecureVault.decrypt(prefs[KEY_PRIVATE_KEY]) }

    suspend fun setSoundEffectsEnabled(enabled: Boolean) {
        context.dataStore.edit { prefs ->
            prefs[KEY_SOUND_EFFECTS] = enabled
        }
    }

    suspend fun setHapticFeedbackEnabled(enabled: Boolean) {
        context.dataStore.edit { prefs ->
            prefs[KEY_HAPTIC_FEEDBACK] = enabled
        }
    }

    suspend fun saveUserSession(userId: String, username: String, publicKey: String, privateKey: String) {
        context.dataStore.edit { prefs ->
            prefs[KEY_ACTIVE_USER_ID] = userId
            prefs[KEY_USER_ID] = userId
            prefs[KEY_USERNAME] = username
            prefs[KEY_PUBLIC_KEY] = publicKey
            prefs[KEY_PRIVATE_KEY] = SecureVault.encrypt(privateKey)
        }
    }

    suspend fun setActiveProfile(profile: AccountProfileEntity) {
        saveUserSession(
            userId = profile.userId,
            username = profile.username,
            publicKey = profile.publicKey,
            privateKey = profile.privateKeyPlain
        )
    }

    private fun apiTokenKey(userId: String) = stringPreferencesKey("api_token_$userId")

    /** Stores account session tokens encrypted with a key held by Android Keystore. */
    suspend fun saveApiToken(userId: String, token: String) {
        if (userId.isBlank() || token.isBlank()) return
        context.dataStore.edit { prefs ->
            prefs[apiTokenKey(userId)] = SecureVault.encrypt(token)
        }
    }

    suspend fun getApiToken(userId: String): String? {
        if (userId.isBlank()) return null
        return context.dataStore.data.map { prefs ->
            SecureVault.decrypt(prefs[apiTokenKey(userId)])
        }.first()
    }

    suspend fun saveApiRefreshToken(userId: String, token: String) {
        if (userId.isBlank() || token.isBlank()) return
        context.dataStore.edit { prefs ->
            prefs[stringPreferencesKey("api_refresh_token_$userId")] = SecureVault.encrypt(token)
        }
    }

    suspend fun getApiRefreshToken(userId: String): String? {
        if (userId.isBlank()) return null
        val key = stringPreferencesKey("api_refresh_token_$userId")
        return context.dataStore.data.map { prefs -> SecureVault.decrypt(prefs[key]) }.first()
    }

    suspend fun clearApiSession(userId: String) {
        if (userId.isBlank()) return
        context.dataStore.edit { prefs ->
            prefs.remove(apiTokenKey(userId))
            prefs.remove(stringPreferencesKey("api_refresh_token_$userId"))
        }
    }

    suspend fun clearApiToken(userId: String) {
        if (userId.isBlank()) return
        context.dataStore.edit { prefs -> prefs.remove(apiTokenKey(userId)) }
    }

    private fun groupKeyPreference(userId: String, chatId: String, version: Int) =
        stringPreferencesKey(
            "group_key_${userId}_${android.util.Base64.encodeToString(chatId.toByteArray(Charsets.UTF_8), android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP or android.util.Base64.NO_PADDING)}_v${version}"
        )

    /** Each group's random encryption secret is encrypted with the device's Android Keystore key. */
    suspend fun saveGroupKey(userId: String, chatId: String, version: Int, groupKey: String) {
        if (userId.isBlank() || chatId.isBlank() || version <= 0 || !CryptoManager.isValidGroupKey(groupKey)) return
        val preferenceKey = groupKeyPreference(userId, chatId, version)
        context.dataStore.edit { prefs -> prefs[preferenceKey] = SecureVault.encrypt(groupKey) }
    }

    suspend fun getGroupKey(userId: String, chatId: String, version: Int): String? {
        if (userId.isBlank() || chatId.isBlank() || version <= 0) return null
        val preferenceKey = groupKeyPreference(userId, chatId, version)
        return context.dataStore.data.map { prefs ->
            SecureVault.decrypt(prefs[preferenceKey])?.takeIf(CryptoManager::isValidGroupKey)
        }.first()
    }

    suspend fun clearGroupKeys(userId: String, chatId: String, throughVersion: Int = Int.MAX_VALUE) {
        if (userId.isBlank() || chatId.isBlank()) return
        context.dataStore.edit { prefs ->
            (1..throughVersion.coerceAtMost(10000)).forEach { version ->
                prefs.remove(groupKeyPreference(userId, chatId, version))
            }
        }
    }

    suspend fun setThemeMode(mode: String) {
        context.dataStore.edit { prefs ->
            prefs[KEY_THEME_MODE] = mode
        }
    }

    suspend fun clearSession() {
        context.dataStore.edit { prefs ->
            prefs.clear()
        }
    }
}
