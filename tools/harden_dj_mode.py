#!/usr/bin/env python3
"""Harden DJ Mode: upsert columns, SFX engaged flag, handoff guards, analyzer try/catch."""
from pathlib import Path

# ---------- DB upsert: persist section/key hints ----------
DB = Path("lib/services/database_helper.dart")
db = DB.read_text()
old_upsert = """          columnDjEnergy: analysis.energy,
          columnDjLoudness: analysis.loudness,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,"""
new_upsert = """          columnDjEnergy: analysis.energy,
          columnDjLoudness: analysis.loudness,
          columnDjIntroHintMs: analysis.introHintMs,
          columnDjOutroHintMs: analysis.outroHintMs,
          columnDjSectionHint: analysis.sectionHint,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,"""
if "columnDjIntroHintMs: analysis.introHintMs" not in db:
    if old_upsert not in db:
        raise SystemExit("upsert block miss")
    db = db.replace(old_upsert, new_upsert, 1)
    DB.write_text(db)
    print("db upsert section fields")
else:
    print("db upsert already")

# ---------- features analyzer: outer try/catch ----------
FEAT = Path("lib/services/dj_pcm_features.dart")
feat = FEAT.read_text()
if "analyze(\n    Uint8List pcm" in feat and "try {" not in feat.split("DjPcmFeatures analyze")[1][:200]:
    old_a = """  DjPcmFeatures analyze(
    Uint8List pcm,
    int sampleRate,
    int channels, {
    String windowRole = 'start',
  }) {
    if (sampleRate < 8000 || channels < 1 || pcm.length < sampleRate) {
      return const DjPcmFeatures();
    }

    final mono =
        _toMonoDownsampled(pcm, sampleRate, channels, targetRate: 11025);
    const rate = 11025;
    final section = _sectionFromMono(mono, rate, windowRole: windowRole);
    final key = _softKeyFromMono(mono, rate);

    return DjPcmFeatures(
      keyRoot: key.$1,
      keyMode: key.$2,
      keyConfidence: key.$3,
      keySource: key.$3 >= 0.28 ? 'pcm_chroma' : 'none',
      introHintMs: section.introHintMs,
      outroHintMs: section.outroHintMs,
      headEnergy: section.headEnergy,
      bodyEnergy: section.bodyEnergy,
      sectionHint: section.sectionHint,
    );
  }"""
    new_a = """  DjPcmFeatures analyze(
    Uint8List pcm,
    int sampleRate,
    int channels, {
    String windowRole = 'start',
  }) {
    try {
      if (sampleRate < 8000 || channels < 1 || pcm.length < sampleRate) {
        return const DjPcmFeatures();
      }

      final mono =
          _toMonoDownsampled(pcm, sampleRate, channels, targetRate: 11025);
      const rate = 11025;
      final section = _sectionFromMono(mono, rate, windowRole: windowRole);
      final key = _softKeyFromMono(mono, rate);

      return DjPcmFeatures(
        keyRoot: key.$1,
        keyMode: key.$2,
        keyConfidence: key.$3,
        keySource: key.$3 >= 0.28 ? 'pcm_chroma' : 'none',
        introHintMs: section.introHintMs,
        outroHintMs: section.outroHintMs,
        headEnergy: section.headEnergy,
        bodyEnergy: section.bodyEnergy,
        sectionHint: section.sectionHint,
      );
    } catch (_) {
      return const DjPcmFeatures();
    }
  }"""
    if old_a in feat:
        feat = feat.replace(old_a, new_a, 1)
        FEAT.write_text(feat)
        print("features try/catch")
    else:
        print("WARN features analyze miss")
else:
    print("features already guarded or pattern differ")

