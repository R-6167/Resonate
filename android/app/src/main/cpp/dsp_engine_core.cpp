/**
 * Vendored DSP ENGINE — per-handle scratch, protection-last chain.
 *
 * Chain: EQ → speaker/bass → auto headroom → DVC → limiter → soft-clip
 * No allocation inside dsp_process / dsp_process_pcm16.
 */
#include "dsp_engine.h"

#include <new>
#include <cmath>
#include <cstring>
#include <algorithm>
#include <cstdlib>
#include <time.h>

namespace {

constexpr int kMaxBands = 31;
constexpr int kMaxCh = 2;
constexpr int kMaxFrames = 4096;
constexpr size_t kAlign = 64;

struct Biquad {
    double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
    double z1 = 0, z2 = 0;
    void reset() { z1 = z2 = 0; }
    float process(float x) {
        const double y = b0 * x + z1;
        z1 = b1 * x - a1 * y + z2;
        z2 = b2 * x - a2 * y;
        return static_cast<float>(y);
    }
    void setPeaking(double sr, double freq, double gainDb, double q) {
        if (freq < 20.0) freq = 20.0;
        if (freq > sr * 0.49) freq = sr * 0.49;
        if (q < 0.1) q = 0.707;
        const double A = std::pow(10.0, gainDb / 40.0);
        const double w0 = 2.0 * M_PI * freq / sr;
        const double alpha = std::sin(w0) / (2.0 * q);
        const double cosw = std::cos(w0);
        const double b0n = 1.0 + alpha * A;
        const double b1n = -2.0 * cosw;
        const double b2n = 1.0 - alpha * A;
        const double a0n = 1.0 + alpha / A;
        const double a1n = -2.0 * cosw;
        const double a2n = 1.0 - alpha / A;
        b0 = b0n / a0n; b1 = b1n / a0n; b2 = b2n / a0n;
        a1 = a1n / a0n; a2 = a2n / a0n;
    }
    void setHighPass(double sr, double freq) {
        if (freq < 10.0) freq = 10.0;
        const double w0 = 2.0 * M_PI * freq / sr;
        const double cosw = std::cos(w0);
        const double sinw = std::sin(w0);
        const double alpha = sinw / (2.0 * 0.707);
        const double b0n = (1.0 + cosw) / 2.0;
        const double b1n = -(1.0 + cosw);
        const double b2n = (1.0 + cosw) / 2.0;
        const double a0n = 1.0 + alpha;
        const double a1n = -2.0 * cosw;
        const double a2n = 1.0 - alpha;
        b0 = b0n / a0n; b1 = b1n / a0n; b2 = b2n / a0n;
        a1 = a1n / a0n; a2 = a2n / a0n;
    }
    void setLowPass(double sr, double freq) {
        if (freq < 20.0) freq = 20.0;
        const double w0 = 2.0 * M_PI * freq / sr;
        const double cosw = std::cos(w0);
        const double sinw = std::sin(w0);
        const double alpha = sinw / (2.0 * 0.707);
        const double b0n = (1.0 - cosw) / 2.0;
        const double b1n = 1.0 - cosw;
        const double b2n = (1.0 - cosw) / 2.0;
        const double a0n = 1.0 + alpha;
        const double a1n = -2.0 * cosw;
        const double a2n = 1.0 - alpha;
        b0 = b0n / a0n; b1 = b1n / a0n; b2 = b2n / a0n;
        a1 = a1n / a0n; a2 = a2n / a0n;
    }
};

struct PeakLimiter {
    float envelope = 0.f;
    float attack_coeff = 0.f;
    float release_coeff = 0.f;
    float ceiling = 0.8912509f;
    void configure(int sample_rate, float attack_ms, float release_ms, float ceiling_db) {
        if (sample_rate < 8000) sample_rate = 44100;
        const float atk = std::max(0.1f, attack_ms) * 0.001f;
        const float rel = std::max(1.0f, release_ms) * 0.001f;
        attack_coeff = std::exp(-1.0f / (atk * (float)sample_rate));
        release_coeff = std::exp(-1.0f / (rel * (float)sample_rate));
        ceiling = std::pow(10.0f, ceiling_db / 20.0f);
        if (ceiling > 0.99f) ceiling = 0.99f;
        if (ceiling < 0.1f) ceiling = 0.1f;
    }
    float process(float x) {
        const float ax = std::fabs(x);
        if (ax > envelope) {
            envelope = attack_coeff * envelope + (1.0f - attack_coeff) * ax;
            if (ax > envelope) envelope = ax;
        } else {
            envelope = release_coeff * envelope + (1.0f - release_coeff) * ax;
        }
        if (envelope <= ceiling || envelope < 1e-8f) return x;
        return x * (ceiling / envelope);
    }
};

inline float soft_clip(float x, float knee_start) {
    const float ax = std::fabs(x);
    if (ax <= knee_start) return x;
    const float s = (x >= 0.0f) ? 1.0f : -1.0f;
    const float over = ax - knee_start;
    const float y = knee_start + over / (1.0f + over * 3.5f);
    return s * (y > 0.985f ? 0.985f : y);
}

struct Engine {
    int sample_rate = 44100;
    int channels = 2;
    int buffer_frames = kMaxFrames;
    double volume = 1.0;
    float headroom_gain = 1.0f;
    bool eq_enabled = true;
    bool speaker_mode = false;
    double virtual_bass = 0.55;
    int band_count = 0;
    double centers[kMaxBands]{};
    double gains[kMaxBands]{};
    Biquad bands[kMaxBands][kMaxCh];
    Biquad hpf[kMaxCh];
    Biquad bass_lp[kMaxCh];
    Biquad bass_bp[kMaxCh];
    PeakLimiter limiter[kMaxCh];

