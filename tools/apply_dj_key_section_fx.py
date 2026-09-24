#!/usr/bin/env python3
"""Wire key-from-PCM, section hints, DB v7, heavier transition SFX."""
from pathlib import Path
import re

# ---------- model v4 ----------
MODEL = Path("lib/models/dj_analysis.dart")
md = MODEL.read_text()
if "currentVersion = 4" not in md:
    md = md.replace("currentVersion = 3", "currentVersion = 4", 1)
    md = md.replace(
        "/// (v1: native PCM BPM; v2: energy/loudness; v3: beatOffset + ID3+PCM merge).",
        "/// (v1–v3 prior; v4: pcm key + intro/outro section hints).",
        1,
    )
    if "final int? introHintMs;" not in md:
        md = md.replace(
            "  final double? loudness;\n",
            "  final double? loudness;\n"
            "  /// Soft intro length estimate (ms) from head energy.\n"
            "  final int? introHintMs;\n"
            "  /// Soft outro length estimate (ms) from end-window energy.\n"
            "  final int? outroHintMs;\n"
            "  /// quiet_intro | energetic | quiet_outro | unknown\n"
            "  final String? sectionHint;\n"
            "  /// id3_tkey | pcm_chroma | none\n"
            "  final String? keySource;\n",
            1,
        )
        md = md.replace(
            "    this.loudness,\n  });",
            "    this.loudness,\n"
            "    this.introHintMs,\n"
            "    this.outroHintMs,\n"
            "    this.sectionHint,\n"
            "    this.keySource,\n  });",
            1,
        )
        # fromMap
        md = md.replace(
            "      loudness: (map['loudness'] as num?)?.toDouble(),\n    );",
            "      loudness: (map['loudness'] as num?)?.toDouble(),\n"
            "      introHintMs: (map['intro_hint_ms'] as num?)?.toInt(),\n"
            "      outroHintMs: (map['outro_hint_ms'] as num?)?.toInt(),\n"
            "      sectionHint: map['section_hint'] as String?,\n"
            "      keySource: map['key_source'] as String?,\n    );",
            1,
        )
        md = md.replace(
            "      'loudness': loudness,\n    };",
            "      'loudness': loudness,\n"
            "      'intro_hint_ms': introHintMs,\n"
            "      'outro_hint_ms': outroHintMs,\n"
            "      'section_hint': sectionHint,\n"
            "      'key_source': keySource,\n    };",
            1,
        )
        # copyWith params + body
        if "double? loudness,\n  })" in md and "introHintMs" not in md.split("copyWith")[1][:400]:
            md = md.replace(
                "    double? loudness,\n  }) {",
                "    double? loudness,\n"
                "    int? introHintMs,\n"
                "    int? outroHintMs,\n"
                "    String? sectionHint,\n"
                "    String? keySource,\n  }) {",
                1,
            )
            md = md.replace(
                "      loudness: loudness ?? this.loudness,\n    );\n  }\n}",
                "      loudness: loudness ?? this.loudness,\n"
                "      introHintMs: introHintMs ?? this.introHintMs,\n"
                "      outroHintMs: outroHintMs ?? this.outroHintMs,\n"
                "      sectionHint: sectionHint ?? this.sectionHint,\n"
                "      keySource: keySource ?? this.keySource,\n    );\n  }\n}",
                1,
            )
    MODEL.write_text(md)
    print("model v4")
else:
    print("model already v4")

