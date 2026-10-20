#!/usr/bin/env python3
from pathlib import Path

pl = Path('lib/services/dj_transition_planner.dart')
t = pl.read_text()
old = "crossfadeBiasMs: (plan.crossfadeBiasMs + 800).clamp(-1500, 2500),"
new = "crossfadeBiasMs: (plan.crossfadeBiasMs + 800).clamp(-1500, 2500).toInt(),"
if old in t:
    pl.write_text(t.replace(old, new, 1))
    print('planner fixed')
elif new in t:
    print('planner already')
else:
    print('WARN planner')

pcm = Path('lib/services/dj_pcm_bpm.dart')
t = pcm.read_text()
old = "final beatOffsetMs = (peakIdx * 10).clamp(0, (60000.0 / bpm).round() - 1);"
new = "final beatOffsetMs = (peakIdx * 10).clamp(0, (60000.0 / bpm).round() - 1).toInt();"
if old in t:
    pcm.write_text(t.replace(old, new, 1))
    print('pcm fixed')
elif new in t:
    print('pcm already')
else:
    print('WARN pcm')
