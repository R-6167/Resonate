#include "dsp_engine.h"
#include <cstdio>

int main() {
    DspStressResult r{};
    const int rc = dsp_run_bass_stress(&r);
    std::printf(
        "bass stress: rc=%d run=%d pass=%d maxPeak=%.4f peakFail=%d nan=%d speakerOk=%d\n",
        rc, r.cases_run, r.cases_passed, r.max_abs_peak,
        r.peak_failures, r.nan_failures, r.speaker_cases_ok);
    return rc == 0 ? 0 : 1;
}
