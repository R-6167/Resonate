/**
 * Thin JNI bridge for DSP ENGINE live path.
 *
 * - dlopen("libdsp_engine.so") so we do not rebuild the engine here
 * - Pre-allocated float scratch (64-byte aligned, max 4096 frames × 2 ch)
 * - GetDirectBufferAddress only when buffer identity changes (cached)
 * - PCM16 LE ↔ float conversion around dsp_process (float ABI)
 *
 * Locked constants: see docs/DSP_JNI_BUFFERS.md
 */

#include <android/log.h>
#include <dlfcn.h>
#include <jni.h>

#include <cstdint>
#include <cstdlib>
#include <cstring>

#define LOG_TAG "DspEngineJni"
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace {

constexpr int kAlignBytes = 64;
constexpr int kMaxChannels = 2;
constexpr int kMaxFrames = 4096;
constexpr size_t kMaxFloatSamples = static_cast<size_t>(kMaxFrames) * kMaxChannels;

struct DspConfig {
  int32_t sample_rate;
  int32_t channels;
  int32_t buffer_frames;
  bool exclusive_mode;
  bool bit_perfect;
  int32_t realtime_priority;
};

using DspCreateFn = void* (*)(const DspConfig*);
using DspDestroyFn = void (*)(void*);
using DspStartFn = int32_t (*)(void*);
using DspStopFn = int32_t (*)(void*);
using DspProcessFn = void (*)(void*, const float*, float*, int32_t);

struct EngineFns {
  void* handle = nullptr;
  DspCreateFn create = nullptr;
  DspDestroyFn destroy = nullptr;
  DspStartFn start = nullptr;
  DspStopFn stop = nullptr;
  DspProcessFn process = nullptr;
  bool ready = false;
};

EngineFns g_fns;

struct NativeEngine {
  void* engine = nullptr;
  int channels = 2;
  int sample_rate = 48000;

  // Preallocated scratch (never malloc on audio thread).
  float* scratch_in = nullptr;
  float* scratch_out = nullptr;

  // Cached direct-buffer identity → address (PCM16 path may change each callback).
  jobject last_in_global = nullptr;
  void* last_in_addr = nullptr;
  jobject last_out_global = nullptr;
  void* last_out_addr = nullptr;
};

bool ensure_lib() {
  if (g_fns.ready) return true;
  void* h = dlopen("libdsp_engine.so", RTLD_NOW);
  if (!h) {
    ALOGE("dlopen libdsp_engine.so failed: %s", dlerror());
    return false;
  }
  g_fns.handle = h;
  g_fns.create = reinterpret_cast<DspCreateFn>(dlsym(h, "dsp_create"));
  g_fns.destroy = reinterpret_cast<DspDestroyFn>(dlsym(h, "dsp_destroy"));
  g_fns.start = reinterpret_cast<DspStartFn>(dlsym(h, "dsp_start"));
  g_fns.stop = reinterpret_cast<DspStopFn>(dlsym(h, "dsp_stop"));
  g_fns.process = reinterpret_cast<DspProcessFn>(dlsym(h, "dsp_process"));
  if (!g_fns.create || !g_fns.destroy || !g_fns.process) {
    ALOGE("dlsym missing dsp_* symbols");
    return false;
  }
  g_fns.ready = true;
  ALOGI("libdsp_engine.so resolved");
  return true;
}

void* aligned_alloc_local(size_t bytes) {
  void* p = nullptr;
  if (posix_memalign(&p, static_cast<size_t>(kAlignBytes), bytes) != 0) {
    p = nullptr;
  }
  if (p) std::memset(p, 0, bytes);
  return p;
}

void* cached_direct_addr(JNIEnv* env, jobject buf, jobject* global_holder, void** cached_addr) {
  if (buf == nullptr) return nullptr;
  // Same Java object as last time → reuse cached address (no JNI call).
  if (*global_holder != nullptr && env->IsSameObject(buf, *global_holder)) {
    return *cached_addr;
  }
  void* addr = env->GetDirectBufferAddress(buf);
  if (addr == nullptr) return nullptr;
  if (*global_holder != nullptr) {
    env->DeleteGlobalRef(*global_holder);
    *global_holder = nullptr;
  }
  *global_holder = env->NewGlobalRef(buf);
  *cached_addr = addr;
  return addr;
}

}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_Aetherion_Resonate_dsp_DspEngineJni_nativeCreate(
    JNIEnv* /*env*/, jclass /*clazz*/,
    jint sample_rate, jint channels, jint buffer_frames) {
  if (!ensure_lib()) return 0;
  if (channels < 1 || channels > kMaxChannels) return 0;
  if (buffer_frames < 1 || buffer_frames > kMaxFrames) buffer_frames = kMaxFrames;

  auto* ne = new NativeEngine();
  ne->channels = channels;
  ne->sample_rate = sample_rate;

  const size_t scratch_bytes = kMaxFloatSamples * sizeof(float);
  ne->scratch_in = static_cast<float*>(aligned_alloc_local(scratch_bytes));
  ne->scratch_out = static_cast<float*>(aligned_alloc_local(scratch_bytes));
  if (!ne->scratch_in || !ne->scratch_out) {
    free(ne->scratch_in);
    free(ne->scratch_out);
    delete ne;
    return 0;
  }

  DspConfig cfg{};
  cfg.sample_rate = sample_rate;
  cfg.channels = channels;
  cfg.buffer_frames = buffer_frames;
  cfg.exclusive_mode = false;
  cfg.bit_perfect = true;
  cfg.realtime_priority = 1;

  ne->engine = g_fns.create(&cfg);
  if (!ne->engine) {
    free(ne->scratch_in);
    free(ne->scratch_out);
    delete ne;
    return 0;
  }
  if (g_fns.start) g_fns.start(ne->engine);
  return reinterpret_cast<jlong>(ne);
}

