/**
 * Offline bass stress harness — not on the audio thread.
 */
#include "dsp_engine.h"

#include <cmath>
#include <cstdlib>
#include <cstring>

extern "C" int dsp_run_bass_stress(DspStressResult* out) {
    if (out) {
        out->cases_run = 0;
        out->cases_passed = 0;
        out->max_abs_peak = 0.f;
        out->peak_failures = 0;
        out->nan_failures = 0;
        out->speaker_cases_ok = 0;
    }

    const int sr = 48000;
    const int ch = 2;
    const int frames = 2048;

    DspConfig cfg{};
    cfg.sample_rate = sr;
    cfg.channels = ch;
    cfg.buffer_frames = frames;
    cfg.exclusive_mode = false;
    cfg.bit_perfect = true;
    cfg.realtime_priority = 0;

    void* h = dsp_create(&cfg);
    if (!h) return -1;
    dsp_start(h);

    static const double kHz[10] = {
        31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000};

    struct Case {
        const char* name;
        double gains[10];
        double volume;
        bool speaker;
        double vb;
        double tone_hz;
        double amp;
    };

    static const Case kCases[] = {
        {"Flat unity", {0,0,0,0,0,0,0,0,0,0}, 1.0, false, 0.0, 1000.0, 0.9},
        {"Bass Boost 40Hz", {8,7,5,3,1,0,0,0,0,0}, 1.0, false, 0.0, 40.0, 0.95},
        {"Deep Bass 40Hz", {9,8,6,3,0,-1,-1,0,0,0}, 1.0, false, 0.0, 40.0, 0.95},
        {"Sub Focus 30Hz", {10,9,5,1,-1,-2,-1,0,0,0}, 1.0, false, 0.0, 30.0, 0.95},
        {"Bass Extreme 40Hz", {11,10,7,2,0,-2,-1,0,1,1}, 1.0, false, 0.0, 40.0, 0.95},
        {"Bass Extreme +2.0 vol", {11,10,7,2,0,-2,-1,0,1,1}, 2.0, false, 0.0, 40.0, 0.9},
        {"Bass Extreme speaker", {11,10,7,2,0,-2,-1,0,1,1}, 1.0, true, 0.7, 40.0, 0.95},
        {"Deep Bass speaker VB", {9,8,6,3,0,-1,-1,0,0,0}, 1.2, true, 1.0, 50.0, 0.95},
        {"Sub Focus speaker", {10,9,5,1,-1,-2,-1,0,0,0}, 1.0, true, 0.55, 35.0, 0.95},
        {"All +12 bass + vol", {12,12,12,8,4,0,0,0,0,0}, 1.5, false, 0.0, 45.0, 0.9},
        {"Bass Extreme 60Hz", {11,10,7,2,0,-2,-1,0,1,1}, 1.0, false, 0.0, 60.0, 0.95},
        {"Impulse click", {11,10,7,2,0,-2,-1,0,1,1}, 1.0, false, 0.0, 0.0, 1.0},
    };
    const int nCases = (int)(sizeof(kCases) / sizeof(kCases[0]));

    float* inbuf = (float*)std::malloc(sizeof(float) * (size_t)frames * (size_t)ch);
    float* outbuf = (float*)std::malloc(sizeof(float) * (size_t)frames * (size_t)ch);
    if (!inbuf || !outbuf) {
        std::free(inbuf);
        std::free(outbuf);
        dsp_destroy(h);
        return -1;
    }

    int run = 0, passed = 0, peak_fail = 0, nan_fail = 0, speaker_ok = 0;
    float max_peak = 0.f;

    for (int ci = 0; ci < nCases; ++ci) {
        const Case& cs = kCases[ci];
        dsp_eq_set_bands(h, kHz, cs.gains, 10);
        dsp_eq_set_enabled(h, true);
        dsp_set_volume(h, cs.volume);
        dsp_set_speaker_mode(h, cs.speaker);
        dsp_set_virtual_bass(h, cs.vb);

        if (cs.tone_hz <= 0.0) {
            for (int i = 0; i < frames * ch; ++i) inbuf[i] = 0.f;
            inbuf[64 * ch] = (float)cs.amp;
            inbuf[64 * ch + 1] = (float)cs.amp;
        } else {
            const double w = 2.0 * M_PI * cs.tone_hz / (double)sr;
            for (int i = 0; i < frames; ++i) {
                const float s = (float)(cs.amp * std::sin(w * (double)i));
                inbuf[i * ch] = s;
                inbuf[i * ch + 1] = s;
            }
        }

        dsp_process(h, inbuf, outbuf, frames);
        dsp_process(h, inbuf, outbuf, frames);

        bool ok = true;
        float local_peak = 0.f;
        for (int i = 0; i < frames * ch; ++i) {
            const float s = outbuf[i];
            if (!std::isfinite(s)) {
                ok = false;
                nan_fail++;
                break;
            }
            const float a = std::fabs(s);
            if (a > local_peak) local_peak = a;
        }
        if (local_peak > max_peak) max_peak = local_peak;
        if (local_peak > 1.001f) {
            ok = false;
            peak_fail++;
        }

        run++;
        if (ok) {
            passed++;
            if (cs.speaker) speaker_ok++;
        }
    }

    std::free(inbuf);
    std::free(outbuf);
    dsp_destroy(h);

    if (out) {
        out->cases_run = run;
        out->cases_passed = passed;
        out->max_abs_peak = max_peak;
        out->peak_failures = peak_fail;
        out->nan_failures = nan_fail;
        out->speaker_cases_ok = speaker_ok;
    }
    return (passed == run && run > 0) ? 0 : 1;
}
