/**
 * JNI bridge — links vendored libdsp_engine (preferred).
 */
#include <jni.h>
#include <android/log.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>

#include "dsp_engine.h"

#define LOG_TAG "DspEngineJni"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static constexpr size_t kAlign = 64;
static constexpr int kMaxFrames = 4096;
static constexpr int kMaxCh = 2;
static constexpr size_t kScratchFloats = (size_t)kMaxFrames * kMaxCh;
static constexpr int kMaxEqBands = 31;

static inline float soft_clip(float x) {
    const float ax = fabsf(x);
    if (ax <= 0.90f) return x;
    const float s = (x >= 0.0f) ? 1.0f : -1.0f;
    const float over = ax - 0.90f;
    const float y = 0.90f + over / (1.0f + over * 4.0f);
    return s * (y > 0.995f ? 0.995f : y);
}

static float* g_scratch_in  = nullptr;
static float* g_scratch_out = nullptr;

static bool ensure_scratch() {
    if (g_scratch_in && g_scratch_out) return true;
    if (posix_memalign((void**)&g_scratch_in, kAlign, kScratchFloats * sizeof(float)) != 0) {
        g_scratch_in = nullptr;
        return false;
    }
    if (posix_memalign((void**)&g_scratch_out, kAlign, kScratchFloats * sizeof(float)) != 0) {
        free(g_scratch_in);
        g_scratch_in = nullptr;
        return false;
    }
    return true;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeCreate(
        JNIEnv*, jclass, jdouble sampleRate, jint channels) {
    if (!ensure_scratch()) return 0;

    int sr = (int)lround(sampleRate);
    if (sr < 8000) sr = 44100;
    if (channels < 1) channels = 1;
    if (channels > kMaxCh) channels = kMaxCh;

    DspConfig cfg{};
    cfg.sample_rate = sr;
    cfg.channels = channels;
    cfg.buffer_frames = kMaxFrames;
    cfg.exclusive_mode = false;
    cfg.bit_perfect = true;
    cfg.realtime_priority = 0;

    void* h = dsp_create(&cfg);
    if (!h) {
        LOGE("dsp_create returned null (sr=%d ch=%d)", sr, channels);
        return 0;
    }
    dsp_start(h);
    dsp_set_volume(h, 1.0);
    LOGI("dsp_create ok handle=%p sr=%d ch=%d (linked)", h, sr, channels);
    return reinterpret_cast<jlong>(h);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeDestroy(JNIEnv*, jclass, jlong handle) {
    if (!handle) return;
    void* h = reinterpret_cast<void*>(handle);
    dsp_stop(h);
    dsp_destroy(h);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeSetEnabled(
        JNIEnv*, jclass, jlong handle, jboolean enabled) {
    if (!handle) return;
    dsp_eq_set_enabled(reinterpret_cast<void*>(handle), enabled == JNI_TRUE);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeSetVolume(
        JNIEnv*, jclass, jlong handle, jdouble linearGain) {
    if (!handle) return;
    if (linearGain < 0.0) linearGain = 0.0;
    if (linearGain > 4.0) linearGain = 4.0;
    dsp_set_volume(reinterpret_cast<void*>(handle), linearGain);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeSetEqBands(
        JNIEnv* env, jclass, jlong handle,
        jdoubleArray centersHz, jdoubleArray gainsDb, jboolean enabled) {
    if (!handle) return;
    dsp_eq_set_enabled(reinterpret_cast<void*>(handle), enabled == JNI_TRUE);
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

    dsp_eq_set_bands(reinterpret_cast<void*>(handle), centersPtr, gains, (int32_t)nG);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeSetSpeakerMode(
        JNIEnv*, jclass, jlong handle, jboolean enabled) {
    if (!handle) return;
    dsp_set_speaker_mode(reinterpret_cast<void*>(handle), enabled == JNI_TRUE);
}

extern "C" JNIEXPORT void JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeSetVirtualBass(
        JNIEnv*, jclass, jlong handle, jdouble amount) {
    if (!handle) return;
    dsp_set_virtual_bass(reinterpret_cast<void*>(handle), amount);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeProcessPcm16Direct(
        JNIEnv* env, jclass, jlong handle, jobject buffer, jint frames,
        jint channels, jdouble /*sampleRate*/) {
    if (!handle || frames <= 0 || frames > kMaxFrames ||
        channels <= 0 || channels > kMaxCh) {
        return -1;
    }
    if (!g_scratch_in || !g_scratch_out) {
        if (!ensure_scratch()) return -2;
    }

    void* addr = env->GetDirectBufferAddress(buffer);
    if (!addr) return -3;

    int16_t* pcm = static_cast<int16_t*>(addr);
    const int n = frames * channels;

    for (int i = 0; i < n; ++i) {
        g_scratch_in[i] = (float)pcm[i] * (1.0f / 32768.0f);
    }

    dsp_process(reinterpret_cast<void*>(handle), g_scratch_in, g_scratch_out, frames);

    for (int i = 0; i < n; ++i) {
        float s = soft_clip(g_scratch_out[i]);
        if (s > 1.0f) s = 1.0f;
        if (s < -1.0f) s = -1.0f;
        pcm[i] = (int16_t)lrintf(s * 32767.0f);
    }
    return 0;
}
