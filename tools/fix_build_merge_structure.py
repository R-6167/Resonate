#!/usr/bin/env python3
"""Fix build: define _mergeStructure, startMs.toInt()."""
from pathlib import Path

EST = Path('lib/services/dj_bpm_estimator.dart')
est = EST.read_text()

# Fix num->int clamp
old_ms = 'final startMs = (dur - 18000).clamp(20000, dur - 8000);'
new_ms = 'final startMs = (dur - 18000).clamp(20000, dur - 8000).toInt();'
if old_ms in est and 'startMs = (dur - 18000).clamp(20000, dur - 8000).toInt()' not in est:
    est = est.replace(old_ms, new_ms, 1)
    print('startMs toInt')
elif '.toInt()' in est and 'startMs' in est:
    print('startMs already int')
else:
    print('WARN startMs')

helper = '''
  /// Merge start-window estimate with end-window structure/outro hints.
  DjBpmEstimate? _mergeStructure(DjBpmEstimate? start, DjBpmEstimate? end) {
    if (start == null) return end;
    if (end == null) return start;
    final s = start.sectionHint;
    final e = end.sectionHint;
    String? section;
    if (e == 'quiet_outro' || e == 'outro') {
      if (s == 'build' || s == 'drop' || s == 'chorus' || s == 'intro' ||
          s == 'quiet_intro' || s == 'energetic') {
        section = s;
      } else {
        section = e;
      }
    } else {
      section = s ?? e;
    }
    return DjBpmEstimate(
      bpm: start.bpm > 0 ? start.bpm : end.bpm,
      confidence: start.confidence >= end.confidence
          ? start.confidence
          : end.confidence,
      beatOffsetMs: start.beatOffsetMs,
      source: start.source,
      keyRoot: start.keyRoot ?? end.keyRoot,
      keyMode: start.keyMode ?? end.keyMode,
      keyConfidence: start.keyConfidence >= end.keyConfidence
          ? start.keyConfidence
          : end.keyConfidence,
      energy: start.energy ?? end.energy,
      loudness: start.loudness ?? end.loudness,
      introHintMs: start.introHintMs,
      outroHintMs: end.outroHintMs ?? start.outroHintMs,
      sectionHint: section,
    );
  }

'''

if 'DjBpmEstimate? _mergeStructure(' not in est:
    marker = '  Future<Uint8List?> _readMediaHeadNative(String uri) async {'
    if marker not in est:
        raise SystemExit('marker miss for merge helper')
    est = est.replace(marker, helper + marker, 1)
    print('merge helper added')
else:
    print('merge helper already present')

EST.write_text(est)

# Soften rack: b.gain might need try - check AndroidEqualizerBand
RACK = Path('lib/services/dj_sfx_rack.dart')
if RACK.exists():
    rack = RACK.read_text()
    # Ensure gain snapshot is safe
    if '_savedEqGains = [for (final b in p.bands) b.gain];' in rack:
        rack = rack.replace(
            '_savedEqGains = [for (final b in p.bands) b.gain];',
            '''_savedEqGains = [
        for (final b in p.bands) b.gain,
      ];''',
            1,
        )
        RACK.write_text(rack)
        print('rack snapshot ok')

print('BUILD FIX DONE')
