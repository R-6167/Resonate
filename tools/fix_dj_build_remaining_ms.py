#!/usr/bin/env python3
from pathlib import Path

MP = Path("lib/providers/music_provider.dart")
m = MP.read_text()
changed = False

old = "remainingMs = (rem - 150).clamp(1200, plannedMs);"
new = "remainingMs = (rem - 150).clamp(1200, plannedMs).toInt();"
if old in m:
    m = m.replace(old, new)
    changed = True
    print("remainingMs toInt")
elif new in m:
    print("remainingMs already fixed")
else:
    print("WARN remainingMs pattern miss")

# Early abort after SFX engage should restore
old_abort = """            try { await incoming.stop(); } catch (_) {}
            try { await outgoing.setVolume(base); } catch (_) {}
            await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
            return false;"""
# Only ensure restore is present on paths that already have clearDjStretch after engage
if "await _restoreDjTransitionSfx();" in m:
    # Add restore before return false in too_late abort if missing there
    too_late = """            await ResonateDiagnostics.record('crossfade_aborted_too_late', {
              'remainingMs': rem,
              'plannedMs': plannedMs,
            });
            try { await incoming.stop(); } catch (_) {}
            try { await outgoing.setVolume(base); } catch (_) {}
            await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
            return false;"""
    too_late_fix = """            await ResonateDiagnostics.record('crossfade_aborted_too_late', {
              'remainingMs': rem,
              'plannedMs': plannedMs,
            });
            try { await incoming.stop(); } catch (_) {}
            try { await outgoing.setVolume(base); } catch (_) {}
            await _clearDjStretchSpeeds(outgoing: outgoing, incoming: incoming);
            await _restoreDjTransitionSfx();
            return false;"""
    if too_late in m and "crossfade_aborted_too_late" in m:
        if "_restoreDjTransitionSfx();\n            return false;" not in m[m.find("crossfade_aborted_too_late"):m.find("crossfade_aborted_too_late")+500]:
            m = m.replace(too_late, too_late_fix, 1)
            changed = True
            print("too_late restore")
        else:
            print("too_late restore already")

PCM = Path("lib/services/dj_pcm_bpm.dart")
pcm = PCM.read_text()
# period should be int for math.min clarity
old_p = "final period = bestLag.clamp(1, env.length - 1);"
new_p = "final period = bestLag.clamp(1, env.length - 1).toInt();"
if old_p in pcm:
    pcm = pcm.replace(old_p, new_p, 1)
    PCM.write_text(pcm)
    changed = True
    print("period toInt")
elif new_p in pcm:
    print("period already")

# conf as double
if "var conf = sourceConfidence.clamp" in pcm:
    pcm2 = PCM.read_text()
    pcm2 = pcm2.replace(
        "var conf = sourceConfidence.clamp(0.35, 0.72);",
        "var conf = sourceConfidence.clamp(0.35, 0.72).toDouble();",
        1,
    )
    pcm2 = pcm2.replace(
        "conf = (conf + 0.04).clamp(0.35, 0.78);",
        "conf = (conf + 0.04).clamp(0.35, 0.78).toDouble();",
        1,
    )
    PCM.write_text(pcm2)
    print("conf toDouble")

PLAN = Path("lib/services/dj_transition_planner.dart")
pl = PLAN.read_text()
old_th = "      : (durationMs * 0.14).round().clamp(16000, 28000);"
new_th = "      : (durationMs * 0.14).round().clamp(16000, 28000).toInt();"
if old_th in pl:
    pl = pl.replace(old_th, new_th, 1)
    PLAN.write_text(pl)
    changed = True
    print("thresh toInt")

if changed:
    MP.write_text(m)
print("done")
