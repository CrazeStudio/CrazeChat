package com.example.viewmodel

import android.app.Application
import android.graphics.Bitmap
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.data.CryptoManager
import com.example.data.FirebaseRepository
import com.example.data.ProfileImageManager
import com.example.data.UserPreferences
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

class ProfileViewModel(application: Application) : AndroidViewModel(application) {
    private val userPrefs = UserPreferences(application)
    private val pfpManager = ProfileImageManager.getInstance(application)
    private val firebaseRepo = FirebaseRepository()

    val userId: StateFlow<String> = userPrefs.userIdFlow
        .map { it ?: "" }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "")

    val username: StateFlow<String> = userPrefs.usernameFlow
        .map { it ?: "" }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "")

    val publicKey: StateFlow<String> = userPrefs.publicKeyFlow
        .map { it ?: "" }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "")

    val fingerprint: StateFlow<String> = publicKey.map { pub ->
        if (pub.isNotBlank()) CryptoManager.computePublicKeyFingerprint(pub) else ""
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "")

    private val _pfpBitmap = MutableStateFlow<Bitmap?>(null)
    val pfpBitmap: StateFlow<Bitmap?> = _pfpBitmap.asStateFlow()

    private val _isPfpLoading = MutableStateFlow(false)
    val isPfpLoading: StateFlow<Boolean> = _isPfpLoading.asStateFlow()

    private val _pfpError = MutableStateFlow<String?>(null)
    val pfpError: StateFlow<String?> = _pfpError.asStateFlow()

    init {
        viewModelScope.launch {
            userId.collect { id ->
                if (id.isNotBlank()) {
                    loadPfp(id)
                }
            }
        }

        viewModelScope.launch {
            pfpManager.pfpVersion.collect {
                val id = userId.value
                if (id.isNotBlank()) {
                    loadPfp(id)
                }
            }
        }
    }

    private fun loadPfp(id: String) {
        viewModelScope.launch {
            val bitmap = pfpManager.getPfpBitmap(id)
            _pfpBitmap.value = bitmap
        }
    }

    fun setPfpFromUrl(imageUrl: String, onComplete: (Boolean, String?) -> Unit) {
        val id = userId.value
        if (id.isBlank()) {
            onComplete(false, "No active user ID found.")
            return
        }

        val validation = pfpManager.validateImageUrl(imageUrl)
        if (!validation.first) {
            val err = validation.second ?: "Invalid image URL"
            _pfpError.value = err
            onComplete(false, err)
            return
        }

        viewModelScope.launch {
            _isPfpLoading.value = true
            _pfpError.value = null
            val result = pfpManager.downloadAndSavePfp(id, imageUrl)
            _isPfpLoading.value = false
            result.onSuccess { bitmap ->
                _pfpBitmap.value = bitmap
                // Encrypt and sync PFP URL to Firebase so other users can see it
                val encryptedUrl = CryptoManager.encryptPfpUrl(imageUrl)
                firebaseRepo.updatePfpUrl(id, encryptedUrl)
                onComplete(true, null)
            }.onFailure { err ->
                val msg = err.localizedMessage ?: "Failed to download and encrypt image"
                _pfpError.value = msg
                onComplete(false, msg)
            }
        }
    }

    fun removePfp(onComplete: (Boolean) -> Unit) {
        val id = userId.value
        if (id.isBlank()) {
            onComplete(false)
            return
        }

        viewModelScope.launch {
            _isPfpLoading.value = true
            pfpManager.removePfp(id)
            _pfpBitmap.value = null
            // Remove PFP URL from Firebase cloud
            firebaseRepo.updatePfpUrl(id, "")
            _isPfpLoading.value = false
            onComplete(true)
        }
    }
}
