package com.crazestudio.crazechat

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/** Events contain only opaque chat IDs, never message plaintext. */
object PushEventBus {
    private val incomingMutable = MutableSharedFlow<String>(extraBufferCapacity = 32)
    private val openChatMutable = MutableSharedFlow<String>(extraBufferCapacity = 8)
    val incoming = incomingMutable.asSharedFlow()
    val openChatRequests = openChatMutable.asSharedFlow()

    fun messageArrived(chatId: String) {
        if (Regex("^[a-f0-9]{32}$").matches(chatId)) incomingMutable.tryEmit(chatId)
    }

    fun openChat(chatId: String) {
        if (Regex("^[a-f0-9]{32}$").matches(chatId)) openChatMutable.tryEmit(chatId)
    }
}
