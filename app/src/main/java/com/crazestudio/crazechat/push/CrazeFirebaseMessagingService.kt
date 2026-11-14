package com.crazestudio.crazechat.push

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.crazestudio.crazechat.MainActivity
import com.crazestudio.crazechat.R
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Push payloads carry opaque IDs only. This service never displays decrypted
 * message bodies or stores notification text.
 */
class CrazeFirebaseMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        if (data["type"] != "new_message") return
        val manager = getSystemService(NotificationManager::class.java)
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("chat_id", data["chatId"])
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            data["chatId"]?.hashCode() ?: 0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification: Notification = NotificationCompat.Builder(this, "crazechat_messages_default")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("CrazeChat")
            .setContentText("You have a new encrypted message.")
            .setStyle(NotificationCompat.BigTextStyle().bigText("You have a new encrypted message. Open CrazeChat to view it."))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .build()
        manager.notify(data["messageId"]?.hashCode() ?: System.currentTimeMillis().toInt(), notification)
    }
}
