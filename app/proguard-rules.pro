# Keep JNI entry points referenced from native code.
-keep class com.crazestudio.crazechat.security.NativeBridge { *; }
# Preserve cryptographic provider and Android Keystore API usage.
-keep class android.security.keystore.** { *; }
