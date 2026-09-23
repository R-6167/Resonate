#!/usr/bin/env python3
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
P = ROOT / "lib/services/dj_bpm_estimator.dart"
FRAG = Path(__file__).with_name("frag_dj_tkey_method.txt")

def main() -> int:
    t = P.read_text()
    if "DjKeyEstimate" in t and "_parseId3Tkey" in t:
        print("estimator step4 already"); return 0
    if "import 'dj_harmonic.dart';" not in t:
        t = t.replace(
            "import 'package:flutter/foundation.dart';",
            "import 'package:flutter/foundation.dart';\n\nimport 'dj_harmonic.dart';",
            1,
        )
    old = """class DjBpmEstimate {
  final double bpm;
  final double confidence;
  final int beatOffsetMs;
  final String source;

  const DjBpmEstimate({
    required this.bpm,
    required this.confidence,
    this.beatOffsetMs = 0,
    this.source = 'unknown',
  });
}"""
    new = """class DjBpmEstimate {
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
}

class DjKeyEstimate {
  final int keyRoot;
  final String keyMode;
  final double confidence;
  final String source;

  const DjKeyEstimate({
    required this.keyRoot,
    required this.keyMode,
    required this.confidence,
    this.source = 'id3_tkey',
  });
}"""
    if old not in t:
        print("estimate class missing"); return 2
    t = t.replace(old, new, 1)
    oldp = """        final fromId3 = _parseId3Tbpm(bytes);
        if (fromId3 != null) return fromId3;"""
    newp = """        final fromId3 = _parseId3Tbpm(bytes);
        final key = _parseId3Tkey(bytes);
        if (fromId3 != null) {
          if (key == null) return fromId3;
          return DjBpmEstimate(
            bpm: fromId3.bpm,
            confidence: fromId3.confidence,
            beatOffsetMs: fromId3.beatOffsetMs,
            source: fromId3.source,
            keyRoot: key.keyRoot,
            keyMode: key.keyMode,
            keyConfidence: key.confidence,
          );
        }
        if (key != null) {
          return DjBpmEstimate(
            bpm: 0,
            confidence: 0.0,
            source: 'id3_tkey_only',
            keyRoot: key.keyRoot,
            keyMode: key.keyMode,
            keyConfidence: key.confidence,
          );
        }"""
    if oldp not in t:
        print("parse site missing"); return 3
    t = t.replace(oldp, newp, 1)
    method = FRAG.read_text()
    if "_parseId3Tkey" not in t:
        t = t.replace("  int _synchsafe(Uint8List b, int i) {", method + "  int _synchsafe(Uint8List b, int i) {", 1)
    P.write_text(t)
    print("estimator applied", P.stat().st_size)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
