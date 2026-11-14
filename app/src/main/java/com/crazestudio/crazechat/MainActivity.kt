package com.crazestudio.crazechat

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModelProvider

class MainActivity : ComponentActivity() {
    private var folderCallback: ((String?) -> Unit)? = null
    private lateinit var chatModel: MainViewModel

    private val folderPicker = registerForActivityResult(
        ActivityResultContracts.OpenDocumentTree()
    ) { uri ->
        val callback = folderCallback
        folderCallback = null
        if (uri == null) {
            callback?.invoke(null)
        } else {
            try {
                val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                contentResolver.takePersistableUriPermission(uri, flags)
                callback?.invoke(uri.toString())
            } catch (error: Exception) {
                callback?.invoke(null)
            }
        }
    }

    private val notificationPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* Permission result is reflected by the Android OS setting. */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        createNotificationChannels()
        chatModel = ViewModelProvider(this)[MainViewModel::class.java]
        setContent { CrazeChatRoot(chatModel) }
        window.decorView.post {
            consumeLaunchChatId()?.let(chatModel::openChatById)
        }
    }

    override fun onResume() {
        super.onResume()
        if (::chatModel.isInitialized) chatModel.onAppResumed()
    }

    fun chooseSyncFolder(onResult: (String?) -> Unit) {
        if (folderCallback != null) return
        folderCallback = onResult
        folderPicker.launch(null)
    }

    fun setScreenSecure(enabled: Boolean) {
        runOnUiThread {
            if (enabled) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    fun consumeLaunchChatId(): String? {
        val id = intent?.getStringExtra("chat_id")
        intent?.removeExtra("chat_id")
        return id
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.getStringExtra("chat_id")?.let { chatId ->
            PushEventBus.openChat(chatId)
            intent.removeExtra("chat_id")
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannelGroup(NotificationChannelGroup("crazechat_messages_group", "Messages"))
        createMessageChannel(manager, "crazechat_messages_default", true, true)
        createMessageChannel(manager, "crazechat_messages_sound_only", true, false)
        createMessageChannel(manager, "crazechat_messages_vibrate_only", false, true)
        createMessageChannel(manager, "crazechat_messages_silent", false, false)
    }

    private fun createMessageChannel(
        manager: NotificationManager,
        id: String,
        soundEnabled: Boolean,
        vibrationEnabled: Boolean
    ) {
        val channel = NotificationChannel(id, "CrazeChat messages", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Generic alerts for new encrypted CrazeChat messages"
            group = "crazechat_messages_group"
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            enableVibration(vibrationEnabled)
            if (soundEnabled) {
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                    AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build()
                )
            } else {
                setSound(null, null)
            }
            if (vibrationEnabled) vibrationPattern = longArrayOf(0, 180, 100, 180)
        }
        manager.createNotificationChannel(channel)
    }
}
