/**
 * JNI bridge to libdsp_engine.so — MUST match include/dsp_engine.h ABI.
 */

#include <jni.h>
#include <android/log.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>

#define LOG_TAG "DspEngineJni"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

static constexpr size_t kAlign = 64;
static constexpr int kMaxFrames = 4096;
static constexpr int kMaxCh = 2;
static constexpr size_t kScratchFloats = (size_t)kMaxFrames * kMaxCh;
static constexpr int kMaxEqBands = 31;

/**
 * Soft true-peak-ish ceiling into ±1.0.
 * Linear below ~0.85; smooth knee above so boosted bass does not hard-clip.
 * Always on — does not reduce average loudness for clean signals.
 */
static inline float soft_clip(float x) {
    const float ax = fabsf(x);
    if (ax <= 0.85f) return x;
    const float s = (x >= 0.0f) ? 1.0f : -1.0f;
    const float over = ax - 0.85f;
    const float y = 0.85f + over / (1.0f + over * 2.5f);
    return s * (y > 0.999f ? 0.999f : y);
}

struct DspConfigJni {
    int32_t sample_rate;
    int32_t channels;
    int32_t buffer_frames;
    bool    exclusive_mode;
    bool    bit_perfect;
    int32_t realtime_priority;
};

typedef void* (*dsp_create_fn)(const DspConfigJni* config);
typedef void  (*dsp_destroy_fn)(void* handle);
typedef int   (*dsp_start_fn)(void* handle);
typedef int   (*dsp_stop_fn)(void* handle);
typedef void  (*dsp_process_fn)(void* handle, const float* in, float* out, int32_t frames);
typedef void  (*dsp_set_volume_fn)(void* handle, double linear_gain);
typedef void  (*dsp_eq_set_enabled_fn)(void* handle, bool enabled);
typedef void  (*dsp_eq_set_bands_fn)(void* handle, const double* centers_hz, const double* gains_db, int32_t count);
typedef void  (*dsp_eq_set_band_fn)(void* handle, int32_t index, double freq_hz, double gain_db, double q);

static void* g_lib = nullptr;
static dsp_create_fn         g_create = nullptr;
static dsp_destroy_fn        g_destroy = nullptr;
static dsp_start_fn          g_start = nullptr;
static dsp_stop_fn           g_stop = nullptr;
static dsp_process_fn        g_process = nullptr;
static dsp_set_volume_fn     g_set_volume = nullptr;
static dsp_eq_set_enabled_fn g_eq_set_enabled = nullptr;
static dsp_eq_set_bands_fn   g_eq_set_bands = nullptr;
static dsp_eq_set_band_fn    g_eq_set_band = nullptr;

static float* g_scratch_in  = nullptr;
static float* g_scratch_out = nullptr;

