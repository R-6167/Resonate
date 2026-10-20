#!/usr/bin/env python3
"""Wire existing dj_pcm_features into estimator/model/DB/planner/SFX."""
from pathlib import Path

EST = Path("lib/services/dj_bpm_estimator.dart")
est = EST.read_text()
if "dj_pcm_features.dart" not in est:
    est = est.replace(
        "import 'dj_pcm_bpm.dart';",
        "import 'dj_pcm_bpm.dart';\nimport 'dj_pcm_features.dart';",
        1,
    )
    print("import features")

if "introHintMs" not in est:
    est = est.replace(
        "  final double? loudness;\n\n  const DjBpmEstimate({",
        "  final double? loudness;\n  final int? introHintMs;\n  final int? outroHintMs;\n  final String? sectionHint;\n\n  const DjBpmEstimate({",
        1,
    )
    est = est.replace(
        "    this.loudness,\n  });",
        "    this.loudness,\n    this.introHintMs,\n    this.outroHintMs,\n    this.sectionHint,\n  });",
        1,
    )
    print("estimate fields")

old_native = """  Future<DjBpmEstimate?> _estimateFromNativePcm(String uri) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('extractPcmWindow', {
        'uri': uri,
        'maxSeconds': 15.0,
      });
      if (raw is! Map) return null;
      final sampleRate = (raw['sampleRate'] as num?)?.toInt();
      final channels = (raw['channels'] as num?)?.toInt() ?? 2;
      final pcmRaw = raw['pcm'];
      if (sampleRate == null || sampleRate < 8000) return null;
      Uint8List? pcm;
      if (pcmRaw is Uint8List) {
        pcm = pcmRaw;
      } else if (pcmRaw is List<int>) {
        pcm = Uint8List.fromList(pcmRaw);
      }
      if (pcm == null || pcm.length < sampleRate) return null;
      final est = DjPcmBpmAnalyzer().estimateFromPcm16(
        pcm,
        sampleRate,
        channels,
        sourceConfidence: 0.48,
      );
      if (est == null) return null;
      return DjBpmEstimate(
        bpm: est.bpm,
        confidence: est.confidence,
        beatOffsetMs: est.beatOffsetMs,
        source: 'pcm_native',
        energy: est.energy,
        loudness: est.loudness,
      );
    } catch (e) {
      debugPrint('DjBpmEstimator native pcm: $e');
      return null;
    }
  }"""

new_native = """  Future<DjBpmEstimate?> _estimateFromNativePcm(String uri) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('extractPcmWindow', {
        'uri': uri,
        'maxSeconds': 15.0,
      });
      if (raw is! Map) return null;
      final sampleRate = (raw['sampleRate'] as num?)?.toInt();
      final channels = (raw['channels'] as num?)?.toInt() ?? 2;
      final pcmRaw = raw['pcm'];
      if (sampleRate == null || sampleRate < 8000) return null;
      Uint8List? pcm;
      if (pcmRaw is Uint8List) {
        pcm = pcmRaw;
      } else if (pcmRaw is List<int>) {
        pcm = Uint8List.fromList(pcmRaw);
      }
      if (pcm == null || pcm.length < sampleRate) return null;
      final est = DjPcmBpmAnalyzer().estimateFromPcm16(
        pcm,
        sampleRate,
        channels,
        sourceConfidence: 0.48,
      );
      if (est == null) return null;
      final feats = DjPcmFeatureAnalyzer().analyze(
        pcm,
        sampleRate,
        channels,
        windowRole: 'start',
      );
      return DjBpmEstimate(
        bpm: est.bpm,
        confidence: est.confidence,
        beatOffsetMs: est.beatOffsetMs,
        source: 'pcm_native',
        energy: est.energy,
        loudness: est.loudness,
        keyRoot: feats.keyRoot,
        keyMode: feats.keyMode,
        keyConfidence: feats.keyConfidence,
        introHintMs: feats.introHintMs,
        outroHintMs: feats.outroHintMs,
        sectionHint: feats.sectionHint,
      );
    } catch (e) {
      debugPrint('DjBpmEstimator native pcm: $e');
      return null;
    }
  }"""

if "DjPcmFeatureAnalyzer" not in est:
    if old_native not in est:
        raise SystemExit("native pcm block miss")
    est = est.replace(old_native, new_native, 1)
    print("native features wired")
