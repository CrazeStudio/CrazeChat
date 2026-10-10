package com.example.data

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

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
    val privateKeyFlow: Flow<String?> = context.dataStore.data.map { prefs -> prefs[KEY_PRIVATE_KEY] }

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
            prefs[KEY_PRIVATE_KEY] = privateKey
        }
    }

    suspend fun setActiveProfile(profile: AccountProfileEntity) {
        saveUserSession(
            userId = profile.userId,
            username = profile.username,
            publicKey = profile.publicKey,
            privateKey = profile.privateKey
        )
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