# ---------- analysis service: prefer cache under time pressure ----------
AS = Path("lib/services/dj_analysis_service.dart")
as_ = AS.read_text()
if "analyzeSongCachedFirst" not in as_:
    helper = '''
  /// Prefer cache; only recompute when missing/stale. Safe for handoff path.
  Future<DjAnalysis> analyzeSongCachedFirst(Song song) async {
    final existing = await getAnalysis(song.id);
    if (existing != null &&
        !existing.isStale &&
        (existing.hasUsableBpm ||
            existing.hasUsableKey ||
            existing.hasUsableEnergy)) {
      return existing;
    }
    return analyzeSong(song);
  }
'''
    # insert before scheduleAnalyze
    if "void scheduleAnalyze" in as_:
        as_ = as_.replace("  void scheduleAnalyze", helper + "  void scheduleAnalyze", 1)
        AS.write_text(as_)
        print("cachedFirst")
    else:
        print("WARN scheduleAnalyze miss")

# ---------- music_provider harden ----------
MP = Path("lib/providers/music_provider.dart")
mp = MP.read_text()

# Flag: SFX actually engaged this crossfade (restore even if toggle flipped)
if "_djSfxEngaged" not in mp:
    mp = mp.replace(
        "  bool _djSfxActive = false;",
        "  bool _djSfxActive = false;\n  bool _djSfxEngaged = false;",
        1,
    )
    print("sfx engaged flag")

