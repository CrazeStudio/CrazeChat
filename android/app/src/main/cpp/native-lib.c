#include <jni.h>
#include <string.h>
#include <stdlib.h>

// Simple XOR decryption function for obfuscated keys in the binary
void xor_cipher(char *data, size_t len, char key) {
    for (size_t i = 0; i < len; i++) {
        data[i] ^= key;
    }
}

JNIEXPORT jstring JNICALL
Java_com_crazestudio_crazechat_MainActivity_getNativeKey(JNIEnv *env, jobject thiz) {
    // Example XOR obfuscated key bytes (derived by applying XOR with key 0x5A)
    // Replace these bytes with your actual XOR-encoded secret key bytes
    char obfuscated_key[] = {0x13, 0x18, 0x07, 0x08, 0x60, 0x13, 0x18, 0x07, 0x08}; 
    char xor_key = 0x5A;

    size_t len = sizeof(obfuscated_key) / sizeof(obfuscated_key[0]);
    
    // Allocate a temporary buffer to decrypt at runtime
    char *decrypted = (char *)malloc(len + 1);
    if (decrypted == NULL) {
        return (*env)->NewStringUTF(env, "");
    }
    memcpy(decrypted, obfuscated_key, len);
    decrypted[len] = '\0';

    // Decrypt the string in memory
    xor_cipher(decrypted, len, xor_key);

    jstring result = (*env)->NewStringUTF(env, decrypted);
    
    // Free the allocated memory
    free(decrypted);

    return result;
}