else:
    print("native features already")

if "introHintMs: nativePcm.introHintMs" not in est:
    old_merge = """        if (fromId3 != null) {
          return DjBpmEstimate(
            bpm: fromId3.bpm,
            confidence: math.max(fromId3.confidence, 0.75),
            beatOffsetMs: nativePcm.beatOffsetMs,
            source: 'id3_tbpm+pcm',
            keyRoot: key?.keyRoot,
            keyMode: key?.keyMode,
            keyConfidence: key?.confidence ?? 0.0,
            energy: nativePcm.energy,
            loudness: nativePcm.loudness,
          );
        }
        if (key != null) {
          return DjBpmEstimate(
            bpm: nativePcm.bpm,
            confidence: nativePcm.confidence,
            beatOffsetMs: nativePcm.beatOffsetMs,
            source: nativePcm.source,
            keyRoot: key.keyRoot,
            keyMode: key.keyMode,
            keyConfidence: key.confidence,
            energy: nativePcm.energy,
            loudness: nativePcm.loudness,
          );
        }
        return nativePcm;"""
    new_merge = """        if (fromId3 != null) {
          return DjBpmEstimate(
            bpm: fromId3.bpm,
            confidence: math.max(fromId3.confidence, 0.75),
            beatOffsetMs: nativePcm.beatOffsetMs,
            source: 'id3_tbpm+pcm',
            keyRoot: key?.keyRoot ?? nativePcm.keyRoot,
            keyMode: key?.keyMode ?? nativePcm.keyMode,
            keyConfidence: key != null
                ? key.confidence
                : nativePcm.keyConfidence,
            energy: nativePcm.energy,
            loudness: nativePcm.loudness,
            introHintMs: nativePcm.introHintMs,
            outroHintMs: nativePcm.outroHintMs,
            sectionHint: nativePcm.sectionHint,
          );
        }
        if (key != null) {
          return DjBpmEstimate(
            bpm: nativePcm.bpm,
            confidence: nativePcm.confidence,
            beatOffsetMs: nativePcm.beatOffsetMs,
            source: nativePcm.source,
            keyRoot: key.keyRoot,
            keyMode: key.keyMode,
            keyConfidence: key.confidence,
            energy: nativePcm.energy,
            loudness: nativePcm.loudness,
            introHintMs: nativePcm.introHintMs,
            outroHintMs: nativePcm.outroHintMs,
            sectionHint: nativePcm.sectionHint,
          );
        }
        return nativePcm;"""
    if old_merge not in est:
        print("WARN merge block miss")
    else:
        est = est.replace(old_merge, new_merge, 1)
        print("merge sections")

EST.write_text(est)
print("estimator done")

MODEL = Path("lib/models/dj_analysis.dart")
md = MODEL.read_text()
if "introHintMs" not in md:
    md = md.replace(
        "  final double? loudness;\n\n  const DjAnalysis({",
        "  final double? loudness;\n  final int? introHintMs;\n  final int? outroHintMs;\n  final String? sectionHint;\n\n  const DjAnalysis({",
        1,
    )
    md = md.replace(
        "    this.loudness,\n  });",
        "    this.loudness,\n    this.introHintMs,\n    this.outroHintMs,\n    this.sectionHint,\n  });",
        1,
    )
    md = md.replace(
        "      loudness: (map['loudness'] as num?)?.toDouble(),\n    );",
        "      loudness: (map['loudness'] as num?)?.toDouble(),\n      introHintMs: (map['intro_hint_ms'] as num?)?.toInt(),\n      outroHintMs: (map['outro_hint_ms'] as num?)?.toInt(),\n      sectionHint: map['section_hint'] as String?,\n    );",
        1,
    )
    md = md.replace(
        "      'loudness': loudness,\n    };",
        "      'loudness': loudness,\n      'intro_hint_ms': introHintMs,\n      'outro_hint_ms': outroHintMs,\n      'section_hint': sectionHint,\n    };",
        1,
    )
    md = md.replace(
        "    double? loudness,\n  }) {",
        "    double? loudness,\n    int? introHintMs,\n    int? outroHintMs,\n    String? sectionHint,\n  }) {",
        1,
    )
    md = md.replace(
        "      loudness: loudness ?? this.loudness,\n    );",
        "      loudness: loudness ?? this.loudness,\n      introHintMs: introHintMs ?? this.introHintMs,\n      outroHintMs: outroHintMs ?? this.outroHintMs,\n      sectionHint: sectionHint ?? this.sectionHint,\n    );",
        1,
    )
    md = md.replace("static const int currentVersion = 3;", "static const int currentVersion = 4;", 1)
    MODEL.write_text(md)
    print("model v4")