# ---------- DB v7 ----------
DB = Path("lib/services/database_helper.dart")
db = DB.read_text()
if "columnDjIntroHintMs" not in db:
    db = db.replace(
        "static const String columnDjLoudness = 'loudness';",
        "static const String columnDjLoudness = 'loudness';\n"
        "  static const String columnDjIntroHintMs = 'intro_hint_ms';\n"
        "  static const String columnDjOutroHintMs = 'outro_hint_ms';\n"
        "  static const String columnDjSectionHint = 'section_hint';\n"
        "  static const String columnDjKeySource = 'key_source';",
        1,
    )
    db = db.replace("_databaseVersion = 6", "_databaseVersion = 7", 1)
    db = db.replace(
        "$columnDjLoudness REAL, FOREIGN KEY ($columnDjSongId)",
        "$columnDjLoudness REAL, $columnDjIntroHintMs INTEGER, $columnDjOutroHintMs INTEGER, $columnDjSectionHint TEXT, $columnDjKeySource TEXT, FOREIGN KEY ($columnDjSongId)",
    )
    if "oldVersion < 7" not in db:
        db = db.replace(
            """    if (oldVersion < 6) {
      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjEnergy REAL'); } catch (_) {}
      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjLoudness REAL'); } catch (_) {}
    }
""",
            """    if (oldVersion < 6) {
      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjEnergy REAL'); } catch (_) {}
      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjLoudness REAL'); } catch (_) {}
    }
    if (oldVersion < 7) {
      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjIntroHintMs INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjOutroHintMs INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjSectionHint TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjKeySource TEXT'); } catch (_) {}
    }
""",
            1,
        )
    if "columnDjIntroHintMs: analysis.introHintMs" not in db:
        db = db.replace(
            "          columnDjLoudness: analysis.loudness,\n        },",
            "          columnDjLoudness: analysis.loudness,\n"
            "          columnDjIntroHintMs: analysis.introHintMs,\n"
            "          columnDjOutroHintMs: analysis.outroHintMs,\n"
            "          columnDjSectionHint: analysis.sectionHint,\n"
            "          columnDjKeySource: analysis.keySource,\n        },",
            1,
        )
    DB.write_text(db)
    print("db v7")
else:
    print("db already v7")

# ---------- estimator: features on native pcm + optional end window ----------
EST = Path("lib/services/dj_bpm_estimator.dart")
est = EST.read_text()
if "dj_pcm_features.dart" not in est:
    est = est.replace(
        "import 'dj_pcm_bpm.dart';",
        "import 'dj_pcm_bpm.dart';\nimport 'dj_pcm_features.dart';",
        1,
    )

# Extend DjBpmEstimate with section/key source fields if missing
if "final int? introHintMs;" not in est:
    est = est.replace(
        "  final double? loudness;\n",
        "  final double? loudness;\n"
        "  final int? introHintMs;\n"
        "  final int? outroHintMs;\n"
        "  final String? sectionHint;\n"
        "  final String? keySource;\n",
        1,
    )
    est = est.replace(
        "    this.loudness,\n  });",
        "    this.loudness,\n"
        "    this.introHintMs,\n"
        "    this.outroHintMs,\n"
        "    this.sectionHint,\n"
        "    this.keySource,\n  });",
        1,
    )

# Patch _estimateFromNativePcm to attach features
old_native_ret = """      return DjBpmEstimate(
        bpm: est.bpm,
        confidence: est.confidence,
        beatOffsetMs: est.beatOffsetMs,
        source: 'pcm_native',
        energy: est.energy,
        loudness: est.loudness,
      );"""
new_native_ret = """      final feat = DjPcmFeatureAnalyzer().analyze(
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
        keyRoot: feat.keyRoot,
        keyMode: feat.keyMode,
        keyConfidence: feat.keyConfidence,
        introHintMs: feat.introHintMs,
        outroHintMs: feat.outroHintMs,
        sectionHint: feat.sectionHint,
        keySource: feat.keySource,
      );"""
if "DjPcmFeatureAnalyzer" not in est:
    if old_native_ret not in est:
        raise SystemExit("native ret miss")
    est = est.replace(old_native_ret, new_native_ret, 1)
    print("native features")

# When merging ID3 key with PCM, prefer ID3 key but keep section from native
# Update id3_tbpm+pcm return to pass section fields from nativePcm
if "introHintMs: nativePcm.introHintMs" not in est:
    est = est.replace(
        """            energy: nativePcm.energy,
            loudness: nativePcm.loudness,
          );
        }
        if (key != null) {
""",
        """            energy: nativePcm.energy,
            loudness: nativePcm.loudness,
            introHintMs: nativePcm.introHintMs,
            outroHintMs: nativePcm.outroHintMs,
            sectionHint: nativePcm.sectionHint,
            keySource: key?.keyRoot != null ? 'id3_tkey' : nativePcm.keySource,
          );
        }
        if (key != null) {
""",
        1,
    )
    # key != null branch from native
    est = est.replace(
        """            energy: nativePcm.energy,
            loudness: nativePcm.loudness,
          );
        }
        return nativePcm;
""",
        """            energy: nativePcm.energy,
            loudness: nativePcm.loudness,
            introHintMs: nativePcm.introHintMs,
            outroHintMs: nativePcm.outroHintMs,
            sectionHint: nativePcm.sectionHint,
            keySource: 'id3_tkey',
            // key already set above
          );
        }
        return nativePcm;
""",
        1,
    )
    print("merge section fields")