extern "C" JNIEXPORT void JNICALL
Java_com_Aetherion_Resonate_dsp_DspEngineJni_nativeDestroy(
    JNIEnv* env, jclass /*clazz*/, jlong handle) {
  if (handle == 0) return;
  auto* ne = reinterpret_cast<NativeEngine*>(handle);
  if (ne->engine) {
    if (g_fns.stop) g_fns.stop(ne->engine);
    if (g_fns.destroy) g_fns.destroy(ne->engine);
  }
  if (ne->last_in_global) env->DeleteGlobalRef(ne->last_in_global);
  if (ne->last_out_global) env->DeleteGlobalRef(ne->last_out_global);
  free(ne->scratch_in);
  free(ne->scratch_out);
  delete ne;
}

/**
 * Process interleaved PCM 16-bit LE in a direct ByteBuffer.
 * in/out may be the same buffer (in-place after conversion via scratch).
 * Returns frames processed, or negative on error.
 */
extern "C" JNIEXPORT jint JNICALL
Java_com_Aetherion_Resonate_dsp_DspEngineJni_nativeProcessPcm16Direct(
    JNIEnv* env, jclass /*clazz*/,
    jlong handle,
    jobject in_buf, jint in_offset,
    jobject out_buf, jint out_offset,
    jint frames) {
  if (handle == 0 || frames <= 0 || frames > kMaxFrames) return -1;
  auto* ne = reinterpret_cast<NativeEngine*>(handle);
  if (!ne->engine || !g_fns.process) return -2;

  auto* in_base = static_cast<uint8_t*>(
      cached_direct_addr(env, in_buf, &ne->last_in_global, &ne->last_in_addr));
  auto* out_base = static_cast<uint8_t*>(
      cached_direct_addr(env, out_buf, &ne->last_out_global, &ne->last_out_addr));
  if (!in_base || !out_base) return -3;

  const int ch = ne->channels;
  const int samples = frames * ch;
  if (static_cast<size_t>(samples) > kMaxFloatSamples) return -4;

  const auto* in_pcm = reinterpret_cast<const int16_t*>(in_base + in_offset);
  auto* out_pcm = reinterpret_cast<int16_t*>(out_base + out_offset);

  // PCM16 → float [-1, 1)
  constexpr float kScale = 1.0f / 32768.0f;
  for (int i = 0; i < samples; ++i) {
    ne->scratch_in[i] = static_cast<float>(in_pcm[i]) * kScale;
  }

  g_fns.process(ne->engine, ne->scratch_in, ne->scratch_out, frames);

  // float → PCM16 with soft clip
  for (int i = 0; i < samples; ++i) {
    float s = ne->scratch_out[i];
    if (s > 1.0f) s = 1.0f;
    if (s < -1.0f) s = -1.0f;
    out_pcm[i] = static_cast<int16_t>(s * 32767.0f);
  }
  return frames;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_Aetherion_Resonate_dsp_DspEngineJni_nativeIsLibReady(
    JNIEnv* /*env*/, jclass /*clazz*/) {
  return ensure_lib() ? JNI_TRUE : JNI_FALSE;
}
