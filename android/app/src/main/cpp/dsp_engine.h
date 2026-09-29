/**
 * DSP ENGINE public C ABI — vendored with Resonate.
 * Real-time safe: no allocation inside dsp_process.
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

void* dsp_create(const DspConfig* config);
void  dsp_destroy(void* handle);
int   dsp_start(void* handle);
int   dsp_stop(void* handle);

/** Process interleaved float32 in [-1,1]. in may equal out. frames <= buffer_frames. */
void  dsp_process(void* handle, const float* in, float* out, int32_t frames);

void  dsp_set_volume(void* handle, double linear_gain);
void  dsp_eq_set_enabled(void* handle, bool enabled);
void  dsp_eq_set_bands(void* handle, const double* centers_hz, const double* gains_db, int32_t count);
void  dsp_eq_set_band(void* handle, int32_t index, double freq_hz, double gain_db, double q);

/**
 * Speaker delivery mode: mild HPF + psychoacoustic virtual bass + tighter ceiling.
 * Safe on headphones when off (default).
 */
void  dsp_set_speaker_mode(void* handle, bool enabled);

/** Virtual-bass amount 0..1 (only applied when speaker mode is on). */
void  dsp_set_virtual_bass(void* handle, double amount);

#ifdef __cplusplus
}
#endif
