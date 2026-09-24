#!/usr/bin/env python3
from pathlib import Path

EST = Path("lib/services/dj_bpm_estimator.dart")
t = EST.read_text()

if "final double? energy;" in t:
    print("estimator already has energy")
else:
    old_class = """class DjBpmEstimate {
  final double bpm;
  final double confidence;
  final int beatOffsetMs;
  final String source;
  final int? keyRoot;
  final String? keyMode;
  final double keyConfidence;

  const DjBpmEstimate({
    required this.bpm,
    required this.confidence,
    this.beatOffsetMs = 0,
    this.source = 'unknown',
    this.keyRoot,
    this.keyMode,
    this.keyConfidence = 0.0,
  });
}"""
    new_class = """class DjBpmEstimate {
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
}"""
    if old_class not in t:
        raise SystemExit("class miss")
    t = t.replace(old_class, new_class, 1)

# native merge with key
old1 = """          return DjBpmEstimate(
            bpm: nativePcm.bpm,
            confidence: nativePcm.confidence,
            beatOffsetMs: nativePcm.beatOffsetMs,
            source: nativePcm.source,
            keyRoot: key.keyRoot,
            keyMode: key.keyMode,
            keyConfidence: key.confidence,
          );"""
new1 = """          return DjBpmEstimate(
            bpm: nativePcm.bpm,
            confidence: nativePcm.confidence,
            beatOffsetMs: nativePcm.beatOffsetMs,
            source: nativePcm.source,
            keyRoot: key.keyRoot,
            keyMode: key.keyMode,
            keyConfidence: key.confidence,
            energy: nativePcm.energy,
            loudness: nativePcm.loudness,
          );"""
if old1 in t:
    t = t.replace(old1, new1, 1)
    print("native+key energy")
elif "energy: nativePcm.energy" in t:
    print("native+key already")
else:
    print("WARN native+key")

old2 = """          return DjBpmEstimate(
            bpm: pcm.bpm,
            confidence: pcm.confidence,
            beatOffsetMs: pcm.beatOffsetMs,
            source: 'pcm_wav',
            keyRoot: key?.keyRoot,
            keyMode: key?.keyMode,
            keyConfidence: key?.confidence ?? 0.0,
          );"""
new2 = """          return DjBpmEstimate(
            bpm: pcm.bpm,
            confidence: pcm.confidence,
            beatOffsetMs: pcm.beatOffsetMs,
            source: 'pcm_wav',
            keyRoot: key?.keyRoot,
            keyMode: key?.keyMode,
            keyConfidence: key?.confidence ?? 0.0,
            energy: pcm.energy,
            loudness: pcm.loudness,
          );"""
if old2 in t:
    t = t.replace(old2, new2, 1)
    print("wav energy")
elif "source: 'pcm_wav'" in t and "energy: pcm.energy" in t:
    print("wav already")
else:
    print("WARN wav")

old3 = """      return DjBpmEstimate(
        bpm: est.bpm,
        confidence: est.confidence,
        beatOffsetMs: est.beatOffsetMs,
        source: 'pcm_native',
      );"""
new3 = """      return DjBpmEstimate(
        bpm: est.bpm,
        confidence: est.confidence,
        beatOffsetMs: est.beatOffsetMs,
        source: 'pcm_native',
        energy: est.energy,
        loudness: est.loudness,
      );"""
if old3 in t:
    t = t.replace(old3, new3, 1)
    print("native energy")
elif "source: 'pcm_native'" in t and "energy: est.energy" in t:
    print("native already")
else:
    print("WARN native")

EST.write_text(t)
print("estimator written")
