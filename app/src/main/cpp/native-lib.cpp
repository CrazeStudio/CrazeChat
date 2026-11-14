#include <jni.h>
#include <string>

#if __has_include("craze_config.h")
#include "craze_config.h"
#else
#define CC_MASK_LEN 1
#define CC_URL_LEN 0
static const unsigned char cc_mask[CC_MASK_LEN] = {0};
static const unsigned char cc_url_enc[1] = {0};
#endif

namespace {
std::string decode_config(const unsigned char* value, std::size_t length) {
    std::string decoded;
    decoded.reserve(length);
    for (std::size_t i = 0; i < length; ++i) {
        decoded.push_back(static_cast<char>(value[i] ^ cc_mask[i % CC_MASK_LEN]));
    }
    return decoded;
}
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_crazestudio_crazechat_security_NativeBridge_nativeStatus(JNIEnv* env, jobject) {
    return env->NewStringUTF("libcraze.so loaded");
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_crazestudio_crazechat_security_NativeBridge_nativeApiOrigin(JNIEnv* env, jobject) {
    const auto value = decode_config(cc_url_enc, CC_URL_LEN);
    return env->NewStringUTF(value.c_str());
}
