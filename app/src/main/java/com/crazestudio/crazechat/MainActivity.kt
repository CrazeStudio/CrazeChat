package com.crazestudio.crazechat

import android.app.Activity
import android.os.Bundle
import android.widget.TextView
import com.crazestudio.crazechat.security.NativeBridge

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val status = runCatching { NativeBridge.nativeStatus() }
            .getOrElse { "Native security library failed to load: ${it.javaClass.simpleName}" }
        val view = TextView(this).apply {
            text = "CrazeChat\n\nGradle + Kotlin + native C++ core\n\n$status\n\nSecurity foundation initialized."
            textSize = 18f
            setPadding(32, 48, 32, 32)
        }
        setContentView(view)
    }
}