static bool ensure_lib() {
    if (g_lib) return g_create != nullptr && g_process != nullptr;

    g_lib = dlopen("libdsp_engine.so", RTLD_NOW);
    if (!g_lib) {
        LOGE("dlopen libdsp_engine.so failed: %s", dlerror());
        return false;
    }

    g_create         = (dsp_create_fn)dlsym(g_lib, "dsp_create");
    g_destroy        = (dsp_destroy_fn)dlsym(g_lib, "dsp_destroy");
    g_start          = (dsp_start_fn)dlsym(g_lib, "dsp_start");
    g_stop           = (dsp_stop_fn)dlsym(g_lib, "dsp_stop");
    g_process        = (dsp_process_fn)dlsym(g_lib, "dsp_process");
    g_set_volume     = (dsp_set_volume_fn)dlsym(g_lib, "dsp_set_volume");
    g_eq_set_enabled = (dsp_eq_set_enabled_fn)dlsym(g_lib, "dsp_eq_set_enabled");
    g_eq_set_bands   = (dsp_eq_set_bands_fn)dlsym(g_lib, "dsp_eq_set_bands");
    g_eq_set_band    = (dsp_eq_set_band_fn)dlsym(g_lib, "dsp_eq_set_band");

    if (!g_create || !g_process) {
        LOGE("dlsym missing dsp_create and/or dsp_process");
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

    LOGI("libdsp_engine.so loaded create=%p process=%p vol=%p eq_bands=%p",
         (void*)g_create, (void*)g_process, (void*)g_set_volume, (void*)g_eq_set_bands);
    return true;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeCreate(
        JNIEnv*, jclass, jdouble sampleRate, jint channels) {
    if (!ensure_lib() || !g_create) return 0;

    int sr = (int)lround(sampleRate);
    if (sr < 8000) sr = 44100;
    if (channels < 1) channels = 1;
    if (channels > kMaxCh) channels = kMaxCh;

    DspConfigJni cfg;
    cfg.sample_rate = sr;
    cfg.channels = channels;
    cfg.buffer_frames = kMaxFrames;
    cfg.exclusive_mode = false;
    cfg.bit_perfect = true;
    cfg.realtime_priority = 0;

    void* h = g_create(&cfg);
    if (!h) {
        LOGE("dsp_create returned null (sr=%d ch=%d)", sr, channels);
        return 0;
    }
    if (g_start) g_start(h);
    if (g_set_volume) g_set_volume(h, 1.0);
    LOGI("dsp_create ok handle=%p sr=%d ch=%d", h, sr, channels);
    return reinterpret_cast<jlong>(h);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeDestroy(JNIEnv*, jclass, jlong handle) {
    if (!handle) return;
    void* h = reinterpret_cast<void*>(handle);
    if (g_stop) g_stop(h);
    if (g_destroy) g_destroy(h);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeSetEnabled(
        JNIEnv*, jclass, jlong handle, jboolean enabled) {
    if (!handle) return;
    if (g_eq_set_enabled) {
        g_eq_set_enabled(reinterpret_cast<void*>(handle), enabled == JNI_TRUE);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeSetVolume(
        JNIEnv*, jclass, jlong handle, jdouble linearGain) {
    if (!handle || !g_set_volume) return;
    if (linearGain < 0.0) linearGain = 0.0;
    if (linearGain > 4.0) linearGain = 4.0;
    g_set_volume(reinterpret_cast<void*>(handle), linearGain);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeSetEqBands(
        JNIEnv* env, jclass, jlong handle,
        jdoubleArray centersHz, jdoubleArray gainsDb, jboolean enabled) {
    if (!handle) return;
    if (g_eq_set_enabled) {
        g_eq_set_enabled(reinterpret_cast<void*>(handle), enabled == JNI_TRUE);
    }
    if (!gainsDb) return;

    jsize nG = env->GetArrayLength(gainsDb);
    if (nG <= 0) return;
    if (nG > kMaxEqBands) nG = kMaxEqBands;

    double gains[kMaxEqBands];
    double centers[kMaxEqBands];
    jdouble* gPtr = env->GetDoubleArrayElements(gainsDb, nullptr);
    if (!gPtr) return;
    for (jsize i = 0; i < nG; ++i) gains[i] = gPtr[i];
    env->ReleaseDoubleArrayElements(gainsDb, gPtr, JNI_ABORT);

    const double* centersPtr = nullptr;
    if (centersHz != nullptr) {
        jsize nC = env->GetArrayLength(centersHz);
        jsize n = nC < nG ? nC : nG;
        jdouble* cPtr = env->GetDoubleArrayElements(centersHz, nullptr);
        if (cPtr) {
            for (jsize i = 0; i < n; ++i) centers[i] = cPtr[i];
            env->ReleaseDoubleArrayElements(centersHz, cPtr, JNI_ABORT);
            centersPtr = centers;
        }
    }

    if (g_eq_set_bands) {
        g_eq_set_bands(reinterpret_cast<void*>(handle), centersPtr, gains, (int32_t)nG);
    } else if (g_eq_set_band) {
        for (jsize i = 0; i < nG; ++i) {
            double hz = centersPtr ? centers[i] : 0.0;
            g_eq_set_band(reinterpret_cast<void*>(handle), (int32_t)i, hz, gains[i], 0.0);
        }
    }
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeProcessPcm16Direct(
        JNIEnv* env, jclass, jlong handle, jobject buffer, jint frames,
        jint channels, jdouble /*sampleRate*/) {
    if (!handle || !g_process || frames <= 0 || frames > kMaxFrames ||
        channels <= 0 || channels > kMaxCh) {
        return -1;
    }
    if (!g_scratch_in || !g_scratch_out) {
        if (!ensure_lib()) return -2;
    }

    void* addr = env->GetDirectBufferAddress(buffer);
    if (!addr) return -3;

    int16_t* pcm = static_cast<int16_t*>(addr);
    const int n = frames * channels;

    for (int i = 0; i < n; ++i) {
        g_scratch_in[i] = (float)pcm[i] * (1.0f / 32768.0f);
    }

    g_process(reinterpret_cast<void*>(handle), g_scratch_in, g_scratch_out, frames);

    for (int i = 0; i < n; ++i) {
        float s = soft_clip(g_scratch_out[i]);
        if (s > 1.0f) s = 1.0f;
        if (s < -1.0f) s = -1.0f;
        pcm[i] = (int16_t)(s * 32767.0f);
    }
    return 0;
}
