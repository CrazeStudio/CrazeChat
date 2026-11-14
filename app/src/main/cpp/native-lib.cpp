#include <jni.h>
#include <algorithm>
#include <cctype>
#include <string>

#if __has_include("craze_config.h")
#include "craze_config.h"
#else
#define CC_MASK_LEN 1
#define CC_URL_LEN 0
#define CC_KEY_LEN 0
static const unsigned char cc_mask[CC_MASK_LEN] = {0};
static const unsigned char cc_url_enc[1] = {0};
static const unsigned char cc_key_enc[1] = {0};
#endif

namespace {
std::string decode_config(const unsigned char* value, std::size_t length, std::size_t offset) {
    std::string decoded;
    decoded.reserve(length);
    for (std::size_t i = 0; i < length; ++i) {
        const auto mask = cc_mask[(i + offset) % CC_MASK_LEN];
        decoded.push_back(static_cast<char>(value[i] ^ mask));
    }
    return decoded;
}

bool safe_token(const std::string& value, std::size_t max_len) {
    if (value.empty() || value.size() > max_len) return false;
    return std::all_of(value.begin(), value.end(), [](unsigned char c) {
        return std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~';
    });
}

bool safe_path(const std::string& path) {
    if (path.empty() || path.size() > 2048 || path.front() != '/') return false;
    if (path.find("..") != std::string::npos) return false;
    return std::none_of(path.begin(), path.end(), [](unsigned char c) {
        return c < 0x21 || c == 0x7f || c == '\\' || c == '#' || c == '?';
    });
}

std::string from_jstring(JNIEnv* env, jstring value) {
    if (!value) return {};
    const char* chars = env->GetStringUTFChars(value, nullptr);
    if (!chars) return {};
    std::string result(chars);
    env->ReleaseStringUTFChars(value, chars);
    return result;
}
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_crazestudio_crazechat_security_NativeBridge_nativeStatus(JNIEnv* env, jobject) {
    return env->NewStringUTF("libcraze.so loaded");
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_crazestudio_crazechat_security_NativeBridge_nativeApiOrigin(JNIEnv* env, jobject) {
    const auto value = decode_config(cc_url_enc, CC_URL_LEN, 0);
    return env->NewStringUTF(value.c_str());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_crazestudio_crazechat_security_NativeBridge_nativeGatewayKey(JNIEnv* env, jobject) {
    const auto value = decode_config(cc_key_enc, CC_KEY_LEN, 7);
    return env->NewStringUTF(value.c_str());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_crazestudio_crazechat_security_NativeBridge_nativeBuildCanonicalRequest(
    JNIEnv* env, jobject, jstring method_value, jstring path_value,
    jstring timestamp_value, jstring nonce_value, jstring body_hash_value) {
    const auto method = from_jstring(env, method_value);
    const auto path = from_jstring(env, path_value);
    const auto timestamp = from_jstring(env, timestamp_value);
    const auto nonce = from_jstring(env, nonce_value);
    const auto body_hash = from_jstring(env, body_hash_value);

    if (!(method == "GET" || method == "POST" || method == "PUT" ||
          method == "PATCH" || method == "DELETE")) return nullptr;
    if (!safe_path(path) || !safe_token(timestamp, 16) ||
        !safe_token(nonce, 128) || body_hash.size() != 64) return nullptr;
    if (!std::all_of(body_hash.begin(), body_hash.end(), [](unsigned char c) {
        return std::isxdigit(c) != 0;
    })) return nullptr;

    const std::string canonical =
        method + "\n" + path + "\n" + timestamp + "\n" +
        nonce + "\n" + body_hash;
    return env->NewStringUTF(canonical.c_str());
}