else:
    print("model already")

AS = Path("lib/services/dj_analysis_service.dart")
as_ = AS.read_text()
if "introHintMs: estimate.introHintMs" not in as_:
    as_ = as_.replace(
        "              energy: estimate.energy,\n              loudness: estimate.loudness,\n            );",
        "              energy: estimate.energy,\n              loudness: estimate.loudness,\n              introHintMs: estimate.introHintMs,\n              outroHintMs: estimate.outroHintMs,\n              sectionHint: estimate.sectionHint,\n            );",
        1,
    )
    AS.write_text(as_)
    print("analysis service")

DB = Path("lib/services/database_helper.dart")
db = DB.read_text()
if "columnDjIntroHintMs" not in db:
    db = db.replace("static const _databaseVersion = 6;", "static const _databaseVersion = 7;", 1)
    db = db.replace(
        "  static const String columnDjLoudness = 'loudness';",
        "  static const String columnDjLoudness = 'loudness';\n  static const String columnDjIntroHintMs = 'intro_hint_ms';\n  static const String columnDjOutroHintMs = 'outro_hint_ms';\n  static const String columnDjSectionHint = 'section_hint';",
        1,
    )
    db = db.replace(
        "$columnDjEnergy REAL, $columnDjLoudness REAL, FOREIGN KEY",
        "$columnDjEnergy REAL, $columnDjLoudness REAL, $columnDjIntroHintMs INTEGER, $columnDjOutroHintMs INTEGER, $columnDjSectionHint TEXT, FOREIGN KEY",
        1,
    )
    if "oldVersion < 7" not in db:
        db = db.replace(
            "    if (oldVersion < 6) {\n      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjEnergy REAL'); } catch (_) {}\n      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjLoudness REAL'); } catch (_) {}\n    }\n  }",
            "    if (oldVersion < 6) {\n      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjEnergy REAL'); } catch (_) {}\n      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjLoudness REAL'); } catch (_) {}\n    }\n    if (oldVersion < 7) {\n      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjIntroHintMs INTEGER'); } catch (_) {}\n      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjOutroHintMs INTEGER'); } catch (_) {}\n      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjSectionHint TEXT'); } catch (_) {}\n    }\n  }",
            1,
        )
    DB.write_text(db)
    print("db v7")

PL = Path("lib/services/dj_transition_planner.dart")
pl = PL.read_text()
if "outroHintMs" not in pl or "outroHintMs: analysisA" not in pl:
    old_fn = """bool inOutroWindow({
  required int? durationMs,
  required int positionMs,
}) {
  if (durationMs == null || durationMs < 45000) return false;
  if (positionMs < 0) return false;
  final remaining = durationMs - positionMs;
  if (remaining < 2800) return false;
  final thresh = durationMs < 120000
      ? 14000
      : (durationMs * 0.14).round().clamp(16000, 28000).toInt();
  return remaining <= thresh;
}"""
    new_fn = """bool inOutroWindow({
  required int? durationMs,
  required int positionMs,
  int? outroHintMs,
}) {
  if (durationMs == null || durationMs < 45000) return false;
  if (positionMs < 0) return false;
  final remaining = durationMs - positionMs;
  if (remaining < 2800) return false;
  var thresh = durationMs < 120000
      ? 14000
      : (durationMs * 0.14).round().clamp(16000, 28000).toInt();
  if (outroHintMs != null && outroHintMs > 0) {
    thresh = math.max(thresh, (outroHintMs + 2000).clamp(8000, 32000).toInt());
  }
  return remaining <= thresh;
}"""
    if "import 'dart:math" not in pl:
        pl = "import 'dart:math' as math;\n" + pl
    if old_fn in pl:
        pl = pl.replace(old_fn, new_fn, 1)
        print("inOutro section")
    pl = pl.replace(
        "      inOutroWindow(\n        durationMs: outgoingDurationMs ?? analysisA.durationMs,\n        positionMs: outgoingPositionMs,\n      );",
        "      inOutroWindow(\n        durationMs: outgoingDurationMs ?? analysisA.durationMs,\n        positionMs: outgoingPositionMs,\n        outroHintMs: analysisA.outroHintMs,\n      );",
        1,
    )
    PL.write_text(pl)

