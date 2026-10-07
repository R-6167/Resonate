#include "dsp_engine.h"
#include <cstdio>

int main() {
    DspInfo info{};
    dsp_get_info(nullptr, &info);
    std::printf("DSP ENGINE v%d.%d.%d features=0x%08x maxBands=%d maxFrames=%d\n",
                info.version_major, info.version_minor, info.version_patch,
                info.features, info.max_bands, info.max_frames);

    DspStressResult r{};
    const int rc = dsp_run_bass_stress(&r);
    std::printf(
        "bass stress: rc=%d run=%d pass=%d maxPeak=%.4f peakFail=%d nan=%d speakerOk=%d\n",
        rc, r.cases_run, r.cases_passed, r.max_abs_peak,
        r.peak_failures, r.nan_failures, r.speaker_cases_ok);
    std::printf(
        "latency: avg=%lld ns max=%lld ns budget=%lld ns (%.2f%% of budget) overruns=%d\n",
        (long long)r.avg_ns_per_call, (long long)r.max_ns_per_call,
        (long long)r.budget_ns, r.cpu_pct_of_budget, r.overrun_calls);
    return rc == 0 ? 0 : 1;
}
