/**
 * JNI bridge — linked to vendored libdsp_engine.
 * No global scratch: each handle owns its float buffers.
 */
#include <jni.h>
#include <android/log.h>
#include <stdint.h>
#include <math.h>

#include "dsp_engine.h"

#define LOG_TAG "DspEngineJni"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static constexpr int kMaxFrames = 4096;
static constexpr int kMaxCh = 2;
static constexpr int kMaxEqBands = 31;

extern "C" JNIEXPORT jlong JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeCreate(
        JNIEnv*, jclass, jdouble sampleRate, jint channels) {
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
    LOGI("dsp_create ok handle=%p sr=%d ch=%d (per-handle scratch)", h, sr, channels);
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

    void* addr = env->GetDirectBufferAddress(buffer);
    if (!addr) return -3;

    int16_t* pcm = static_cast<int16_t*>(addr);
    return dsp_process_pcm16(reinterpret_cast<void*>(handle), pcm, frames);
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeGetStats(
        JNIEnv* env, jclass, jlong handle) {
    jdoubleArray arr = env->NewDoubleArray(6);
    if (!arr) return nullptr;
    double vals[6] = {0, 0, 0, 0, 0, 0};
    if (handle) {
        DspStats st{};
        dsp_get_stats(reinterpret_cast<void*>(handle), &st);
        vals[0] = (double)st.process_calls;
        vals[1] = st.process_calls > 0
                      ? ((double)st.total_ns / (double)st.process_calls) / 1000.0
                      : 0.0;
        vals[2] = (double)st.max_ns / 1000.0;
        vals[3] = (double)st.overrun_count;
        vals[4] = (double)st.last_frames;
        vals[5] = (double)st.sample_rate;
    }
    env->SetDoubleArrayRegion(arr, 0, 6, vals);
    return arr;
}

extern "C" JNIEXPORT void JNICALL
Java_com_aetherion_resonate_dsp_DspEngineJni_nativeResetStats(
        JNIEnv*, jclass, jlong handle) {
    if (!handle) return;
    dsp_reset_stats(reinterpret_cast<void*>(handle));
}