MP = Path("lib/providers/music_provider.dart")
mp = MP.read_text()
if "mismatch * 0.28" not in mp:
    old_engage = """  Future<void> _engageDjTransitionSfx() async {
    if (!_djSfxActive) return;
    try {
      await AudioEffectsBridge.setReverb(0.22);
      await ResonateDiagnostics.record('dj_transition_sfx', {
        'action': 'engage',
        'reverb': 0.22,
      });
    } catch (e) {
      debugPrint('DJ transition SFX engage: $e');
    }
  }"""
    new_engage = """  Future<void> _engageDjTransitionSfx({double energyScore = 0.5}) async {
    if (!_djSfxActive) return;
    try {
      final mismatch = (1.0 - energyScore).clamp(0.0, 1.0);
      final reverb = (0.18 + mismatch * 0.28).clamp(0.18, 0.48).toDouble();
      final width = (0.12 + mismatch * 0.22).clamp(0.10, 0.36).toDouble();
      await AudioEffectsBridge.setReverb(reverb);
      await AudioEffectsBridge.setVirtualizer(width);
      await ResonateDiagnostics.record('dj_transition_sfx', {
        'action': 'engage',
        'reverb': reverb,
        'virtualizer': width,
        'energyScore': energyScore,
      });
    } catch (e) {
      debugPrint('DJ transition SFX engage: $e');
    }
  }"""
    if old_engage in mp:
        mp = mp.replace(old_engage, new_engage, 1)
        print("heavy engage")
    old_restore = """  Future<void> _restoreDjTransitionSfx() async {
    if (!_djSfxActive) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final effectsEnabled = prefs.getBool('effects_enabled') ?? true;
      final reverb = prefs.getDouble('reverb') ?? 0.0;
      await AudioEffectsBridge.setReverb(effectsEnabled ? reverb : 0.0);
      await ResonateDiagnostics.record('dj_transition_sfx', {
        'action': 'restore',
        'reverb': effectsEnabled ? reverb : 0.0,
      });
    } catch (e) {
      debugPrint('DJ transition SFX restore: $e');
    }
  }"""
    new_restore = """  Future<void> _restoreDjTransitionSfx() async {
    if (!_djSfxActive) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final effectsEnabled = prefs.getBool('effects_enabled') ?? true;
      final reverb = prefs.getDouble('reverb') ?? 0.0;
      final virt = prefs.getDouble('virtualizer') ?? 0.0;
      await AudioEffectsBridge.setReverb(effectsEnabled ? reverb : 0.0);
      await AudioEffectsBridge.setVirtualizer(effectsEnabled ? virt : 0.0);
      await ResonateDiagnostics.record('dj_transition_sfx', {
        'action': 'restore',
        'reverb': effectsEnabled ? reverb : 0.0,
        'virtualizer': effectsEnabled ? virt : 0.0,
      });
    } catch (e) {
      debugPrint('DJ transition SFX restore: $e');
    }
  }"""
    if old_restore in mp:
        mp = mp.replace(old_restore, new_restore, 1)
        print("heavy restore")
    if "_lastDjEnergyScore" not in mp:
        mp = mp.replace(
            "  int _lastDjCrossfadeBiasMs = 0;",
            "  int _lastDjCrossfadeBiasMs = 0;\n  double _lastDjEnergyScore = 0.5;",
            1,
        )
        mp = mp.replace(
            "_lastDjCrossfadeBiasMs = plan.crossfadeBiasMs;",
            "_lastDjCrossfadeBiasMs = plan.crossfadeBiasMs;\n      _lastDjEnergyScore = plan.energyScore;",
            1,
        )
        mp = mp.replace(
            "await _engageDjTransitionSfx();",
            "await _engageDjTransitionSfx(energyScore: _lastDjEnergyScore);",
            1,
        )
        print("energy score sfx")
    MP.write_text(mp)

print("ALL DONE")