# Prefer ID3 key over weak PCM key when both exist in native-only path with key
# (already handled)

EST.write_text(est)

# ---------- analysis_service map new fields ----------
AS = Path("lib/services/dj_analysis_service.dart")
as_ = AS.read_text()
if "introHintMs: estimate.introHintMs" not in as_:
    as_ = as_.replace(
        "              energy: estimate.energy,\n              loudness: estimate.loudness,\n            );",
        "              energy: estimate.energy,\n"
        "              loudness: estimate.loudness,\n"
        "              introHintMs: estimate.introHintMs,\n"
        "              outroHintMs: estimate.outroHintMs,\n"
        "              sectionHint: estimate.sectionHint,\n"
        "              keySource: estimate.keySource ??\n                  (estimate.keyRoot != null ? 'id3_tkey' : null),\n            );",
        1,
    )
    AS.write_text(as_)
    print("analysis_service fields")
else:
    print("analysis_service already")

# ---------- heavier transition SFX ----------
MP = Path("lib/providers/music_provider.dart")
mp = MP.read_text()
old_eng = """  Future<void> _engageDjTransitionSfx() async {
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
  }
"""
new_eng = """  Future<void> _engageDjTransitionSfx() async {
    if (!_djSfxActive) return;
    try {
      // Heavier but still soft: reverb glue + light bass + width.
      await AudioEffectsBridge.setReverb(0.38);
      await AudioEffectsBridge.setBassBoost(0.14);
      await AudioEffectsBridge.setVirtualizer(0.18);
      // Soft high-cut on outgoing engine EQ if bands exist.
      try {
        final params = await equalizer.parameters;
        for (final band in params.bands) {
          final hz = band.centerFrequency;
          if (hz >= 4000) {
            final g = band.gain;
            await band.setGain(
              (g - 2.5).clamp(params.minDecibels, params.maxDecibels).toDouble(),
            );
          }
        }
      } catch (_) {}
      await ResonateDiagnostics.record('dj_transition_sfx', {
        'action': 'engage',
        'reverb': 0.38,
        'bassBoost': 0.14,
        'virtualizer': 0.18,
        'highCut': true,
      });
    } catch (e) {
      debugPrint('DJ transition SFX engage: $e');
    }
  }
"""
if "highCut": true," in mp or "'highCut': true" in mp:
    print("heavy sfx already")
elif old_eng in mp:
    mp = mp.replace(old_eng, new_eng, 1)
    print("heavy sfx engage")
else:
    print("WARN engage block miss")

old_res = """  Future<void> _restoreDjTransitionSfx() async {
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
  }
"""
new_res = """  Future<void> _restoreDjTransitionSfx() async {
    if (!_djSfxActive) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final effectsEnabled = prefs.getBool('effects_enabled') ?? true;
      final reverb = prefs.getDouble('reverb') ?? 0.0;
      final bass = prefs.getDouble('bassBoost') ?? 0.0;
      final virt = prefs.getDouble('virtualizer') ?? 0.0;
      await AudioEffectsBridge.setReverb(effectsEnabled ? reverb : 0.0);
      await AudioEffectsBridge.setBassBoost(effectsEnabled ? bass : 0.0);
      await AudioEffectsBridge.setVirtualizer(effectsEnabled ? virt : 0.0);
      try {
        await _audioEffectsController.syncAll();
      } catch (_) {}
      await ResonateDiagnostics.record('dj_transition_sfx', {
        'action': 'restore',
        'reverb': effectsEnabled ? reverb : 0.0,
        'bassBoost': effectsEnabled ? bass : 0.0,
        'virtualizer': effectsEnabled ? virt : 0.0,
      });
    } catch (e) {
      debugPrint('DJ transition SFX restore: $e');
    }
  }
"""
if "await _audioEffectsController.syncAll()" in mp and "action': 'restore'" in mp:
    # may already be partial
    if old_res in mp:
        mp = mp.replace(old_res, new_res, 1)
        print("heavy sfx restore")
    else:
        print("restore block already custom")
elif old_res in mp:
    mp = mp.replace(old_res, new_res, 1)
    print("heavy sfx restore")

MP.write_text(mp)
print("ALL DONE")
