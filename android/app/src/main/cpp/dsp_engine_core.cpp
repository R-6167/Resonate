/**
 * DSP ENGINE — stereo-linked, crest-aware, 2-band, NEON-ready.
 *
 * Chain:
 *   DC-block → EQ → speaker/bass → headroom → preamp → DVC (smoothed)
 *   → LR4 crossover (user Hz) → 2-band crest-aware true-peak
 *   → sum → soft-clip
 *
 * Process path never allocates. Look-ahead ~4 ms.
 * Parameter ramps (~8 ms) avoid zipper on volume / headroom / VB / preamp.
 */
#include "dsp_engine.h"

#include <new>
#include <cmath>
#include <cstring>
#include <algorithm>
#include <cstdlib>
#include <atomic>
#include <mutex>
#include <time.h>

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>
#define DSP_NEON 1
#else
#define DSP_NEON 0
#endif

namespace {

constexpr int kMaxBands = 31;
constexpr int kMaxCh = 2;
constexpr int kMaxFrames = 4096;
constexpr size_t kAlign = 64;
constexpr int kOsFactor = 4;
constexpr int kMaxLookahead = 512;
constexpr float kXoverHz = 120.0f;

inline float sanitize(float x) {
    if (!std::isfinite(x)) return 0.f;
    if (x > 8.f) return 8.f;
    if (x < -8.f) return -8.f;
    return x;
}

struct DcBlocker {
    float x1 = 0.f;
    float y1 = 0.f;
    float R = 0.995f;

    void configure(int sample_rate, float fc_hz = 8.0f) {
        if (sample_rate < 8000) sample_rate = 44100;
        if (fc_hz < 1.f) fc_hz = 1.f;
        if (fc_hz > 40.f) fc_hz = 40.f;
        R = 1.0f - (2.0f * (float)M_PI * fc_hz / (float)sample_rate);
        if (R < 0.90f) R = 0.90f;
        if (R > 0.9999f) R = 0.9999f;
        x1 = y1 = 0.f;
    }

    float process(float x) {
        x = sanitize(x);
        const float y = x - x1 + R * y1;
        x1 = x;
        y1 = y;
        return sanitize(y);
    }
};

struct Smoothed {
    float current = 1.f;
    float target = 1.f;
    float coeff = 0.f;

    void configure(int sample_rate, float time_ms) {
        if (sample_rate < 8000) sample_rate = 44100;
        if (time_ms < 0.5f) time_ms = 0.5f;
        coeff = std::exp(-1.0f / (time_ms * 0.001f * (float)sample_rate));
    }

    void set_target(float t) { target = t; }
    void snap(float t) { current = target = t; }

    float next() {
        current = coeff * current + (1.0f - coeff) * target;
        return current;
    }
};

struct Biquad {
    double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
    double z1 = 0, z2 = 0;
    void reset() { z1 = z2 = 0; }

    float process(float x) {
        x = sanitize(x);
        const double y = b0 * x + z1;
        z1 = b1 * x - a1 * y + z2;
        z2 = b2 * x - a2 * y;
        return sanitize(static_cast<float>(y));
    }

    void setPeaking(double sr, double freq, double gainDb, double q) {
        if (freq < 20.0) freq = 20.0;
        if (freq > sr * 0.49) freq = sr * 0.49;
        if (q < 0.1) q = 0.707;
        if (gainDb > 24.0) gainDb = 24.0;
        if (gainDb < -24.0) gainDb = -24.0;
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

    void setButterLP(double sr, double freq, double q) {
        if (freq < 20.0) freq = 20.0;
        if (q < 0.1) q = 0.707;
        const double w0 = 2.0 * M_PI * freq / sr;
        const double cosw = std::cos(w0);
        const double sinw = std::sin(w0);
        const double alpha = sinw / (2.0 * q);
        const double b0n = (1.0 - cosw) / 2.0;
        const double b1n = 1.0 - cosw;
        const double b2n = (1.0 - cosw) / 2.0;
        const double a0n = 1.0 + alpha;
        const double a1n = -2.0 * cosw;
        const double a2n = 1.0 - alpha;
        b0 = b0n / a0n; b1 = b1n / a0n; b2 = b2n / a0n;
        a1 = a1n / a0n; a2 = a2n / a0n;
    }

    void setButterHP(double sr, double freq, double q) {
        if (freq < 10.0) freq = 10.0;
        if (q < 0.1) q = 0.707;
        const double w0 = 2.0 * M_PI * freq / sr;
        const double cosw = std::cos(w0);
        const double sinw = std::sin(w0);
        const double alpha = sinw / (2.0 * q);
        const double b0n = (1.0 + cosw) / 2.0;
        const double b1n = -(1.0 + cosw);
        const double b2n = (1.0 + cosw) / 2.0;
        const double a0n = 1.0 + alpha;
        const double a1n = -2.0 * cosw;
        const double a2n = 1.0 - alpha;
        b0 = b0n / a0n; b1 = b1n / a0n; b2 = b2n / a0n;
        a1 = a1n / a0n; a2 = a2n / a0n;
    }
};

struct LR4Crossover {
    Biquad lp1, lp2, hp1, hp2;

