#include <jni.h>
#include <string.h>

JNIEXPORT jstring JNICALL
Java_com_crazestudio_crazechat_MainActivity_getNativeKey(JNIEnv *env, jobject thiz) {
    // Simple obfuscated or plain storage in native library
    const char *key = "YOUR_SUPER_SECRET_API_KEY";
    return (*env)->NewStringUTF(env, key);
}
