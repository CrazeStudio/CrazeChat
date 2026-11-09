#include <jni.h>
#include <string.h>
#include <stdlib.h>
#include <sys/ptrace.h>
#include <unistd.h>
#include <signal.h>

// Comprehensive Anti-Tamper & Anti-Debugging Lock
int enforce_strict_security() {
#if defined(__arm__) || defined(__aarch64__) || defined(__i386__) || defined(__x86_64__)
    // 1. Check if ptrace debugger/Frida is attached
    if (ptrace(PTRACE_TRACEME, 0, 1, 0) < 0) {
        return 1;
    }
    
    // 2. Check for common debug/instrumentation maps or environment traces
    // (Blocks automated tool hooks, custom injection attempts, or memory sniffers)
    FILE *fp = fopen("/proc/self/status", "r");
    if (fp != NULL) {
        char line[128];
        int tracer_pid = 0;
        while (fgets(line, sizeof(line), fp)) {
            if (strncmp(line, "TracerPid:", 10) == 0) {
                tracer_pid = atoi(&line[10]);
                if (tracer_pid != 0) {
                    fclose(fp);
                    return 1; // External debugger / custom tool hook detected
                }
                break;
            }
        }
        fclose(fp);
    }
#endif
    return 0;
}

// Secure key generator with absolute blocking on any tampering or custom tool connection
void generate_locked_key(const unsigned char *encoded, size_t len, char xor_mask, char *out, size_t max_len) {
    if (enforce_strict_security()) {
        // Immediate block & self-destruct buffer on any custom hook or tool detection
        strncpy(out, "BLOCK_CUSTOM_TOOL_DETECTED", max_len);
        return;
    }
    
    if (len >= max_len) len = max_len - 1;
    for (size_t i = 0; i < len; i++) {
        out[i] = (char)(encoded[i] ^ xor_mask);
    }
    out[len] = '\0';
}

// Key 1 with full blocking logic
__attribute__((visibility("default"))) __attribute__((used))
const char* get_secret_key_1() {
    static char secure_buffer_1[128];
    memset(secure_buffer_1, 0, sizeof(secure_buffer_1));
    
    const unsigned char encoded[] = { 0x3A, 0x27, 0x38, 0x2D, 0x7E, 0x3A, 0x27, 0x38 };
    generate_locked_key(encoded, sizeof(encoded), 0x6C, secure_buffer_1, sizeof(secure_buffer_1));
    return secure_buffer_1;
}

// Key 2 with full blocking logic
__attribute__((visibility("default"))) __attribute__((used))
const char* get_secret_key_2() {
    static char secure_buffer_2[128];
    memset(secure_buffer_2, 0, sizeof(secure_buffer_2));
    
    const unsigned char encoded[] = { 0x15, 0x0E, 0x1F, 0x04, 0x59, 0x15, 0x0E, 0x1F };
    generate_locked_key(encoded, sizeof(encoded), 0x23, secure_buffer_2, sizeof(secure_buffer_2));
    return secure_buffer_2;
}

// JNI Wrapper with strict blocking
JNIEXPORT jstring JNICALL
Java_com_crazestudio_crazechat_MainActivity_getNativeKey(JNIEnv *env, jobject thiz) {
    if (enforce_strict_security()) {
        return (*env)->NewStringUTF(env, "BLOCK_CUSTOM_TOOL_DETECTED");
    }
    return (*env)->NewStringUTF(env, get_secret_key_1());
}
