import java.security.MessageDigest
import java.security.SecureRandom

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.google.gms.google-services")
}

val generatedNativeConfig = file("src/main/cpp/generated/craze_config.h")
val apiOrigin = providers.environmentVariable("CRAZECHAT_BURL")
    .orElse("https://crazestudio-web.mehetabhoque566.workers.dev")
val gatewayKey = providers.environmentVariable("CRAZECHAT_KEY").orElse("")
val gatewayKeyFingerprint = gatewayKey.map { value ->
    MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
}

val generateCrazeNativeConfig = tasks.register("generateCrazeNativeConfig") {
    inputs.property("apiOrigin", apiOrigin)
    inputs.property("gatewayKeyFingerprint", gatewayKeyFingerprint)
    outputs.file(generatedNativeConfig)
    doLast {
        val origin = apiOrigin.get().trim()
        val key = gatewayKey.get().trim()
        require(origin.startsWith("https://") ||
            origin.startsWith("http://10.0.2.2") ||
            origin.startsWith("http://127.0.0.1") ||
            origin.startsWith("http://localhost")) {
            "CRAZECHAT_BURL must be an HTTPS origin (or an explicit local development origin)."
        }
        val mask = ByteArray(16).also { SecureRandom().nextBytes(it) }
        fun maskValue(value: String, offset: Int): ByteArray {
            val raw = value.toByteArray(Charsets.UTF_8)
            return ByteArray(raw.size + 1).also { result ->
                raw.forEachIndexed { index, byte ->
                    result[index] = (byte.toInt() xor (mask[(index + offset) % mask.size].toInt() and 0xff)).toByte()
                }
                result[raw.size] = 0
            }
        }
        fun bytes(value: ByteArray) = value.joinToString(", ") { (it.toInt() and 0xff).toString() }
        val urlBytes = maskValue(origin, 0)
        val keyBytes = maskValue(key, 7)
        generatedNativeConfig.parentFile.mkdirs()
        generatedNativeConfig.writeText(
            "/* Generated from build environment. Do not commit. */\n" +
                "#define CC_MASK_LEN 16\n" +
                "#define CC_URL_LEN ${urlBytes.size - 1}\n" +
                "#define CC_KEY_LEN ${keyBytes.size - 1}\n" +
                "static const unsigned char cc_mask[CC_MASK_LEN] = {${bytes(mask)}};\n" +
                "static const unsigned char cc_url_enc[CC_URL_LEN + 1] = {${bytes(urlBytes)}};\n" +
                "static const unsigned char cc_key_enc[CC_KEY_LEN + 1] = {${bytes(keyBytes)}};\n"
        )
        println("CrazeChat native configuration generated; sensitive values were not logged.")
    }
}

android {
    namespace = "com.crazestudio.crazechat"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.crazestudio.crazechat"
        minSdk = 24
        targetSdk = 35
        versionCode = 2
        versionName = "2.0.0"
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64") }
        externalNativeBuild {
            cmake { cppFlags += listOf("-std=c++20", "-fvisibility=hidden", "-fstack-protector-strong") }
        }
    }

    buildTypes {
        debug { isMinifyEnabled = false }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    externalNativeBuild {
        cmake { path = file("src/main/cpp/CMakeLists.txt"); version = "3.22.1" }
    }
    packaging { jniLibs { useLegacyPackaging = false } }
}

tasks.named("preBuild").configure { dependsOn(generateCrazeNativeConfig) }
tasks.configureEach {
    if (name.startsWith("configureCMake") || name.startsWith("buildCMake")) {
        dependsOn(generateCrazeNativeConfig)
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.activity:activity-compose:1.10.0")
    implementation("androidx.fragment:fragment-ktx:1.8.5")
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("androidx.lifecycle:lifecycle-process:2.8.7")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-process:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.bouncycastle:bcprov-jdk18on:1.86")
    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("com.google.firebase:firebase-installations")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
