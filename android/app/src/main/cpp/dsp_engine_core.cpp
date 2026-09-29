/**
 * Vendored DSP ENGINE core — RBJ peaking EQ, DVC, soft limiter, virtual bass.
 * All working memory is owned by the handle; dsp_process never allocates.
 */
#include "dsp_engine.h"

#include <new>
#include <cmath>
#include <cstring>
#include <algorithm>

namespace {

constexpr int kMaxBands = 31;
constexpr int kMaxCh = 2;
constexpr int kMaxFrames = 4096;

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
        b0 = b0n / a0n;
        b1 = b1n / a0n;
        b2 = b2n / a0n;
        a1 = a1n / a0n;
        a2 = a2n / a0n;
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
        b0 = b0n / a0n;
        b1 = b1n / a0n;
        b2 = b2n / a0n;
        a1 = a1n / a0n;
        a2 = a2n / a0n;
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
        b0 = b0n / a0n;
        b1 = b1n / a0n;
        b2 = b2n / a0n;
        a1 = a1n / a0n;
        a2 = a2n / a0n;
    }
};

struct Engine {
    int sample_rate = 44100;
    int channels = 2;
    int buffer_frames = kMaxFrames;

    double volume = 1.0;
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

    float env[kMaxCh]{};

    bool running = false;

    void rebuildEq() {
        for (int i = 0; i < band_count; ++i) {
            double q = 1.0;
            if (i > 0 && i < band_count - 1) {
                const double f0 = centers[i - 1];
                const double f2 = centers[i + 1];
                const double ratio = f2 / std::max(f0, 1.0);
                q = std::sqrt(ratio);
                if (q < 0.5) q = 0.5;
                if (q > 4.0) q = 4.0;
            }
            for (int c = 0; c < channels; ++c) {
                bands[i][c].setPeaking(sample_rate, centers[i], gains[i], q);
            }
        }
    }

    void rebuildSpeakerFilters() {
        for (int c = 0; c < channels; ++c) {
            hpf[c].setHighPass(sample_rate, 55.0);
            bass_lp[c].setLowPass(sample_rate, 90.0);
            bass_bp[c].setPeaking(sample_rate, 160.0, 0.0, 0.8);
        }
    }
};

inline float soft_ceiling(float x) {
    const float ax = std::fabs(x);
    if (ax <= 0.88f) return x;
    const float s = (x >= 0.0f) ? 1.0f : -1.0f;
    const float over = ax - 0.88f;
    const float y = 0.88f + over / (1.0f + over * 3.2f);
    return s * (y > 0.98f ? 0.98f : y);
}

inline float limit_sample(float x, float& env, float threshold, float release) {
    const float ax = std::fabs(x);
    if (ax > env) {
        env = ax;
    } else {
        env = env * release + ax * (1.0f - release);
    }
    if (env <= threshold) return x;
    const float g = threshold / env;
    return x * g;
}

} // namespace

extern "C" {

void* dsp_create(const DspConfig* config) {
    auto* e = new (std::nothrow) Engine();
    if (!e) return nullptr;
    if (config) {
        e->sample_rate = config->sample_rate > 0 ? config->sample_rate : 44100;
        e->channels = config->channels >= 1 && config->channels <= kMaxCh
                          ? config->channels
                          : 2;
        e->buffer_frames = config->buffer_frames > 0
                               ? std::min(config->buffer_frames, kMaxFrames)
                               : kMaxFrames;
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
    return e;
}

void dsp_destroy(void* handle) {
    delete static_cast<Engine*>(handle);
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
    static_cast<Engine*>(handle)->eq_enabled = enabled;
}

void dsp_eq_set_bands(void* handle, const double* centers_hz,
                      const double* gains_db, int32_t count) {
    if (!handle || !gains_db || count <= 0) return;
    auto* e = static_cast<Engine*>(handle);
    if (count > kMaxBands) count = kMaxBands;
    e->band_count = count;
    for (int i = 0; i < count; ++i) {
        e->gains[i] = gains_db[i];
        if (centers_hz) {
            e->centers[i] = centers_hz[i];
        } else if (e->centers[i] <= 0.0) {
            e->centers[i] = 20.0 * std::pow(1000.0, i / (double)std::max(count - 1, 1));
        }
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
    for (int c = 0; c < e->channels; ++c) {
        e->bands[index][c].setPeaking(e->sample_rate, freq_hz, gain_db, q);
    }
}

void dsp_set_speaker_mode(void* handle, bool enabled) {
    if (!handle) return;
    auto* e = static_cast<Engine*>(handle);
    e->speaker_mode = enabled;
    e->rebuildSpeakerFilters();
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

    const int ch = e->channels;
    const float vol = static_cast<float>(e->volume);
    const bool eq = e->eq_enabled;
    const bool speaker = e->speaker_mode;
    const float vb = static_cast<float>(e->virtual_bass);
    const float thresh = speaker ? 0.82f : 0.90f;
    const float release = speaker ? 0.9992f : 0.9985f;

    for (int i = 0; i < frames; ++i) {
        for (int c = 0; c < ch; ++c) {
            float s = in[i * ch + c];

            if (eq) {
                for (int b = 0; b < e->band_count; ++b) {
                    s = e->bands[b][c].process(s);
                }
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

            s *= vol;
            s = limit_sample(s, e->env[c], thresh, release);
            s = soft_ceiling(s);
            out[i * ch + c] = s;
        }
    }
}

} // extern "C"
