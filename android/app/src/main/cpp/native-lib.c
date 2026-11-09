#include <string.h>
#include <stdlib.h>
#include <jni.h>

#ifdef __cplusplus
extern "C" {
#endif

// Generic XOR decryption utility
void xor_decrypt(const unsigned char *src, size_t len, char xor_key, char *dest) {
    for (size_t i = 0; i < len; i++) {
        dest[i] = (char)(src[i] ^ xor_key);
    }
    dest[len] = '\0';
}

// Exported function for Secret Key 1 (e.g., API Key)
__attribute__((visibility("default"))) __attribute__((used))
const char* get_secret_key_1() {
    static char decrypted_cache[64];
    // Obfuscated bytes for Key 1
    const unsigned char obfuscated[] = {0x13, 0x18, 0x07, 0x08, 0x60, 0x13, 0x18, 0x07, 0x08};
    char xor_key = 0x5A;
    
    size_t len = sizeof(obfuscated) / sizeof(obfuscated[0]);
    if (len >= sizeof(decrypted_cache)) return "";

    xor_decrypt(obfuscated, len, xor_key, decrypted_cache);
    return decrypted_cache;
}

// Exported function for Secret Key 2 (e.g., Firebase / Encryption Salt / Auth Token)
__attribute__((visibility("default"))) __attribute__((used))
const char* get_secret_key_2() {
    static char decrypted_cache_2[64];
    // Obfuscated bytes for Key 2 (using a distinct or same XOR key)
    const unsigned char obfuscated[] = {0x35, 0x32, 0x25, 0x26, 0x42, 0x35, 0x32, 0x25, 0x26};
    char xor_key = 0x3C;
    
    size_t len = sizeof(obfuscated) / sizeof(obfuscated[0]);
    if (len >= sizeof(decrypted_cache_2)) return "";

    xor_decrypt(obfuscated, len, xor_key, decrypted_cache_2);
    return decrypted_cache_2;
}

#ifdef __cplusplus
}
#endif
