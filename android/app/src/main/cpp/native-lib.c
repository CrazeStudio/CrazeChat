#include <jni.h>
#include <string.h>
#include <stdlib.h>
#include <sys/ptrace.h>
#include <unistd.h>

// 1. Anti-Debugging / Anti-Frida Check
int check_debugger_attached() {
#if defined(__arm__) || defined(__aarch64__) || defined(__i386__) || defined(__x86_64__)
    // ptrace TRACEME fails if a debugger or instrumentation tool (like Frida) is already attached
    if (ptrace(PTRACE_TRACEME, 0, 1, 0) < 0) {
        return 1; // Debugger detected
    }
#endif
    return 0;
}

// 2. Dynamic Algorithmic Derivation for Key 1 (No static plaintext or simple array)
void generate_key_1(char *out, size_t max_len) {
    if (check_debugger_attached()) {
        strncpy(out, "SECURITY_VIOLATION_DETECTED", max_len);
        return;
    }
    
    // Constructing characters dynamically through runtime math and bitwise transforms
    // Example seed bytes combined with XOR obfuscation layer
    unsigned char encoded[] = { 0x3A, 0x27, 0x38, 0x2D, 0x7E, 0x3A, 0x27, 0x38 };
    char xor_mask = 0x6C;
    
    size_t len = sizeof(encoded);
    if (len >= max_len) len = max_len - 1;

    for (size_t i = 0; i < len; i++) {
        out[i] = (char)(encoded[i] ^ xor_mask);
    }
    out[len] = '\0';
}

// 3. Dynamic Algorithmic Derivation for Key 2 (Isolated & protected)
void generate_key_2(char *out, size_t max_len) {
    if (check_debugger_attached()) {
        strncpy(out, "SECURITY_VIOLATION_DETECTED", max_len);
        return;
    }

    unsigned char encoded[] = { 0x15, 0x0E, 0x1F, 0x04, 0x59, 0x15, 0x0E, 0x1F };
    char xor_mask = 0x23;

    size_t len = sizeof(encoded);
    if (len >= max_len) len = max_len - 1;

    for (size_t i = 0; i < len; i++) {
        out[i] = (char)(encoded[i] ^ xor_mask);
    }
    out[len] = '\0';
}

// Clean C Export for Key 1
__attribute__((visibility("default"))) __attribute__((used))
const char* get_secret_key_1() {
    static char secure_buffer_1[128];
    memset(secure_buffer_1, 0, sizeof(secure_buffer_1));
    generate_key_1(secure_buffer_1, sizeof(secure_buffer_1));
    return secure_buffer_1;
}

// Clean C Export for Key 2
__attribute__((visibility("default"))) __attribute__((used))
const char* get_secret_key_2() {
    static char secure_buffer_2[128];
    memset(secure_buffer_2, 0, sizeof(secure_buffer_2));
    generate_key_2(secure_buffer_2, sizeof(secure_buffer_2));
    return secure_buffer_2;
}

// JNI Compatibility Wrappers
JNIEXPORT jstring JNICALL
Java_com_crazestudio_crazechat_MainActivity_getNativeKey(JNIEnv *env, jobject thiz) {
    return (*env)->NewStringUTF(env, get_secret_key_1());
}
