/**
 * DSP ENGINE public C ABI — standalone v0.4
 *
 * Chain: DC → EQ → speaker/bass → headroom → preamp → DVC
 *        → LR4 → 2-band crest-aware true-peak → soft-clip
 */
#pragma once

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define DSP_ENGINE_VERSION_MAJOR 0
#define DSP_ENGINE_VERSION_MINOR 4
#define DSP_ENGINE_VERSION_PATCH 0
#define DSP_ENGINE_VERSION_STRING "0.4.0"

/** Feature bitmask for dsp_get_info(). */
enum {
    DSP_FEATURE_EQ            = 1u << 0,
    DSP_FEATURE_DVC           = 1u << 1,
    DSP_FEATURE_TRUE_PEAK     = 1u << 2,
    DSP_FEATURE_STEREO_LINK   = 1u << 3,
    DSP_FEATURE_TWO_BAND      = 1u << 4,
    DSP_FEATURE_NEON          = 1u << 5,
    DSP_FEATURE_DC_BLOCK      = 1u << 6,
    DSP_FEATURE_PARAM_RAMP    = 1u << 7,
    DSP_FEATURE_CREST_RELEASE = 1u << 8,
    DSP_FEATURE_SPEAKER_VB    = 1u << 9,
    DSP_FEATURE_PREAMP        = 1u << 10
};

typedef struct DspConfig {
    int32_t sample_rate;
    int32_t channels;
    int32_t buffer_frames;
    bool    exclusive_mode;
    bool    bit_perfect;
    int32_t realtime_priority;
} DspConfig;

typedef struct DspStats {
    int64_t process_calls;
    int64_t total_ns;
    int64_t max_ns;
    int64_t overrun_count;
    int32_t last_frames;
    int32_t sample_rate;
    int32_t channels;
} DspStats;

typedef struct DspInfo {
    int32_t version_major;
    int32_t version_minor;
    int32_t version_patch;
    int32_t sample_rate;
    int32_t channels;
    int32_t max_bands;
    int32_t max_frames;
    uint32_t features;
} DspInfo;

typedef struct DspStressResult {
    int32_t cases_run;
    int32_t cases_passed;
    float   max_abs_peak;
    int32_t peak_failures;
    int32_t nan_failures;
    int32_t speaker_cases_ok;
    int64_t avg_ns_per_call;
    int64_t max_ns_per_call;
    int64_t budget_ns;
    double  cpu_pct_of_budget;
    int32_t overrun_calls;
} DspStressResult;

void* dsp_create(const DspConfig* config);
void  dsp_destroy(void* handle);
int   dsp_start(void* handle);
int   dsp_stop(void* handle);

void  dsp_process(void* handle, const float* in, float* out, int32_t frames);
int   dsp_process_pcm16(void* handle, int16_t* interleaved, int32_t frames);

void  dsp_set_volume(void* handle, double linear_gain);
void  dsp_set_preamp(void* handle, double linear_gain);

void  dsp_eq_set_enabled(void* handle, bool enabled);
void  dsp_eq_set_bands(void* handle, const double* centers_hz, const double* gains_db, int32_t count);
void  dsp_eq_set_band(void* handle, int32_t index, double freq_hz, double gain_db, double q);

void  dsp_set_speaker_mode(void* handle, bool enabled);
void  dsp_set_virtual_bass(void* handle, double amount);

void  dsp_get_stats(void* handle, DspStats* out);
void  dsp_reset_stats(void* handle);
int   dsp_get_info(void* handle, DspInfo* out);

int   dsp_run_bass_stress(DspStressResult* out);

#ifdef __cplusplus
}
#endif