# engage sets flag
old_eng = """  Future<void> _engageDjTransitionSfx({double energyScore = 0.5}) async {
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
new_eng = """  Future<void> _engageDjTransitionSfx({double energyScore = 0.5}) async {
    if (!_djSfxActive) return;
    try {
      final score = energyScore.isFinite ? energyScore.clamp(0.0, 1.0).toDouble() : 0.5;
      final mismatch = (1.0 - score).clamp(0.0, 1.0).toDouble();
      final reverb = (0.18 + mismatch * 0.28).clamp(0.18, 0.48).toDouble();
      final width = (0.12 + mismatch * 0.22).clamp(0.10, 0.36).toDouble();
      await AudioEffectsBridge.setReverb(reverb);
      await AudioEffectsBridge.setVirtualizer(width);
      _djSfxEngaged = true;
      await ResonateDiagnostics.record('dj_transition_sfx', {
        'action': 'engage',
        'reverb': reverb,
        'virtualizer': width,
        'energyScore': score,
      });
    } catch (e) {
      debugPrint('DJ transition SFX engage: $e');
    }
  }"""
if "_djSfxEngaged = true" not in mp:
    if old_eng not in mp:
        print("WARN engage miss")
    else:
        mp = mp.replace(old_eng, new_eng, 1)
        print("engage harden")

old_res = """  Future<void> _restoreDjTransitionSfx() async {
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
new_res = """  Future<void> _restoreDjTransitionSfx() async {
    // Restore if we engaged this fade — even if user toggled SFX off mid-crossfade.
    if (!_djSfxEngaged && !_djSfxActive) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final effectsEnabled = prefs.getBool('effects_enabled') ?? true;
      final reverb = prefs.getDouble('reverb') ?? 0.0;
      final virt = prefs.getDouble('virtualizer') ?? 0.0;
      await AudioEffectsBridge.setReverb(effectsEnabled ? reverb : 0.0);
      await AudioEffectsBridge.setVirtualizer(effectsEnabled ? virt : 0.0);
      _djSfxEngaged = false;
      await ResonateDiagnostics.record('dj_transition_sfx', {
        'action': 'restore',
        'reverb': effectsEnabled ? reverb : 0.0,
        'virtualizer': effectsEnabled ? virt : 0.0,
      });
    } catch (e) {
      _djSfxEngaged = false;
      debugPrint('DJ transition SFX restore: $e');
    }
  }"""
if "!_djSfxEngaged && !_djSfxActive" not in mp:
    if old_res not in mp:
        print("WARN restore miss")
    else:
        mp = mp.replace(old_res, new_res, 1)
        print("restore harden")

# Handoff: use cachedFirst + guard bpm null + finite energy
old_prep_wait = """        final aFuture = _djAnalysis!.analyzeSong(outgoingSong);
        final bFuture = _djAnalysis!.analyzeSong(incomingSong);
        results = await Future.wait<DjAnalysis>([aFuture, bFuture]).timeout(
          const Duration(milliseconds: 2800),
          onTimeout: () => const <DjAnalysis>[],
        );"""
new_prep_wait = """        final aFuture = _djAnalysis!.analyzeSongCachedFirst(outgoingSong);
        final bFuture = _djAnalysis!.analyzeSongCachedFirst(incomingSong);
        results = await Future.wait<DjAnalysis>([aFuture, bFuture]).timeout(
          const Duration(milliseconds: 2200),
          onTimeout: () => const <DjAnalysis>[],
        );"""
if "analyzeSongCachedFirst" not in mp:
    if old_prep_wait not in mp:
        print("WARN prep wait miss")
    else:
        mp = mp.replace(old_prep_wait, new_prep_wait, 1)
        print("handoff cachedFirst")

# Guard force unwrap bpmA/bpmB
old_bpm = """      final bpmA = plan.bpmA!;
      final bpmB = plan.bpmB!;"""
new_bpm = """      final bpmA = plan.bpmA;
      final bpmB = plan.bpmB;
      if (bpmA == null || bpmB == null || bpmA < 40 || bpmB < 40) {
        await ResonateDiagnostics.recordDj(
          stage: 'handoff',
          outcome: 'applied',
          reason: 'missing_bpm_after_plan',
          songId: incomingSong.id,
          extra: plan.toDiagExtra(),
        );
        return;
      }"""
if "missing_bpm_after_plan" not in mp:
    if old_bpm not in mp:
        print("WARN bpm unwrap miss")
    else:
        mp = mp.replace(old_bpm, new_bpm, 1)
        print("bpm null guard")

# Finite energy score from plan
if "_lastDjEnergyScore = plan.energyScore;" in mp:
    mp = mp.replace(
        "_lastDjEnergyScore = plan.energyScore;",
        "_lastDjEnergyScore = plan.energyScore.isFinite\n          ? plan.energyScore.clamp(0.0, 1.0).toDouble()\n          : 0.5;",
        1,
    )
    print("energy finite")

# Ensure restore on more abort paths that clear stretch after engage
# Pattern: clearDjStretch then return false without restore
# Too late already has restore. Check incoming start failed path.
if "crossfade incoming engine failed" in mp:
    # After throw or before - look for incoming start failed
    pass

# Before finally of performTrueCrossfade - ensure restore when _crossfadeInProgress cleared
# Find common finally if any
if "_crossfadeInProgress = false" in mp and mp.count("_restoreDjTransitionSfx") < 3:
    # Inject restore into a catch at end of performTrueCrossfade if missing
    # Search for typical end
    marker = "      _crossfadeInProgress = false;\n    }"
    # Too broad - skip

# On prepare early return after timeout, zero bias already done at start

MP.write_text(mp)
print("music_provider done")

# ---------- planner: finite energy ----------
PL = Path("lib/services/dj_transition_planner.dart")
pl = PL.read_text()
if "isFinite" not in pl:
    old_ec = """double energyCompatibility(double? a, double? b) {
  if (a == null || b == null) return 0.5;
  final d = (a - b).abs().clamp(0.0, 1.0);
  return (1.0 - d);
}"""
    new_ec = """double energyCompatibility(double? a, double? b) {
  if (a == null || b == null) return 0.5;
  if (!a.isFinite || !b.isFinite) return 0.5;
  final aa = a.clamp(0.0, 1.0).toDouble();
  final bb = b.clamp(0.0, 1.0).toDouble();
  final d = (aa - bb).abs().clamp(0.0, 1.0).toDouble();
  return (1.0 - d);
}"""
    if old_ec in pl:
        pl = pl.replace(old_ec, new_ec, 1)
        PL.write_text(pl)
        print("energyCompat finite")

# ---------- pcm bpm: NaN guard ----------
PCM = Path("lib/services/dj_pcm_bpm.dart")
pcm = PCM.read_text()
if "bpm.isFinite" not in pcm:
    pcm = pcm.replace(
        "    if (bpm < 60 || bpm > 180) return null;",
        "    if (!bpm.isFinite || bpm < 60 || bpm > 180) return null;",
        1,
    )
    PCM.write_text(pcm)
    print("pcm bpm finite")

print("ALL HARDEN DONE")
