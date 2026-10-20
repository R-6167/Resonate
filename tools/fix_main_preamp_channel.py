#!/usr/bin/env python3
from pathlib import Path
import os
ROOT = Path(__file__).resolve().parents[1]
for root, _, files in os.walk(ROOT / 'android'):
    for f in files:
        if f != 'MainActivity.kt': continue
        p = Path(root)/f
        t = p.read_text()
        if 'applyPreampAll' in t and 'setLiveDspLimiterCeiling' in t:
            print('already');
            raise SystemExit(0)
        old = 'com.aetherion.resonate.dsp.DspEngineRegistry.applyVolumeAll(linear)'
        # only the preamp call site: look for setLiveDspPreampDb block
        idx = t.find('"setLiveDspPreampDb"')
        if idx < 0:
            print('no preamp channel'); raise SystemExit(1)
        chunk = t[idx:idx+500]
        if 'applyVolumeAll' in chunk:
            # replace first applyVolumeAll after setLiveDspPreampDb only
            pre = t[:idx]
            rest = t[idx:]
            rest = rest.replace(
                'com.aetherion.resonate.dsp.DspEngineRegistry.applyVolumeAll(linear)',
                'com.aetherion.resonate.dsp.DspEngineRegistry.applyPreampAll(linear)',
                1,
            )
            # insert limiter/crossover channels after preamp block if missing
            if 'setLiveDspLimiterCeiling' not in rest:
                marker = '"setLiveDspEqBands"'
                insert = '''"setLiveDspLimiterCeiling" -> {
                        val high = (call.argument<Number>("highDb") ?: -0.5).toFloat()
                        val low = (call.argument<Number>("lowDb") ?: -0.2).toFloat()
                        com.aetherion.resonate.dsp.DspEngineRegistry.applyLimiterCeilingAll(high, low)
                        result.success(mapOf("ok" to true, "highDb" to high, "lowDb" to low))
                    }
                    "setLiveDspCrossoverHz" -> {
                        val hz = (call.argument<Number>("hz") ?: 120.0).toFloat()
                        com.aetherion.resonate.dsp.DspEngineRegistry.applyCrossoverHzAll(hz)
                        result.success(mapOf("ok" to true, "hz" to hz))
                    }
                    '''
                rest = rest.replace(marker, insert + marker, 1)
            p.write_text(pre + rest)
            print('MainActivity fixed', p)
        else:
            print('preamp already uses non-volume', chunk[:200])