    float* scratch_in = nullptr;
    float* scratch_out = nullptr;
    size_t scratch_floats = 0;

    int64_t process_calls = 0;
    int64_t total_ns = 0;
    int64_t max_ns = 0;
    int64_t overrun_count = 0;
    int32_t last_frames = 0;
    bool running = false;

    bool allocScratch() {
        scratch_floats = (size_t)kMaxFrames * (size_t)kMaxCh;
        if (posix_memalign((void**)&scratch_in, kAlign, scratch_floats * sizeof(float)) != 0) {
            scratch_in = nullptr;
            return false;
        }
        if (posix_memalign((void**)&scratch_out, kAlign, scratch_floats * sizeof(float)) != 0) {
            free(scratch_in);
            scratch_in = nullptr;
            return false;
        }
        return true;
    }

    void freeScratch() {
        free(scratch_in);
        free(scratch_out);
        scratch_in = scratch_out = nullptr;
        scratch_floats = 0;
    }

    void rebuildEq() {
        double max_pos = 0.0;
        for (int i = 0; i < band_count; ++i) {
            if (gains[i] > max_pos) max_pos = gains[i];
            double q = 1.0;
            if (i > 0 && i < band_count - 1) {
                const double f0 = centers[i - 1];
                const double f2 = centers[i + 1];
                const double ratio = f2 / std::max(f0, 1.0);
                q = std::sqrt(ratio);
                if (q < 0.5) q = 0.5;
                if (q > 4.0) q = 4.0;
            }
            for (int c = 0; c < channels; ++c)
                bands[i][c].setPeaking(sample_rate, centers[i], gains[i], q);
        }
        if (eq_enabled && max_pos > 0.25) {
            headroom_gain = (float)std::pow(10.0, -(max_pos * 0.92) / 20.0);
        } else {
            headroom_gain = 1.0f;
        }
        if (speaker_mode) headroom_gain *= 0.841395f;
    }

    void rebuildSpeakerFilters() {
        for (int c = 0; c < channels; ++c) {
            hpf[c].setHighPass(sample_rate, 55.0);
            bass_lp[c].setLowPass(sample_rate, 90.0);
            bass_bp[c].setPeaking(sample_rate, 160.0, 0.0, 0.8);
        }
    }

