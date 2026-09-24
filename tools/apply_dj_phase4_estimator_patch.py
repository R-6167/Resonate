#!/usr/bin/env python3
from pathlib import Path
import re

EST = Path("lib/services/dj_bpm_estimator.dart")
t = EST.read_text()

# Always ensure class has energy/loudness fields
new_class = '''class DjBpmEstimate {
  final double bpm;
  final double confidence;
  final int beatOffsetMs;
  final String source;
  final int? keyRoot;
  final String? keyMode;
  final double keyConfidence;
  /// Relative energy 0–1 from PCM window (null when ID3-only / unknown).
  final double? energy;
  /// Approximate loudness 0–1 from PCM window.
  final double? loudness;

  const DjBpmEstimate({
    required this.bpm,
    required this.confidence,
    this.beatOffsetMs = 0,
    this.source = 'unknown',
    this.keyRoot,
    this.keyMode,
    this.keyConfidence = 0.0,
    this.energy,
    this.loudness,
  });
}'''

m = re.search(r'class DjBpmEstimate \{.*?\n\}\n', t, re.S)
if not m:
    raise SystemExit('class regex miss')
t = t[:m.start()] + new_class + '\n' + t[m.end():]
print('rewrote DjBpmEstimate class')

def ensure_energy(block_old, block_new, label):
    global t
    if 'energy:' in block_old and block_old in t:
        # shouldn't happen
        pass
    if block_old in t:
        t = t.replace(block_old, block_new, 1)
        print(label, 'patched')
        return
    if label in t or (label == 'native' and "energy: est.energy" in t):
        print(label, 'already')
        return
    print('WARN', label)

ensure_energy(
'''          return DjBpmEstimate(
            bpm: nativePcm.bpm,
            confidence: nativePcm.confidence,
            beatOffsetMs: nativePcm.beatOffsetMs,
            source: nativePcm.source,
            keyRoot: key.keyRoot,
            keyMode: key.keyMode,
            keyConfidence: key.confidence,
          );''',
'''          return DjBpmEstimate(
            bpm: nativePcm.bpm,
            confidence: nativePcm.confidence,
            beatOffsetMs: nativePcm.beatOffsetMs,
            source: nativePcm.source,
            keyRoot: key.keyRoot,
            keyMode: key.keyMode,
            keyConfidence: key.confidence,
            energy: nativePcm.energy,
            loudness: nativePcm.loudness,
          );''',
'native+key')

ensure_energy(
'''          return DjBpmEstimate(
            bpm: pcm.bpm,
            confidence: pcm.confidence,
            beatOffsetMs: pcm.beatOffsetMs,
            source: 'pcm_wav',
            keyRoot: key?.keyRoot,
            keyMode: key?.keyMode,
            keyConfidence: key?.confidence ?? 0.0,
          );''',
'''          return DjBpmEstimate(
            bpm: pcm.bpm,
            confidence: pcm.confidence,
            beatOffsetMs: pcm.beatOffsetMs,
            source: 'pcm_wav',
            keyRoot: key?.keyRoot,
            keyMode: key?.keyMode,
            keyConfidence: key?.confidence ?? 0.0,
            energy: pcm.energy,
            loudness: pcm.loudness,
          );''',
'wav')

ensure_energy(
'''      return DjBpmEstimate(
        bpm: est.bpm,
        confidence: est.confidence,
        beatOffsetMs: est.beatOffsetMs,
        source: 'pcm_native',
      );''',
'''      return DjBpmEstimate(
        bpm: est.bpm,
        confidence: est.confidence,
        beatOffsetMs: est.beatOffsetMs,
        source: 'pcm_native',
        energy: est.energy,
        loudness: est.loudness,
      );''',
'native')

EST.write_text(t)
if 'final double? energy;' not in EST.read_text():
    raise SystemExit('VERIFY FAIL no energy field')
print('ok')
