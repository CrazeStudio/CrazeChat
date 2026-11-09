#include <string.h>
#include <stdlib.h>
#include <jni.h>

#ifdef __cplusplus
extern "C" {
#endif

// Simple XOR decryption function
void xor_cipher(char *data, size_t len, char key) {
    for (size_t i = 0; i < len; i++) {
        data[i] ^= key;
    }
}

// Clean C exported function for direct Dart FFI usage
__attribute__((visibility("default"))) __attribute__((used))
const char* get_secret_key() {
    // Example XOR obfuscated key bytes (derived with XOR key 0x5A)
    // Replace these bytes with your actual XOR-encoded secret key bytes
    static char decrypted_cache[64];
    char obfuscated_key[] = {0x13, 0x18, 0x07, 0x08, 0x60, 0x13, 0x18, 0x07, 0x08}; 
    char xor_key = 0x5A;

    size_t len = sizeof(obfuscated_key) / sizeof(obfuscated_key[0]);
    if (len >= sizeof(decrypted_cache)) {
        return "";
    }

    memcpy(decrypted_cache, obfuscated_key, len);
    decrypted_cache[len] = '\0';

    xor_cipher(decrypted_cache, len, xor_key);

    return decrypted_cache;
}

// JNI wrapper method for Android Java/Kotlin layer compatibility if needed
JNIEXPORT jstring JNICALL
Java_com_crazestudio_crazechat_MainActivity_getNativeKey(JNIEnv *env, jobject thiz) {
    const char *key = get_secret_key();
    return (*env)->NewStringUTF(env, key);
}

#ifdef __cplusplus
}
#endif
