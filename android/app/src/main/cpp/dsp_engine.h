/**
 * DSP ENGINE public C ABI — vendored with Resonate.
 *
 * Protection chain (final stages last so DVC cannot defeat the ceiling):
 *   EQ → speaker/bass → auto headroom → DVC → limiter → soft-clip → out
 *
 * Scratch buffers live on the handle (no shared globals across A/B players).
 * dsp_process / dsp_process_pcm16 never allocate.
 */
#pragma once

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

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

void* dsp_create(const DspConfig* config);
void  dsp_destroy(void* handle);
int   dsp_start(void* handle);
int   dsp_stop(void* handle);

/** Interleaved float32 in/out. in may equal out. */
void  dsp_process(void* handle, const float* in, float* out, int32_t frames);

/**
 * In-place PCM16 processing using the handle's private float scratch.
 * Returns 0 on success, negative on error.
 */
int   dsp_process_pcm16(void* handle, int16_t* interleaved, int32_t frames);

void  dsp_set_volume(void* handle, double linear_gain);
void  dsp_eq_set_enabled(void* handle, bool enabled);
void  dsp_eq_set_bands(void* handle, const double* centers_hz, const double* gains_db, int32_t count);
void  dsp_eq_set_band(void* handle, int32_t index, double freq_hz, double gain_db, double q);

void  dsp_set_speaker_mode(void* handle, bool enabled);
void  dsp_set_virtual_bass(void* handle, double amount);

void  dsp_get_stats(void* handle, DspStats* out);
void  dsp_reset_stats(void* handle);

#ifdef __cplusplus
}
#endif
