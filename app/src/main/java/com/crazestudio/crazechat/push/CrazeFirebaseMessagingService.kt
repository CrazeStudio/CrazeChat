package com.crazestudio.crazechat.push

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ProcessLifecycleOwner
import com.crazestudio.crazechat.MainActivity
import com.crazestudio.crazechat.PushEventBus
import com.crazestudio.crazechat.R
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/** Push payloads never carry plaintext message content. */
class CrazeFirebaseMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        if (data["type"] != "new_message") return
        val chatId = data["chatId"]?.takeIf { Regex("^[a-f0-9]{32}$").matches(it) } ?: return

        val foreground = ProcessLifecycleOwner.get().lifecycle.currentState
            .isAtLeast(Lifecycle.State.STARTED)
        if (foreground) {
            PushEventBus.messageArrived(chatId)
            return
        }

        val launch = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("chat_id", chatId)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            chatId.hashCode(),
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification: Notification = NotificationCompat.Builder(this, "crazechat_messages_default")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("CrazeChat")
            .setContentText("You have a new encrypted message.")
            .setStyle(NotificationCompat.BigTextStyle().bigText("You have a new encrypted message. Open CrazeChat to view it."))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .build()
        getSystemService(NotificationManager::class.java)
            .notify(data["messageId"]?.hashCode() ?: chatId.hashCode(), notification)
    }
}
