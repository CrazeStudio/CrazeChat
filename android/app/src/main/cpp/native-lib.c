#include <jni.h>
#include <string.h>
#include <stdlib.h>
#include <sys/ptrace.h>
#include <unistd.h>

// 1. Hardened Anti-Debugging & Anti-Instrumentation Check (Blocks Frida, GDB, LLDB)
int enforce_system_security() {
#if defined(__arm__) || defined(__aarch64__) || defined(__i386__) || defined(__x86_64__)
    // Attempt to trace self. If a debugger or DBI framework (like Frida) is attached, ptrace fails.
    if (ptrace(PTRACE_TRACEME, 0, 1, 0) < 0) {
        return 1; // Tampering or debugger detected
    }
#endif
    return 0;
}

// 2. Dynamic Runtime Key Generation with Blockage on Tampering
void generate_protected_key(const unsigned char *encoded, size_t len, char xor_mask, char *out, size_t max_len) {
    // If any custom hooking or debugging is detected, poison the output to block extraction
    if (enforce_system_security()) {
        const char *violation = "BLOCKED_BY_RASP_SECURITY";
        strncpy(out, violation, max_len);
        return;
    }

    if (len >= max_len) {
        len = max_len - 1;
    }

    for (size_t i = 0; i < len; i++) {
        out[i] = (char)(encoded[i] ^ xor_mask);
    }
    out[len] = '\0';
}

// Exported Function for Key 1
__attribute__((visibility("default"))) __attribute__((used))
const char* get_secret_key_1() {
    static char secure_buffer_1[128];
    memset(secure_buffer_1, 0, sizeof(secure_buffer_1));
    
    // Obfuscated bytes + XOR mask
    const unsigned char encoded[] = { 0x3A, 0x27, 0x38, 0x2D, 0x7E, 0x3A, 0x27, 0x38 };
    char xor_mask = 0x6C;

    generate_protected_key(encoded, sizeof(encoded), xor_mask, secure_buffer_1, sizeof(secure_buffer_1));
    return secure_buffer_1;
}

// Exported Function for Key 2
__attribute__((visibility("default"))) __attribute__((used))
const char* get_secret_key_2() {
    static char secure_buffer_2[128];
    memset(secure_buffer_2, 0, sizeof(secure_buffer_2));
    
    // Obfuscated bytes + XOR mask
    const unsigned char encoded[] = { 0x15, 0x0E, 0x1F, 0x04, 0x59, 0x15, 0x0E, 0x1F };
    char xor_mask = 0x23;

    generate_protected_key(encoded, sizeof(encoded), xor_mask, secure_buffer_2, sizeof(secure_buffer_2));
    return secure_buffer_2;
}

// JNI Bridge Wrapper
JNIEXPORT jstring JNICALL
Java_com_crazestudio_crazechat_MainActivity_getNativeKey(JNIEnv *env, jobject thiz) {
    return (*env)->NewStringUTF(env, get_secret_key_1());
}