    void rebuildLimiter() {
        const float atk = speaker_mode ? 2.0f : 3.0f;
        const float rel = speaker_mode ? 80.0f : 120.0f;
        const float ceil_db = speaker_mode ? -1.5f : -1.0f;
        for (int c = 0; c < channels; ++c)
            limiter[c].configure(sample_rate, atk, rel, ceil_db);
    }
};

} // namespace

extern "C" {

void* dsp_create(const DspConfig* config) {
    auto* e = new (std::nothrow) Engine();
    if (!e) return nullptr;
    if (config) {
        e->sample_rate = config->sample_rate > 0 ? config->sample_rate : 44100;
        e->channels = config->channels >= 1 && config->channels <= kMaxCh ? config->channels : 2;
        e->buffer_frames = config->buffer_frames > 0
                               ? std::min(config->buffer_frames, kMaxFrames)
                               : kMaxFrames;
    }
    if (!e->allocScratch()) {
        delete e;
        return nullptr;
    }
    static const double kDefaultHz[10] = {
        31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000};
    e->band_count = 10;
    for (int i = 0; i < 10; ++i) {
        e->centers[i] = kDefaultHz[i];
        e->gains[i] = 0.0;
    }
    e->rebuildEq();
    e->rebuildSpeakerFilters();
    e->rebuildLimiter();
    return e;
}

void dsp_destroy(void* handle) {
    if (!handle) return;
    auto* e = static_cast<Engine*>(handle);
    e->freeScratch();
    delete e;
}

int dsp_start(void* handle) {
    if (!handle) return -1;
    static_cast<Engine*>(handle)->running = true;
    return 0;
}

int dsp_stop(void* handle) {
    if (!handle) return -1;
    static_cast<Engine*>(handle)->running = false;
    return 0;
}

void dsp_set_volume(void* handle, double linear_gain) {
    if (!handle) return;
    auto* e = static_cast<Engine*>(handle);
    if (linear_gain < 0.0) linear_gain = 0.0;
    if (linear_gain > 4.0) linear_gain = 4.0;
    e->volume = linear_gain;
}

void dsp_eq_set_enabled(void* handle, bool enabled) {
    if (!handle) return;
    auto* e = static_cast<Engine*>(handle);
    e->eq_enabled = enabled;
    e->rebuildEq();
}

void dsp_eq_set_bands(void* handle, const double* centers_hz,
                      const double* gains_db, int32_t count) {
    if (!handle || !gains_db || count <= 0) return;
    auto* e = static_cast<Engine*>(handle);
    if (count > kMaxBands) count = kMaxBands;
    e->band_count = count;
    for (int i = 0; i < count; ++i) {
        e->gains[i] = gains_db[i];
        if (centers_hz) e->centers[i] = centers_hz[i];
        else if (e->centers[i] <= 0.0)
            e->centers[i] = 20.0 * std::pow(1000.0, i / (double)std::max(count - 1, 1));
    }
    e->rebuildEq();
}

void dsp_eq_set_band(void* handle, int32_t index, double freq_hz,
                     double gain_db, double q) {
    if (!handle || index < 0 || index >= kMaxBands) return;
    auto* e = static_cast<Engine*>(handle);
    if (index >= e->band_count) e->band_count = index + 1;
    e->centers[index] = freq_hz;
    e->gains[index] = gain_db;
    if (q <= 0.0) q = 1.0;
    for (int c = 0; c < e->channels; ++c)
        e->bands[index][c].setPeaking(e->sample_rate, freq_hz, gain_db, q);
    e->rebuildEq();
}

void dsp_set_speaker_mode(void* handle, bool enabled) {
    if (!handle) return;
    auto* e = static_cast<Engine*>(handle);
    e->speaker_mode = enabled;
    e->rebuildSpeakerFilters();
    e->rebuildEq();
    e->rebuildLimiter();
}

void dsp_set_virtual_bass(void* handle, double amount) {
    if (!handle) return;
    auto* e = static_cast<Engine*>(handle);
    if (amount < 0.0) amount = 0.0;
    if (amount > 1.0) amount = 1.0;
    e->virtual_bass = amount;
}

void dsp_process(void* handle, const float* in, float* out, int32_t frames) {
    if (!handle || !in || !out || frames <= 0) return;
    auto* e = static_cast<Engine*>(handle);
    if (frames > kMaxFrames) frames = kMaxFrames;

    struct timespec t0{}, t1{};
    clock_gettime(CLOCK_MONOTONIC, &t0);

    const int ch = e->channels;
    const float vol = static_cast<float>(e->volume);
    const float hr = e->headroom_gain;
    const bool eq = e->eq_enabled;
    const bool speaker = e->speaker_mode;
    const float vb = static_cast<float>(e->virtual_bass);
    const float knee = speaker ? 0.80f : 0.88f;

    for (int i = 0; i < frames; ++i) {
        for (int c = 0; c < ch; ++c) {
            float s = in[i * ch + c];

            if (eq) {
                for (int b = 0; b < e->band_count; ++b)
                    s = e->bands[b][c].process(s);
            }

            if (speaker) {
                const float deep = e->bass_lp[c].process(s);
                s = e->hpf[c].process(s);
                if (vb > 0.01f) {
                    float h = deep;
                    h = h - 0.35f * h * h * h;
                    h = e->bass_bp[c].process(h);
                    s += h * (0.35f * vb);
                }
            }

            s *= hr;
            s *= vol;
            s = e->limiter[c].process(s);
            s = soft_clip(s, knee);

            if (s > 1.0f) s = 1.0f;
            if (s < -1.0f) s = -1.0f;
            out[i * ch + c] = s;
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    const int64_t ns = (int64_t)(t1.tv_sec - t0.tv_sec) * 1000000000LL
                     + (int64_t)(t1.tv_nsec - t0.tv_nsec);
    e->process_calls += 1;
    e->total_ns += ns;
    if (ns > e->max_ns) e->max_ns = ns;
    e->last_frames = frames;
    if (e->sample_rate > 0 && frames > 0) {
        const int64_t budget_ns =
            (int64_t)frames * 1000000000LL / (int64_t)e->sample_rate;
        if (ns > budget_ns) e->overrun_count += 1;
    }
}

int dsp_process_pcm16(void* handle, int16_t* interleaved, int32_t frames) {
    if (!handle || !interleaved || frames <= 0) return -1;
    auto* e = static_cast<Engine*>(handle);
    if (frames > kMaxFrames) return -2;
    if (!e->scratch_in || !e->scratch_out) return -3;

    const int ch = e->channels;
    const int n = frames * ch;
    for (int i = 0; i < n; ++i)
        e->scratch_in[i] = (float)interleaved[i] * (1.0f / 32768.0f);

    dsp_process(handle, e->scratch_in, e->scratch_out, frames);

    for (int i = 0; i < n; ++i) {
        float s = e->scratch_out[i];
        if (s > 1.0f) s = 1.0f;
        if (s < -1.0f) s = -1.0f;
        interleaved[i] = (int16_t)lrintf(s * 32767.0f);
    }
    return 0;
}

void dsp_get_stats(void* handle, DspStats* out) {
    if (!out) return;
    out->process_calls = 0;
    out->total_ns = 0;
    out->max_ns = 0;
    out->overrun_count = 0;
    out->last_frames = 0;
    out->sample_rate = 0;
    out->channels = 0;
    if (!handle) return;
    auto* e = static_cast<Engine*>(handle);
    out->process_calls = e->process_calls;
    out->total_ns = e->total_ns;
    out->max_ns = e->max_ns;
    out->overrun_count = e->overrun_count;
    out->last_frames = e->last_frames;
    out->sample_rate = e->sample_rate;
    out->channels = e->channels;
}

void dsp_reset_stats(void* handle) {
    if (!handle) return;
    auto* e = static_cast<Engine*>(handle);
    e->process_calls = 0;
    e->total_ns = 0;
    e->max_ns = 0;
    e->overrun_count = 0;
    e->last_frames = 0;
}

} // extern "C"