    void configure(double sr, double freq) {
        const double q = 0.7071067811865476;
        lp1.setButterLP(sr, freq, q);
        lp2.setButterLP(sr, freq, q);
        hp1.setButterHP(sr, freq, q);
        hp2.setButterHP(sr, freq, q);
        lp1.reset(); lp2.reset(); hp1.reset(); hp2.reset();
    }

    void process(float x, float* low_out, float* high_out) {
        float lo = lp2.process(lp1.process(x));
        float hi = hp2.process(hp1.process(x));
        *low_out = lo;
        *high_out = -hi;
    }
};

struct LookaheadDetector {
    float prev_in = 0.f;
    float sc_x1 = 0.f;
    float sc_y1 = 0.f;
    float sc_a = 0.f;
    float delay[kMaxLookahead]{};
    int delay_len = 64;
    int delay_pos = 0;

    void configure(int sample_rate, float lookahead_ms) {
        if (sample_rate < 8000) sample_rate = 44100;
        const float fc = 90.0f;
        const float rc = 1.0f / (2.0f * (float)M_PI * fc);
        const float dt = 1.0f / (float)sample_rate;
        sc_a = rc / (rc + dt);
        sc_x1 = sc_y1 = 0.f;
        prev_in = 0.f;
        int la = (int)std::lround(lookahead_ms * 0.001f * (float)sample_rate);
        if (la < 8) la = 8;
        if (la > kMaxLookahead) la = kMaxLookahead;
        delay_len = la;
        delay_pos = 0;
        std::memset(delay, 0, sizeof(delay));
    }

    float truePeakAbs(float x) const {
        float peak = std::fabs(x);
        const float a = prev_in;
        const float b = x;
        const float d = b - a;
        for (int k = 1; k < kOsFactor; ++k) {
            const float y = a + d * ((float)k / (float)kOsFactor);
            const float ay = std::fabs(y);
            if (ay > peak) peak = ay;
        }
        const float mid = 0.5f * (a + b);
        const float am = std::fabs(mid);
        if (am > peak) peak = am;
        return peak;
    }

    float feed(float x, float* peak_out) {
        x = sanitize(x);
        const float sc = sc_a * (sc_y1 + x - sc_x1);
        sc_x1 = x;
        sc_y1 = sc;
        const float tp_full = truePeakAbs(x);
        const float tp_sc = truePeakAbs(sc);
        *peak_out = 0.55f * tp_sc + 0.45f * tp_full;
        prev_in = x;
        const float delayed = delay[delay_pos];
        delay[delay_pos] = x;
        delay_pos++;
        if (delay_pos >= delay_len) delay_pos = 0;
        return delayed;
    }
};

struct LinkedLimiter {
    float ceiling = 0.9440609f;
    float attack_coeff = 0.f;
    float release_fast = 0.f;
    float release_slow = 0.f;
    float envelope = 0.f;
    float avg = 0.f;
    float avg_coeff = 0.f;
    float gain = 1.f;

