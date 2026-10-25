package com.example.viewmodel

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.data.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.UUID

sealed class AuthState {
    object Loading : AuthState()
    object NeedsRegistration : AuthState()
    object Authenticated : AuthState()
    data class Error(val message: String) : AuthState()
}

class AuthViewModel(application: Application) : AndroidViewModel(application) {
    private val db = CrazeDatabase.getDatabase(application)
    private val profileDao = db.profileDao()
    private val userPrefs = UserPreferences(application)
    private val firebaseRepo = FirebaseRepository(application)

    private val _authState = MutableStateFlow<AuthState>(AuthState.Loading)
    val authState: StateFlow<AuthState> = _authState.asStateFlow()

    val profiles: StateFlow<List<AccountProfileEntity>> = profileDao.getAllProfilesFlow()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val canAddProfile: StateFlow<Boolean> = profiles.map { it.size < 2 }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)

    val userIdFlow = userPrefs.userIdFlow
    val usernameFlow = userPrefs.usernameFlow
    val publicKeyFlow = userPrefs.publicKeyFlow
    val privateKeyFlow = userPrefs.privateKeyFlow

    val themeMode: StateFlow<String> = userPrefs.themeModeFlow
        .map { it ?: "light" }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "light")

    val soundEffectsEnabled: StateFlow<Boolean> = userPrefs.soundEffectsEnabledFlow
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)

    val hapticFeedbackEnabled: StateFlow<Boolean> = userPrefs.hapticFeedbackEnabledFlow
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)

    val showOnlineStatus: StateFlow<Boolean> = userPrefs.showOnlineStatusFlow
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)
    val readReceiptsEnabled: StateFlow<Boolean> = userPrefs.readReceiptsFlow
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)
    val allowDiscovery: StateFlow<Boolean> = userPrefs.allowDiscoveryFlow
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)
    val allowGroupInvites: StateFlow<Boolean> = userPrefs.allowGroupInvitesFlow
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), true)

    private val _privacySyncError = MutableStateFlow<String?>(null)
    val privacySyncError: StateFlow<String?> = _privacySyncError.asStateFlow()

    fun setThemeMode(mode: String) {
        viewModelScope.launch {
            userPrefs.setThemeMode(mode)
        }
    }

    fun setSoundEffectsEnabled(enabled: Boolean) {
        viewModelScope.launch {
            userPrefs.setSoundEffectsEnabled(enabled)
        }
    }

    fun setHapticFeedbackEnabled(enabled: Boolean) {
        viewModelScope.launch {
            userPrefs.setHapticFeedbackEnabled(enabled)
        }
    }

    fun setPrivacySetting(name: String, enabled: Boolean) {
        viewModelScope.launch {
            val uid = userPrefs.userIdFlow.first().orEmpty()
            if (uid.isBlank()) {
                _privacySyncError.value = "Sign in to save privacy settings."
                return@launch
            }
            val previous = when (name) {
                "showOnlineStatus" -> userPrefs.showOnlineStatusFlow.first()
                "readReceipts" -> userPrefs.readReceiptsFlow.first()
                "allowDiscovery" -> userPrefs.allowDiscoveryFlow.first()
                "allowGroupInvites" -> userPrefs.allowGroupInvitesFlow.first()
                else -> return@launch
            }
            userPrefs.setPrivacyPreference(name, enabled)
            _privacySyncError.value = null
            try {
                firebaseRepo.updatePrivacySetting(uid, name, enabled)
            } catch (e: Exception) {
                userPrefs.setPrivacyPreference(name, previous)
                _privacySyncError.value = e.message ?: "Could not save privacy setting to the server."
                Log.w("AuthViewModel", "Privacy setting update failed", e)
            }
        }
    }

    private suspend fun refreshPrivacySettings(userId: String) {
        try {
            val settings = firebaseRepo.getPrivacySettings(userId)
            userPrefs.savePrivacySettings(
                showOnlineStatus = settings.optBoolean("showOnlineStatus", true),
                readReceipts = settings.optBoolean("readReceipts", true),
                allowDiscovery = settings.optBoolean("allowDiscovery", true),
                allowGroupInvites = settings.optBoolean("allowGroupInvites", true)
            )
            _privacySyncError.value = null
        } catch (e: Exception) {
            Log.w("AuthViewModel", "Could not fetch server privacy settings: " + e.message)
        }
    }

    init {
        migrateLocalPrivateKeys()
        checkSession()
    }

    private fun migrateLocalPrivateKeys() {
        viewModelScope.launch {
            try {
                profileDao.getAllProfiles().forEach { profile ->
                    if (profile.privateKey.isNotBlank() && !profile.privateKey.startsWith("enc:")) {
                        profileDao.insertProfile(profile.copy(privateKey = SecureVault.encrypt(profile.privateKey)))
                    }
                }
                val activeId = userPrefs.userIdFlow.first().orEmpty()
                if (activeId.isNotBlank()) {
                    val activeProfile = profileDao.getProfile(activeId)
                    if (activeProfile != null && activeProfile.privateKeyPlain.isNotBlank()) {
                        userPrefs.setActiveProfile(activeProfile)
                    } else if (activeId.isNotBlank()) {
                        // Android Keystore keys are device-bound. If a restored DB cannot be
                        // decrypted, require password-based cloud recovery rather than using a blank key.
                        userPrefs.clearSession()
                    }
                }
            } catch (e: Exception) {
                Log.w("AuthViewModel", "Secure local key migration could not complete: ${e.message}")
            }
        }
    }

    fun checkSession() {
        viewModelScope.launch {
            userPrefs.userIdFlow.collect { userId ->
                if (userId.isNullOrEmpty()) {
                    _authState.value = AuthState.NeedsRegistration
                } else {
                    _authState.value = AuthState.Authenticated
                    refreshPrivacySettings(userId)
                }
            }
        }
    }

    fun logout() {
        viewModelScope.launch {
            val uid = userPrefs.userIdFlow.first().orEmpty()
            if (uid.isNotBlank()) firebaseRepo.logoutAccount(uid)
            userPrefs.clearSession()
            _authState.value = AuthState.NeedsRegistration
        }
    }

    fun switchProfile(profile: AccountProfileEntity) {
        viewModelScope.launch {
            userPrefs.setActiveProfile(profile)
            _authState.value = AuthState.Authenticated
        }
    }

    fun loginUser(username: String, password: String, onComplete: (Boolean) -> Unit) {
        if (username.isBlank() || password.isBlank()) {
            _authState.value = AuthState.Error("Username and password cannot be empty")
            onComplete(false)
            return
        }

        viewModelScope.launch {
            try {
                _authState.value = AuthState.Loading
                val cleanUsername = username.trim()
                // The backend verifies the password; the APK contains no shared API password.
                val authResponse = firebaseRepo.loginAccount(cleanUsername, password)
                val remoteAccount = authResponse.optJSONObject("user")
                    ?: throw IllegalStateException("The server returned no account.")
                val accountUid = remoteAccount.optString("userId")
                val canonicalUsername = remoteAccount.optString("username", cleanUsername)
                if (accountUid.isBlank()) throw IllegalStateException("The account ID is missing.")

                val remoteProfile = firebaseRepo.getAccountProfile(accountUid)
                val localProfile = profileDao.getProfileByUsername(cleanUsername)
                    ?: profileDao.getProfileByUsername(canonicalUsername)

                val profile: AccountProfileEntity = if (
                    localProfile != null && localProfile.privateKeyPlain.isNotBlank() &&
                    (remoteProfile?.publicKey.isNullOrBlank() || localProfile.publicKey == remoteProfile?.publicKey)
                ) {
                    AccountProfileEntity(
                        userId = accountUid,
                        username = canonicalUsername,
                        password = withContext(Dispatchers.IO) { CryptoManager.hashPassword(password) },
                        publicKey = localProfile.publicKey,
                        privateKey = SecureVault.encrypt(localProfile.privateKeyPlain)
                    )
                } else {
                    val encryptedBackup = remoteProfile?.encryptedBackup.orEmpty()
                    if (encryptedBackup.isBlank()) {
                        throw IllegalStateException("Account signed in, but no compatible encrypted key backup exists on this device or server.")
                    }
                    val backupUsername = remoteProfile?.username?.ifBlank { canonicalUsername } ?: canonicalUsername
                    val decrypted = withContext(Dispatchers.IO) { CryptoManager.decryptProfile(password, backupUsername, encryptedBackup) }
                        ?: throw IllegalStateException("Password accepted, but the encrypted key backup could not be opened. Keep the old device until recovery is fixed.")
                    val parts = decrypted.split("|")
                    if (parts.size < 5 || parts[3].isBlank() || parts[4].isBlank()) {
                        throw IllegalStateException("The encrypted profile backup is incomplete.")
                    }
                    AccountProfileEntity(
                        userId = accountUid,
                        username = canonicalUsername,
                        password = withContext(Dispatchers.IO) { CryptoManager.hashPassword(password) },
                        publicKey = parts[3],
                        privateKey = SecureVault.encrypt(parts[4])
                    )
                }

                if (localProfile != null && localProfile.userId != accountUid) {
                    profileDao.deleteProfileById(localProfile.userId)
                }
                profileDao.insertProfile(profile)
                userPrefs.setActiveProfile(profile)

                // Re-wrap the profile backup with the current password after successful sign-in.
                val backupPayload = "${profile.userId}|${profile.username}|${profile.password}|${profile.publicKey}|${profile.privateKeyPlain}"
                val encryptedBackup = withContext(Dispatchers.IO) { CryptoManager.encryptProfile(password, profile.username, backupPayload) }
                val uploaded = firebaseRepo.registerUser(accountUid, profile.username, profile.publicKey, encryptedBackup)
                if (!uploaded) Log.w("AuthViewModel", "Signed in locally; profile backup refresh failed")
                _authState.value = AuthState.Authenticated
                onComplete(true)
            } catch (e: Exception) {
                // Preserve access to this device's locally encrypted chats during network outages.
                // Never use local fallback after the backend explicitly rejects a password.
                val canFallbackOffline = e !is FirebaseRepository.ApiException || e.status >= 500
                val local = if (canFallbackOffline) profileDao.getProfileByUsername(username.trim()) else null
                if (local != null && local.privateKeyPlain.isNotBlank()) {
                    val validLocalPassword = withContext(Dispatchers.IO) {
                        CryptoManager.verifyPassword(password, local.password)
                    }
                    if (validLocalPassword) {
                        val strongHash = withContext(Dispatchers.IO) { CryptoManager.hashPassword(password) }
                        val securedProfile = local.copy(
                            password = strongHash,
                            privateKey = SecureVault.encrypt(local.privateKeyPlain)
                        )
                        profileDao.insertProfile(securedProfile)
                        userPrefs.setActiveProfile(securedProfile)
                        _authState.value = AuthState.Authenticated
                        onComplete(true)
                        return@launch
                    }
                }
                val message = e.message?.takeIf { it.isNotBlank() } ?: "Login failed"
                _authState.value = AuthState.Error(message)
                onComplete(false)
            }
        }
    }

    fun registerUser(username: String, password: String, onComplete: (Boolean, String?) -> Unit) {
        val cleanUsername = username.trim()
        if (cleanUsername.length !in 3..24 || !cleanUsername.matches(Regex("^[A-Za-z0-9_]+$"))) {
            _authState.value = AuthState.Error("Username must be 3–24 characters using letters, numbers, or underscore.")
            onComplete(false, null)
            return
        }
        if (password.length !in 10..128) {
            _authState.value = AuthState.Error("Password must be 10–128 characters.")
            onComplete(false, null)
            return
        }

        viewModelScope.launch {
            try {
                val currentCount = profileDao.getProfileCount()
                if (currentCount >= 2) {
                    _authState.value = AuthState.Error("Device limit reached (max 2 accounts allowed on this phone).")
                    onComplete(false, null)
                    return@launch
                }
                val existingLocal = profileDao.getProfileByUsername(cleanUsername)
                if (existingLocal != null) {
                    _authState.value = AuthState.Error("Username already exists on this device. Please log in.")
                    onComplete(false, null)
                    return@launch
                }

                _authState.value = AuthState.Loading
                val keyPair = CryptoManager.generateKeyPair()
                val hashedPassword = withContext(Dispatchers.IO) { CryptoManager.hashPassword(password) }

                // The server generates the canonical account ID and stores only a scrypt hash.
                val response = firebaseRepo.registerAccount(cleanUsername, password)
                val remoteAccount = response.optJSONObject("user")
                    ?: throw IllegalStateException("The server returned no account.")
                val userId = remoteAccount.optString("userId")
                val canonicalUsername = remoteAccount.optString("username", cleanUsername)
                if (userId.isBlank()) throw IllegalStateException("The account ID is missing.")

                val newProfile = AccountProfileEntity(
                    userId = userId,
                    username = canonicalUsername,
                    password = hashedPassword,
                    publicKey = keyPair.publicKeyBase64,
                    privateKey = SecureVault.encrypt(keyPair.privateKeyBase64)
                )
                val backupPayload = "${newProfile.userId}|${newProfile.username}|${newProfile.password}|${newProfile.publicKey}|${newProfile.privateKeyPlain}"
                val encryptedBackup = withContext(Dispatchers.IO) { CryptoManager.encryptProfile(password, canonicalUsername, backupPayload) }

                profileDao.insertProfile(newProfile)
                userPrefs.setActiveProfile(newProfile)
                val uploaded = firebaseRepo.registerUser(userId, canonicalUsername, keyPair.publicKeyBase64, encryptedBackup)
                if (!uploaded) {
                    Log.w("AuthViewModel", "Account created, but profile backup did not sync. Keep this device and its keys.")
                }

                _authState.value = AuthState.Authenticated
                onComplete(true, userId)
            } catch (e: Exception) {
                val message = e.message?.takeIf { it.isNotBlank() } ?: "Registration failed"
                _authState.value = AuthState.Error(message)
                onComplete(false, null)
            }
        }
    }

    fun changeAccountPassword(currentPassword: String, newPassword: String, onComplete: (Boolean, String?) -> Unit) {
        if (currentPassword.isBlank() || newPassword.length !in 10..128) {
            onComplete(false, "Enter your current password and a new password of at least 10 characters.")
            return
        }
        viewModelScope.launch {
            try {
                val userId = userPrefs.userIdFlow.first().orEmpty()
                val username = userPrefs.usernameFlow.first().orEmpty()
                if (userId.isBlank() || username.isBlank()) throw IllegalStateException("No signed-in account.")
                val oldProfile = profileDao.getProfileByUsername(username)
                    ?: throw IllegalStateException("Local encryption keys are missing.")
                val privateKeyPlain = oldProfile.privateKeyPlain
                if (privateKeyPlain.isBlank() || oldProfile.publicKey.isBlank()) {
                    throw IllegalStateException("Your local encryption keys are unavailable. Password was not changed; recover the profile first.")
                }

                // Build the new backup before the request; the backend atomically updates
                // the scrypt credential and this password-protected backup in one DB update.
                val newPasswordHash = withContext(Dispatchers.IO) { CryptoManager.hashPassword(newPassword) }
                val updated = AccountProfileEntity(
                    userId = oldProfile.userId,
                    username = oldProfile.username,
                    password = newPasswordHash,
                    publicKey = oldProfile.publicKey,
                    privateKey = SecureVault.encrypt(privateKeyPlain)
                )
                val backupPayload = "${updated.userId}|${updated.username}|${updated.password}|${updated.publicKey}|${privateKeyPlain}"
                val encryptedBackup = withContext(Dispatchers.IO) {
                    CryptoManager.encryptProfile(newPassword, updated.username, backupPayload)
                }
                firebaseRepo.changeAccountPassword(
                    userId = userId,
                    currentPassword = currentPassword,
                    newPassword = newPassword,
                    publicKey = updated.publicKey,
                    encryptedBackup = encryptedBackup
                )

                // Password change revokes existing sessions. Establish a fresh session with
                // the new password before declaring the operation complete.
                firebaseRepo.loginAccount(username, newPassword)
                profileDao.insertProfile(updated)
                userPrefs.setActiveProfile(updated)
                onComplete(true, null)
            } catch (e: Exception) {
                onComplete(false, e.message?.takeIf { it.isNotBlank() } ?: "Password change failed")
            }
        }
    }

    fun deleteAccount(userId: String, password: String, onComplete: (Boolean, String?) -> Unit) {
        if (password.isBlank()) {
            onComplete(false, "Enter your password to confirm account deletion.")
            return
        }
        viewModelScope.launch {
            try {
                firebaseRepo.deleteRemoteAccount(userId, password)
                profileDao.deleteProfileById(userId)
                val remaining = profileDao.getAllProfiles()
                if (remaining.isNotEmpty()) {
                    userPrefs.setActiveProfile(remaining.first())
                    _authState.value = AuthState.Authenticated
                } else {
                    userPrefs.clearSession()
                    _authState.value = AuthState.NeedsRegistration
                }
                onComplete(true, null)
            } catch (e: Exception) {
                onComplete(false, e.message?.takeIf { it.isNotBlank() } ?: "Account deletion failed")
            }
        }
    }

    fun deleteProfile(userId: String) {
        viewModelScope.launch {
            profileDao.deleteProfileById(userId)
            val remaining = profileDao.getAllProfiles()
            if (remaining.isNotEmpty()) {
                userPrefs.setActiveProfile(remaining.first())
            } else {
                userPrefs.clearSession()
                _authState.value = AuthState.NeedsRegistration
            }
        }
    }
}
