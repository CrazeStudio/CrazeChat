package com.example.viewmodel

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.data.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
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
    private val firebaseRepo = FirebaseRepository()

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

    init {
        checkSession()
    }

    fun checkSession() {
        viewModelScope.launch {
            userPrefs.userIdFlow.collect { userId ->
                if (userId.isNullOrEmpty()) {
                    _authState.value = AuthState.NeedsRegistration
                } else {
                    _authState.value = AuthState.Authenticated
                }
            }
        }
    }

    fun logout() {
        viewModelScope.launch {
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
                var profile = profileDao.getProfileByUsername(cleanUsername)

                // If not in local storage (e.g. storage cleared or new device), recover from cloud
                if (profile == null) {
                    val firebaseUser = firebaseRepo.findUserByUsername(cleanUsername)
                    if (firebaseUser != null) {
                        val encryptedBackup = firebaseUser.encryptedBackup

                        if (encryptedBackup.isNotBlank()) {
                            val decryptedProfile = CryptoManager.decryptProfile(password, cleanUsername, encryptedBackup)
                            if (decryptedProfile != null) {
                                val parts = decryptedProfile.split("|")
                                if (parts.size >= 5) {
                                    val recoveredProfile = AccountProfileEntity(
                                        userId = parts[0],
                                        username = parts[1],
                                        password = parts[2],
                                        publicKey = parts[3],
                                        privateKey = parts[4]
                                    )
                                    profileDao.insertProfile(recoveredProfile)
                                    userPrefs.setActiveProfile(recoveredProfile)
                                    _authState.value = AuthState.Authenticated
                                    onComplete(true)
                                    return@launch
                                }
                            } else {
                                _authState.value = AuthState.Error("Incorrect password for account '$cleanUsername'")
                                onComplete(false)
                                return@launch
                            }
                        } else {
                            _authState.value = AuthState.Error("Account found online, but no cloud backup exists.")
                            onComplete(false)
                            return@launch
                        }
                    } else {
                        _authState.value = AuthState.Error("Account '$cleanUsername' not found.")
                        onComplete(false)
                        return@launch
                    }
                }

                if (profile != null) {
                    val hashedPassword = CryptoManager.hashPassword(password)
                    if (profile.password == hashedPassword || profile.password == password) {
                        userPrefs.setActiveProfile(profile)
                        _authState.value = AuthState.Authenticated
                        onComplete(true)
                    } else {
                        _authState.value = AuthState.Error("Incorrect password")
                        onComplete(false)
                    }
                } else {
                    _authState.value = AuthState.Error("Account not found")
                    onComplete(false)
                }
            } catch (e: Exception) {
                _authState.value = AuthState.Error(e.localizedMessage ?: "Login failed")
                onComplete(false)
            }
        }
    }

    fun registerUser(username: String, password: String, onComplete: (Boolean, String?) -> Unit) {
        if (username.isBlank() || password.isBlank()) {
            _authState.value = AuthState.Error("Username and password cannot be empty")
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

                val cleanUsername = username.trim()
                val existingLocal = profileDao.getProfileByUsername(cleanUsername)
                if (existingLocal != null) {
                    _authState.value = AuthState.Error("Username already exists on this device. Please log in.")
                    onComplete(false, null)
                    return@launch
                }

                _authState.value = AuthState.Loading
                val userId = UUID.randomUUID().toString()
                val keyPair = CryptoManager.generateKeyPair()

                val hashedPassword = CryptoManager.hashPassword(password)
                val newProfile = AccountProfileEntity(
                    userId = userId,
                    username = cleanUsername,
                    password = hashedPassword,
                    publicKey = keyPair.publicKeyBase64,
                    privateKey = keyPair.privateKeyBase64
                )

                // Create encrypted cloud backup payload protected with user's password
                val profileJson = "${newProfile.userId}|${newProfile.username}|${newProfile.password}|${newProfile.publicKey}|${newProfile.privateKey}"
                val encryptedBackup = CryptoManager.encryptProfile(password, cleanUsername, profileJson)

                val existing = firebaseRepo.findUserByUsername(cleanUsername)
                if (existing != null) {
                    _authState.value = AuthState.Error("Username already taken online.")
                    onComplete(false, null)
                    return@launch
                }

                val registeredOnline = firebaseRepo.registerUser(userId, cleanUsername, keyPair.publicKeyBase64, encryptedBackup)
                if (!registeredOnline) {
                    Log.w("AuthViewModel", "Online registration timed out or encountered network issue, continuing with local setup")
                }

                profileDao.insertProfile(newProfile)
                userPrefs.setActiveProfile(newProfile)

                _authState.value = AuthState.Authenticated
                onComplete(true, userId)
            } catch (e: Exception) {
                _authState.value = AuthState.Error(e.localizedMessage ?: "Registration failed")
                onComplete(false, null)
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