    void configure(int sample_rate, float attack_ms, float release_ms, float ceiling_db) {
        if (sample_rate < 8000) sample_rate = 44100;
        const float atk = std::max(0.05f, attack_ms) * 0.001f;
        const float rel = std::max(1.0f, release_ms) * 0.001f;
        attack_coeff = std::exp(-1.0f / (atk * (float)sample_rate));
        release_fast = std::exp(-1.0f / (rel * (float)sample_rate));
        release_slow = std::exp(-1.0f / (rel * 2.5f * (float)sample_rate));
        avg_coeff = std::exp(-1.0f / (0.050f * (float)sample_rate));
        ceiling = std::pow(10.0f, ceiling_db / 20.0f);
        if (ceiling > 0.995f) ceiling = 0.995f;
        if (ceiling < 0.1f) ceiling = 0.1f;
        envelope = 0.f;
        avg = 0.f;
        gain = 1.f;
    }

    float update(float linked_peak) {
        avg = avg_coeff * avg + (1.0f - avg_coeff) * linked_peak;
        const float crest = linked_peak / (avg + 1e-6f);
        float rel_blend = (crest - 1.0f) * 0.5f;
        if (rel_blend < 0.f) rel_blend = 0.f;
        if (rel_blend > 1.f) rel_blend = 1.f;
        const float release_coeff = release_slow + (release_fast - release_slow) * rel_blend;

        if (linked_peak > envelope) {
            envelope = attack_coeff * envelope + (1.0f - attack_coeff) * linked_peak;
            if (linked_peak > envelope) envelope = linked_peak;
        } else {
            envelope = release_coeff * envelope + (1.0f - release_coeff) * linked_peak;
        }

        float target = 1.f;
        if (envelope > ceiling && envelope > 1e-8f)
            target = ceiling / envelope;
        if (target < 0.08f) target = 0.08f;

        if (target < gain)
            gain = attack_coeff * gain + (1.0f - attack_coeff) * target;
        else
            gain = release_coeff * gain + (1.0f - release_coeff) * target;

        return gain;
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

#if DSP_NEON
inline void soft_clip_stereo(float s0, float s1, float knee, float* o0, float* o1) {
    float32x2_t v = {s0, s1};
    float tmp[2];
    vst1_f32(tmp, v);
    *o0 = soft_clip(sanitize(tmp[0]), knee);
    *o1 = soft_clip(sanitize(tmp[1]), knee);
    if (*o0 > 1.f) *o0 = 1.f;
    if (*o0 < -1.f) *o0 = -1.f;
    if (*o1 > 1.f) *o1 = 1.f;
    if (*o1 < -1.f) *o1 = -1.f;
}
#endif

enum class ControlType : uint8_t {
    Volume,
    Preamp,
    EqEnabled,
    EqBands,
    EqBand,
    SpeakerMode,
    VirtualBass,
    LimiterCeiling,
    CrossoverHz,
};

struct ControlCommand {
    ControlType type = ControlType::Volume;
    double value0 = 0.0;
    double value1 = 0.0;
    double value2 = 0.0;
    float float0 = 0.0f;
    float float1 = 0.0f;
    int32_t index = 0;
    int32_t count = 0;
    bool enabled = false;
    double centers[kMaxBands]{};
    double gains[kMaxBands]{};
};

// Control threads publish commands; the audio thread is the only code that
// mutates filter/stateful DSP objects. No mutex is ever taken from process().
struct ControlQueue {
    static constexpr uint32_t kCapacity = 128;
    ControlCommand commands[kCapacity];
    std::atomic<uint32_t> head{0};
    std::atomic<uint32_t> tail{0};
    std::mutex producer_mutex;

    bool push(const ControlCommand& command) {
        std::lock_guard<std::mutex> lock(producer_mutex);
        const uint32_t h = head.load(std::memory_order_relaxed);
        const uint32_t t = tail.load(std::memory_order_acquire);
        if (h - t >= kCapacity) return false;
        commands[h % kCapacity] = command;
        head.store(h + 1, std::memory_order_release);
        return true;
    }
};

struct Engine {
    int sample_rate = 44100;
    int channels = 2;
    int buffer_frames = kMaxFrames;
    double volume = 1.0;
    double preamp = 1.0;
    float headroom_gain = 1.0f;
    bool eq_enabled = true;
    bool speaker_mode = false;
    double virtual_bass = 0.55;
    float ceiling_db_high = -0.5f;
    float ceiling_db_low  = -0.2f;
    float xover_hz = kXoverHz;
    DcBlocker dc[kMaxCh];
    Smoothed sm_vol;
    Smoothed sm_hr;
    Smoothed sm_vb;
    Smoothed sm_pre;
    int band_count = 0;
    double centers[kMaxBands]{};
    double gains[kMaxBands]{};
    Biquad bands[kMaxBands][kMaxCh];
    Biquad hpf[kMaxCh];
    Biquad bass_lp[kMaxCh];
    Biquad bass_bp[kMaxCh];
    LR4Crossover xover[kMaxCh];
    LookaheadDetector det_low[kMaxCh];
    LookaheadDetector det_high[kMaxCh];
    LinkedLimiter lim_low;
    LinkedLimiter lim_high;

    float* scratch_in = nullptr;
    float* scratch_out = nullptr;
    size_t scratch_floats = 0;

    std::atomic<int64_t> process_calls{0};
    std::atomic<int64_t> total_ns{0};
    std::atomic<int64_t> max_ns{0};
    std::atomic<int64_t> overrun_count{0};
    std::atomic<int32_t> last_frames{0};
    std::atomic<bool> running{false};
    ControlQueue control_queue;

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
        if (eq_enabled && max_pos > 0.5) {
            const double comp = max_pos * 0.48;
            headroom_gain = (float)std::pow(10.0, -comp / 20.0);
        } else {
            headroom_gain = 1.0f;
        }
        if (speaker_mode) headroom_gain *= 0.92f;
        sm_hr.set_target(headroom_gain);
    }

    void rebuildSpeakerFilters() {
        for (int c = 0; c < channels; ++c) {
            hpf[c].setHighPass(sample_rate, 55.0);
            bass_lp[c].setLowPass(sample_rate, 90.0);
            bass_bp[c].setPeaking(sample_rate, 160.0, 0.0, 0.8);
        }
    }

    void rebuildXover() {
        for (int c = 0; c < channels; ++c)
            xover[c].configure((double)sample_rate, (double)xover_hz);
    }

    void rebuildLimiter() {
        const float atk_h = speaker_mode ? 1.2f : 2.0f;
        const float rel_h = speaker_mode ? 140.0f : 200.0f;
        const float atk_l = speaker_mode ? 2.0f : 3.0f;
        const float rel_l = speaker_mode ? 220.0f : 320.0f;
        float ceil_h = ceiling_db_high;
        float ceil_l = ceiling_db_low;
        if (speaker_mode) {
            ceil_h -= 0.5f;
            ceil_l -= 0.3f;
        }
        const float la_ms = 4.0f;
        lim_high.configure(sample_rate, atk_h, rel_h, ceil_h);
        lim_low.configure(sample_rate, atk_l, rel_l, ceil_l);
        for (int c = 0; c < channels; ++c) {
            det_high[c].configure(sample_rate, la_ms);
            det_low[c].configure(sample_rate, la_ms);
        }
    }

    void applyControlCommands() {
        const uint32_t head = control_queue.head.load(std::memory_order_acquire);
        uint32_t tail = control_queue.tail.load(std::memory_order_relaxed);
        while (tail != head) {
            const ControlCommand& cmd =
                control_queue.commands[tail % ControlQueue::kCapacity];
            switch (cmd.type) {
                case ControlType::Volume:
                    volume = cmd.value0;
                    sm_vol.set_target((float)cmd.value0);
                    break;
                case ControlType::Preamp:
                    preamp = cmd.value0;
                    sm_pre.set_target((float)cmd.value0);
                    break;
                case ControlType::EqEnabled:
                    eq_enabled = cmd.enabled;
                    rebuildEq();
                    break;
                case ControlType::EqBands:
                    band_count = cmd.count;
                    for (int i = 0; i < band_count; ++i) {
                        centers[i] = cmd.centers[i];
                        gains[i] = cmd.gains[i];
                    }
                    rebuildEq();
                    break;
                case ControlType::EqBand:
                    if (cmd.index >= 0 && cmd.index < kMaxBands) {
                        if (cmd.index >= band_count) band_count = cmd.index + 1;
                        centers[cmd.index] = cmd.value0;
                        gains[cmd.index] = cmd.value1;
                        for (int c = 0; c < channels; ++c)
                            bands[cmd.index][c].setPeaking(sample_rate, cmd.value0,
                                                           cmd.value1, cmd.value2);
                        rebuildEq();
                    }
                    break;
                case ControlType::SpeakerMode:
                    speaker_mode = cmd.enabled;
                    rebuildSpeakerFilters();
                    rebuildEq();
                    rebuildLimiter();
                    break;
                case ControlType::VirtualBass:
                    virtual_bass = cmd.value0;
                    sm_vb.set_target((float)cmd.value0);
                    break;
                case ControlType::LimiterCeiling:
                    ceiling_db_high = cmd.float0;
                    ceiling_db_low = cmd.float1;
                    rebuildLimiter();
                    break;
                case ControlType::CrossoverHz:
                    xover_hz = cmd.float0;
                    rebuildXover();
                    break;
            }
            ++tail;
            control_queue.tail.store(tail, std::memory_order_release);
        }
    }

    void configureSmoothersAndDc() {
        for (int c = 0; c < channels; ++c)
            dc[c].configure(sample_rate, 8.0f);
        sm_vol.configure(sample_rate, 8.0f);
        sm_hr.configure(sample_rate, 12.0f);
        sm_vb.configure(sample_rate, 15.0f);
        sm_pre.configure(sample_rate, 8.0f);
        sm_vol.snap((float)volume);
        sm_hr.snap(headroom_gain);
        sm_vb.snap((float)virtual_bass);
        sm_pre.snap((float)preamp);
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
    e->rebuildXover();
    e->rebuildLimiter();
    e->configureSmoothersAndDc();
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
    if (linear_gain < 0.0) linear_gain = 0.0;
    if (linear_gain > 4.0) linear_gain = 4.0;
    ControlCommand cmd;
    cmd.type = ControlType::Volume;
    cmd.value0 = linear_gain;
    static_cast<Engine*>(handle)->control_queue.push(cmd);
}

void dsp_set_preamp(void* handle, double linear_gain) {
    if (!handle) return;
    if (linear_gain < 0.0) linear_gain = 0.0;
    if (linear_gain > 4.0) linear_gain = 4.0;
    ControlCommand cmd;
    cmd.type = ControlType::Preamp;
    cmd.value0 = linear_gain;
    static_cast<Engine*>(handle)->control_queue.push(cmd);
}

int dsp_get_info(void* handle, DspInfo* out) {
    if (!out) return -1;
    out->version_major = DSP_ENGINE_VERSION_MAJOR;
    out->version_minor = DSP_ENGINE_VERSION_MINOR;
    out->version_patch = DSP_ENGINE_VERSION_PATCH;
    out->sample_rate = 0;
    out->channels = 0;
    out->max_bands = kMaxBands;
    out->max_frames = kMaxFrames;
    uint32_t f = 0;
    f |= DSP_FEATURE_EQ;
    f |= DSP_FEATURE_DVC;
    f |= DSP_FEATURE_TRUE_PEAK;
    f |= DSP_FEATURE_STEREO_LINK;
    f |= DSP_FEATURE_TWO_BAND;
    f |= DSP_FEATURE_DC_BLOCK;
    f |= DSP_FEATURE_PARAM_RAMP;
    f |= DSP_FEATURE_CREST_RELEASE;
    f |= DSP_FEATURE_SPEAKER_VB;
    f |= DSP_FEATURE_PREAMP;
#if DSP_NEON
    f |= DSP_FEATURE_NEON;
#endif
    out->features = f;
    if (handle) {
        auto* e = static_cast<Engine*>(handle);
        out->sample_rate = e->sample_rate;
        out->channels = e->channels;
    }
    return 0;
}

void dsp_set_limiter_ceiling(void* handle, float ceiling_db_high, float ceiling_db_low) {
    if (!handle) return;
    auto clamp_db = [](float v) {
        if (v < -6.0f) v = -6.0f;
        if (v > -0.1f) v = -0.1f;
        return v;
    };
    ControlCommand cmd;
    cmd.type = ControlType::LimiterCeiling;
    cmd.float0 = clamp_db(ceiling_db_high);
    cmd.float1 = clamp_db(ceiling_db_low);
    static_cast<Engine*>(handle)->control_queue.push(cmd);
}

void dsp_set_crossover_hz(void* handle, float freq_hz) {
    if (!handle) return;
    if (freq_hz < 80.0f) freq_hz = 80.0f;
    if (freq_hz > 200.0f) freq_hz = 200.0f;
    ControlCommand cmd;
    cmd.type = ControlType::CrossoverHz;
    cmd.float0 = freq_hz;
    static_cast<Engine*>(handle)->control_queue.push(cmd);
}

void dsp_eq_set_enabled(void* handle, bool enabled) {
    if (!handle) return;
    ControlCommand cmd;
    cmd.type = ControlType::EqEnabled;
    cmd.enabled = enabled;
    static_cast<Engine*>(handle)->control_queue.push(cmd);
}

void dsp_eq_set_bands(void* handle, const double* centers_hz,
                      const double* gains_db, int32_t count) {
    if (!handle || !gains_db || count <= 0) return;
    if (count > kMaxBands) count = kMaxBands;
    ControlCommand cmd;
    cmd.type = ControlType::EqBands;
    cmd.count = count;
    for (int i = 0; i < count; ++i) {
        double g = gains_db[i];
        if (g > 24.0) g = 24.0;
        if (g < -24.0) g = -24.0;
        cmd.gains[i] = g;
        if (centers_hz) cmd.centers[i] = centers_hz[i];
        else cmd.centers[i] = 20.0 * std::pow(1000.0, i / (double)std::max(count - 1, 1));
    }
    static_cast<Engine*>(handle)->control_queue.push(cmd);
}

void dsp_eq_set_band(void* handle, int32_t index, double freq_hz,
                     double gain_db, double q) {
    if (!handle || index < 0 || index >= kMaxBands) return;
    if (gain_db > 24.0) gain_db = 24.0;
    if (gain_db < -24.0) gain_db = -24.0;
    if (q <= 0.0) q = 1.0;
    ControlCommand cmd;
    cmd.type = ControlType::EqBand;
    cmd.index = index;
    cmd.value0 = freq_hz;
    cmd.value1 = gain_db;
    cmd.value2 = q;
    static_cast<Engine*>(handle)->control_queue.push(cmd);
}

void dsp_set_speaker_mode(void* handle, bool enabled) {
    if (!handle) return;
    ControlCommand cmd;
    cmd.type = ControlType::SpeakerMode;
    cmd.enabled = enabled;
    static_cast<Engine*>(handle)->control_queue.push(cmd);
}

void dsp_set_virtual_bass(void* handle, double amount) {
    if (!handle) return;
    if (amount < 0.0) amount = 0.0;
    if (amount > 1.0) amount = 1.0;
    ControlCommand cmd;
    cmd.type = ControlType::VirtualBass;
    cmd.value0 = amount;
    static_cast<Engine*>(handle)->control_queue.push(cmd);
}

void dsp_process(void* handle, const float* in, float* out, int32_t frames) {
    if (!handle || !in || !out || frames <= 0) return;
    auto* e = static_cast<Engine*>(handle);
    if (frames > kMaxFrames) frames = kMaxFrames;

    struct timespec t0{}, t1{};
    clock_gettime(CLOCK_MONOTONIC, &t0);

    // Apply all pending controls at the buffer boundary. The audio thread
    // owns filter coefficients and state; setters never touch them directly.
    e->applyControlCommands();

    const int ch = e->channels;
    const bool eq = e->eq_enabled;
    const bool speaker = e->speaker_mode;
    const float knee = speaker ? 0.86f : 0.93f;

    for (int i = 0; i < frames; ++i) {
        const float vol = e->sm_vol.next();
        const float hr = e->sm_hr.next();
        const float vb = e->sm_vb.next();
        const float pre = e->sm_pre.next();

        float delayed_lo[kMaxCh] = {};
        float delayed_hi[kMaxCh] = {};
        float peaks_lo[kMaxCh] = {};
        float peaks_hi[kMaxCh] = {};

        for (int c = 0; c < ch; ++c) {
            float s = e->dc[c].process(in[i * ch + c]);

            if (eq) {
                for (int b = 0; b < e->band_count; ++b)
                    s = e->bands[b][c].process(s);
            }

            if (speaker) {
                const float deep = e->bass_lp[c].process(s);
                s = e->hpf[c].process(s);
                if (vb > 0.01f) {
                    float h = deep;
                    h = h - 0.18f * h * h * h;
                    h = e->bass_bp[c].process(h);
                    s += h * (0.42f * vb);
                }
            }

            s = sanitize(s * hr * pre * vol);

            float lo, hi;
            e->xover[c].process(s, &lo, &hi);
            delayed_lo[c] = e->det_low[c].feed(lo, &peaks_lo[c]);
            delayed_hi[c] = e->det_high[c].feed(hi, &peaks_hi[c]);
        }

        float link_lo = peaks_lo[0];
        float link_hi = peaks_hi[0];
        for (int c = 1; c < ch; ++c) {
            if (peaks_lo[c] > link_lo) link_lo = peaks_lo[c];
            if (peaks_hi[c] > link_hi) link_hi = peaks_hi[c];
        }
        const float gr_lo = e->lim_low.update(link_lo);
        const float gr_hi = e->lim_high.update(link_hi);

        if (ch == 2) {
#if DSP_NEON
            const float sum0 = delayed_lo[0] * gr_lo + delayed_hi[0] * gr_hi;
            const float sum1 = delayed_lo[1] * gr_lo + delayed_hi[1] * gr_hi;
            float o0, o1;
            soft_clip_stereo(sum0, sum1, knee, &o0, &o1);
            out[i * 2] = o0;
            out[i * 2 + 1] = o1;
#else
            for (int c = 0; c < 2; ++c) {
                float s = sanitize(delayed_lo[c] * gr_lo + delayed_hi[c] * gr_hi);
                s = soft_clip(s, knee);
                if (s > 1.0f) s = 1.0f;
                if (s < -1.0f) s = -1.0f;
                out[i * 2 + c] = s;
            }
#endif
        } else {
            for (int c = 0; c < ch; ++c) {
                float s = sanitize(delayed_lo[c] * gr_lo + delayed_hi[c] * gr_hi);
                s = soft_clip(s, knee);
                if (s > 1.0f) s = 1.0f;
                if (s < -1.0f) s = -1.0f;
                out[i * ch + c] = s;
            }
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    const int64_t ns = (int64_t)(t1.tv_sec - t0.tv_sec) * 1000000000LL
                     + (int64_t)(t1.tv_nsec - t0.tv_nsec);
    e->process_calls.fetch_add(1, std::memory_order_relaxed);
    e->total_ns.fetch_add(ns, std::memory_order_relaxed);
    int64_t observed_max = e->max_ns.load(std::memory_order_relaxed);
    while (ns > observed_max &&
           !e->max_ns.compare_exchange_weak(observed_max, ns,
                                            std::memory_order_relaxed,
                                            std::memory_order_relaxed)) {}
    e->last_frames.store(frames, std::memory_order_relaxed);
    if (e->sample_rate > 0 && frames > 0) {
        const int64_t budget_ns =
            (int64_t)frames * 1000000000LL / (int64_t)e->sample_rate;
        if (ns > budget_ns) e->overrun_count.fetch_add(1, std::memory_order_relaxed);
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
    out->process_calls = e->process_calls.load(std::memory_order_relaxed);
    out->total_ns = e->total_ns.load(std::memory_order_relaxed);
    out->max_ns = e->max_ns.load(std::memory_order_relaxed);
    out->overrun_count = e->overrun_count.load(std::memory_order_relaxed);
    out->last_frames = e->last_frames.load(std::memory_order_relaxed);
    out->sample_rate = e->sample_rate;
    out->channels = e->channels;
}

void dsp_reset_stats(void* handle) {
    if (!handle) return;
    auto* e = static_cast<Engine*>(handle);
    e->process_calls.store(0, std::memory_order_relaxed);
    e->total_ns.store(0, std::memory_order_relaxed);
    e->max_ns.store(0, std::memory_order_relaxed);
    e->overrun_count.store(0, std::memory_order_relaxed);
    e->last_frames.store(0, std::memory_order_relaxed);
}

} // extern "C"
