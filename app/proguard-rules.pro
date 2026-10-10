# Project specific ProGuard / R8 rules

# Enable optimization, shrinking, and obfuscation
-repackageclasses ''
-allowaccessmodification

# Preserve Line Number and Source File info for meaningful crash stacktraces
-keepattributes SourceFile,LineNumberTable,Signature,InnerClasses,EnclosingMethod,*Annotation*

# =========================================================================
# Kotlin and Coroutines
# =========================================================================
-keep class kotlin.Metadata { *; }
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}
-dontwarn kotlinx.coroutines.**
-dontwarn kotlin.**

# =========================================================================
# Application Data & DTO Models (CRITICAL for Reflection & Serialization)
# =========================================================================
# Keep all data models and entities in com.example.data to prevent
# obfuscation or shrinking from breaking Room database mapping or Firebase
# Realtime Database serialization.
-keep class com.example.data.** { *; }
-keep interface com.example.data.** { *; }

# Keep all ViewModels and their public constructors/methods
-keep class com.example.viewmodel.** { *; }

# =========================================================================
# Jetpack Room Database
# =========================================================================
-keep @androidx.room.Entity class * { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep @androidx.room.Dao interface * { *; }
-dontwarn androidx.room.**

# =========================================================================
# Firebase Realtime Database & Auth
# =========================================================================
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keepattributes *Annotation*,Signature

# =========================================================================
# Retrofit 2
# =========================================================================
-dontwarn retrofit2.**
-keep class retrofit2.** { *; }
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-keepclassmembers class * {
    @retrofit2.http.* <methods>;
}

# =========================================================================
# Moshi (JSON Serialization/Deserialization)
# =========================================================================
-dontwarn com.squareup.moshi.**
-keep class com.squareup.moshi.** { *; }
-keep @com.squareup.moshi.JsonClass class * { *; }
-keep class *JsonAdapter { *; }
-keepclassmembers class * {
    @com.squareup.moshi.Json *;
}

# =========================================================================
# OkHttp 3 & Okio
# =========================================================================
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase

# =========================================================================
# Coil (Image Loading)
# =========================================================================
-dontwarn coil.**
-keep class coil.** { *; }
