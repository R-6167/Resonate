#include <jni.h>
#include <android/log.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define LOG_TAG "DspEngineJni"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Locked buffer policy
static constexpr size_t kAlign = 64;
static constexpr int kMaxFrames = 4096;
static constexpr int kMaxCh = 2;
static constexpr size_t kScratchFloats = (size_t)kMaxFrames * kMaxCh;

typedef void* (*dsp_create_fn)(double sample_rate, int channels);
typedef void  (*dsp_destroy_fn)(void* handle);
typedef void  (*dsp_process_fn)(void* handle, const float* in, float* out, int frames, int channels);
typedef void  (*dsp_set_enabled_fn)(void* handle, int enabled);

static void* g_lib = nullptr;
static dsp_create_fn      g_create = nullptr;
static dsp_destroy_fn     g_destroy = nullptr;
static dsp_process_fn     g_process = nullptr;
static dsp_set_enabled_fn g_set_enabled = nullptr;

static float* g_scratch_in  = nullptr;
static float* g_scratch_out = nullptr;

static bool ensure_lib() {
    if (g_lib) return g_create && g_process;
    g_lib = dlopen("libdsp_engine.so", RTLD_NOW);
    if (!g_lib) {
        LOGE("dlopen libdsp_engine.so failed: %s", dlerror());
        return false;
    }
    g_create      = (dsp_create_fn)dlsym(g_lib, "dsp_create");
    g_destroy     = (dsp_destroy_fn)dlsym(g_lib, "dsp_destroy");
    g_process     = (dsp_process_fn)dlsym(g_lib, "dsp_process");
    g_set_enabled = (dsp_set_enabled_fn)dlsym(g_lib, "dsp_set_enabled");
    if (!g_create || !g_process) {
        LOGE("dlsym missing dsp_create/dsp_process");
        return false;
    }
    if (!g_scratch_in) {
        if (posix_memalign((void**)&g_scratch_in, kAlign, kScratchFloats * sizeof(float)) != 0) {
            g_scratch_in = nullptr;
            return false;
        }
        if (posix_memalign((void**)&g_scratch_out, kAlign, kScratchFloats * sizeof(float)) != 0) {
            free(g_scratch_in);
            g_scratch_in = nullptr;
            return false;
        }
    }
    return true;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeCreate(JNIEnv*, jclass, jdouble sampleRate, jint channels) {
    if (!ensure_lib() || !g_create) return 0;
    void* h = g_create(sampleRate, channels);
    return reinterpret_cast<jlong>(h);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeDestroy(JNIEnv*, jclass, jlong handle) {
    if (g_destroy && handle) g_destroy(reinterpret_cast<void*>(handle));
}

extern "C" JNIEXPORT void JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeSetEnabled(JNIEnv*, jclass, jlong handle, jboolean enabled) {
    if (g_set_enabled && handle) g_set_enabled(reinterpret_cast<void*>(handle), enabled ? 1 : 0);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeProcessPcm16Direct(
        JNIEnv* env, jclass, jlong handle, jobject buffer, jint frames, jint channels, jdouble /*sampleRate*/) {
    if (!handle || !g_process || frames <= 0 || frames > kMaxFrames || channels <= 0 || channels > kMaxCh) {
        return -1;
    }
    if (!ensure_lib() || !g_scratch_in || !g_scratch_out) return -2;

    void* addr = env->GetDirectBufferAddress(buffer);
    if (!addr) return -3;

    int16_t* pcm = static_cast<int16_t*>(addr);
    const int n = frames * channels;

    for (int i = 0; i < n; ++i) {
        g_scratch_in[i] = (float)pcm[i] * (1.0f / 32768.0f);
    }
    g_process(reinterpret_cast<void*>(handle), g_scratch_in, g_scratch_out, frames, channels);
    for (int i = 0; i < n; ++i) {
        float s = g_scratch_out[i];
        if (s > 1.0f) s = 1.0f;
        if (s < -1.0f) s = -1.0f;
        pcm[i] = (int16_t)(s * 32767.0f);
    }
    return 0;
}
