import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_effects_bridge.dart';

/// DJ transition SFX presets (soft, always restorable).
enum DjSfxPreset {
  clubOpen,
  filterOpen,
  filterClose,
  bassDrop,
  wideSpace,
  tightGlue,
  dryPunch,
}

/// Picks and drives transition SFX without blocking playback.
class DjSfxRack {
  DjSfxRack({math.Random? random}) : _rng = random ?? math.Random();

  final math.Random _rng;
  DjSfxPreset? activePreset;
  bool engaged = false;
  List<double>? _savedEqGains;
  bool _eqTouched = false;

  static const presets = DjSfxPreset.values;

  DjSfxPreset pickRandom({double energyScore = 0.5}) {
    final high = energyScore >= 0.75;
    // At high energy avoid clubOpen / bassDrop (they stack on already loud mixes).
    final weights = <DjSfxPreset, int>{
      DjSfxPreset.clubOpen: high ? 1 : 3,
      DjSfxPreset.filterOpen: high ? 3 : 2,
      DjSfxPreset.filterClose: high ? 3 : 2,
      DjSfxPreset.bassDrop: high ? 1 : 2,
      DjSfxPreset.wideSpace: high ? 2 : 2,
      DjSfxPreset.tightGlue: high ? 4 : 3,
      DjSfxPreset.dryPunch: high ? 3 : 2,
    };
    final total = weights.values.fold<int>(0, (a, b) => a + b);
    var r = _rng.nextInt(total);
    for (final e in weights.entries) {
      r -= e.value;
      if (r < 0) return e.key;
    }
    return DjSfxPreset.tightGlue;
  }

  Future<void> engage({
    required double energyScore,
    DjSfxPreset? preset,
    AndroidEqualizer? equalizerA,
    AndroidEqualizer? equalizerB,
  }) async {
    final score =
        energyScore.isFinite ? energyScore.clamp(0.0, 1.0).toDouble() : 0.5;
    final mismatch = (1.0 - score).clamp(0.0, 1.0).toDouble();
    activePreset = preset ?? pickRandom(energyScore: score);
    engaged = true;
    _eqTouched = false;

    try {
      await _snapshotEq(equalizerA);
      // Start silent — first tick of the crossfade fades in.
      await _applyNativeAt(0.0, score, mismatch);
      if (_usesEq(activePreset!)) {
        await _applyEqAt(equalizerA, 0.0);
        await _applyEqAt(equalizerB, 0.0);
        _eqTouched = true;
      }
    } catch (e) {
      debugPrint('DjSfxRack.engage: $e');
    }
  }

  /// [t] is 0→1 over the crossfade. Values above 1 are post-gap release
  /// (caller should tick ~1.15…1.6 before [restore] so SFX bridges the songs).
  Future<void> tick(
    double t, {
    AndroidEqualizer? equalizerA,
    AndroidEqualizer? equalizerB,
    double energyScore = 0.5,
  }) async {
    if (!engaged || activePreset == null) return;
    final score =
        energyScore.isFinite ? energyScore.clamp(0.0, 1.0).toDouble() : 0.5;
    final mismatch = (1.0 - score).clamp(0.0, 1.0).toDouble();
    try {
      await _applyNativeAt(t, score, mismatch);
      if (_usesEq(activePreset!)) {
        await _applyEqAt(equalizerA, t);
        await _applyEqAt(equalizerB, t);
        _eqTouched = true;
      }
    } catch (_) {}
  }

  Future<void> restore({
    AndroidEqualizer? equalizerA,
    AndroidEqualizer? equalizerB,
  }) async {
    if (!engaged && !_eqTouched) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final effectsEnabled = prefs.getBool('effects_enabled') ?? true;
      final reverb = prefs.getDouble('reverb') ?? 0.0;
      final virt = prefs.getDouble('virtualizer') ?? 0.0;
      final bass = prefs.getDouble('bassBoost') ?? 0.0;
      await AudioEffectsBridge.setBassBoost(effectsEnabled ? bass : 0.0);
      await AudioEffectsBridge.setReverb(effectsEnabled ? reverb : 0.0);
      await AudioEffectsBridge.setVirtualizer(effectsEnabled ? virt : 0.0);
      if (_eqTouched) {
        await _restoreEq(equalizerA);
        await _restoreEq(equalizerB);
      }
    } catch (e) {
      debugPrint('DjSfxRack.restore: $e');
    } finally {
      engaged = false;
      _eqTouched = false;
      activePreset = null;
      _savedEqGains = null;
    }
  }

  bool _usesEq(DjSfxPreset p) =>
      p == DjSfxPreset.filterOpen ||
      p == DjSfxPreset.filterClose ||
      p == DjSfxPreset.bassDrop;

  /// Soft attack / sustain / release so SFX never hard-cuts.
  double _envelope(double t) {
    if (t <= 0) return 0.0;
    if (t < 0.18) return (t / 0.18).clamp(0.0, 1.0);
    if (t <= 1.0) return 1.0;
    return ((1.6 - t) / 0.6).clamp(0.0, 1.0);
  }

  Future<void> _applyNativeAt(double t, double score, double mismatch) async {
    final p = activePreset ?? DjSfxPreset.clubOpen;
    final env = _envelope(t);
    final x = t.clamp(0.0, 1.0);
    double bass = 0.0, width = 0.0, reverb = 0.0;
    switch (p) {
      case DjSfxPreset.clubOpen:
        // Kept gentle — high-energy path scales further in energyScale.
        bass = (0.06 * (1.0 - x) + 0.02).clamp(0.01, 0.10);
        width = (0.06 + 0.18 * x).clamp(0.04, 0.26);
        reverb = (0.10 + 0.16 * math.sin(x * math.pi)).clamp(0.06, 0.28);
        break;
      case DjSfxPreset.filterOpen:
        bass = (0.08 * (1.0 - x) + 0.02).clamp(0.02, 0.12);
        width = (0.06 + 0.20 * x).clamp(0.04, 0.28);
        reverb = (0.10 + 0.18 * math.sin(x * math.pi)).clamp(0.08, 0.32);
        break;
      case DjSfxPreset.filterClose:
        bass = (0.04 + 0.10 * x).clamp(0.02, 0.14);
        width = (0.16 * (1.0 - x) + 0.06).clamp(0.04, 0.22);
        reverb = (0.10 + 0.14 * (1.0 - x)).clamp(0.06, 0.26);
        break;
      case DjSfxPreset.bassDrop:
        final punch = math.sin(x * math.pi);
        bass = (0.04 + 0.10 * punch).clamp(0.02, 0.14);
        width = (0.04 + 0.08 * x).clamp(0.03, 0.14);
        reverb = (0.06 + 0.08 * punch).clamp(0.04, 0.18);
        break;
      case DjSfxPreset.wideSpace:
        bass = (0.04 + 0.04 * mismatch).clamp(0.02, 0.10);
        width = (0.18 + 0.30 * x + mismatch * 0.08).clamp(0.12, 0.48);
        reverb = (0.12 + 0.22 * math.sin(x * math.pi)).clamp(0.08, 0.36);
        break;
      case DjSfxPreset.tightGlue:
        bass = (0.05 + mismatch * 0.05).clamp(0.02, 0.12);
        width = (0.05 + 0.06 * x).clamp(0.03, 0.16);
        reverb = (0.18 + mismatch * 0.18 + 0.10 * math.sin(x * math.pi))
            .clamp(0.12, 0.42);
        break;
      case DjSfxPreset.dryPunch:
        bass = (0.08 * math.sin(x * math.pi)).clamp(0.0, 0.14);
        width = (0.04 + 0.05 * x).clamp(0.0, 0.12);
        reverb = (0.06 + 0.14 * math.sin(x * math.pi * 2).abs())
            .clamp(0.0, 0.22);
        break;
    }
    // High-energy tracks: pull SFX way down so we do not double-thump.
    final energyScale = score >= 0.85
        ? 0.45
        : (score >= 0.7 ? 0.62 : (score >= 0.55 ? 0.82 : 1.0));
    bass = (bass * env * energyScale).clamp(0.0, 0.14);
    width = (width * env * energyScale).clamp(0.0, 0.36);
    reverb = (reverb * env * energyScale).clamp(0.0, 0.32);
    await AudioEffectsBridge.setBassBoost(bass);
    await AudioEffectsBridge.setVirtualizer(width);
    await AudioEffectsBridge.setReverb(reverb);
  }

  Future<void> _snapshotEq(AndroidEqualizer? eq) async {
    if (eq == null) return;
    try {
      final p = await eq.parameters;
      _savedEqGains = [for (final b in p.bands) b.gain];
    } catch (_) {
      _savedEqGains = null;
    }
  }

  Future<void> _applyEqAt(AndroidEqualizer? eq, double t) async {
    if (eq == null || activePreset == null) return;
    try {
      final p = await eq.parameters;
      final bands = p.bands;
      if (bands.isEmpty) return;
      final n = bands.length;
      final minG = p.minDecibels;
      final maxG = p.maxDecibels;
      final env = _envelope(t);
      final x = t.clamp(0.0, 1.0);
      for (var i = 0; i < n; i++) {
        final frac = n <= 1 ? 0.5 : i / (n - 1);
        double gain = 0.0;
        switch (activePreset!) {
          case DjSfxPreset.filterOpen:
            gain = -7.0 * (1.0 - x) * frac;
            break;
          case DjSfxPreset.filterClose:
            gain = -6.0 * (1.0 - x) * (1.0 - frac);
            break;
          case DjSfxPreset.bassDrop:
            final low = frac < 0.35;
            final punch = math.sin(x * math.pi);
            gain = low ? (-1.5 + 4.0 * punch) : (-1.0 * (1.0 - x) * frac);
            break;
          default:
            gain = 0.0;
        }
        gain *= env;
        await bands[i].setGain(gain.clamp(minG, maxG).toDouble());
      }
      await eq.setEnabled(true);
    } catch (_) {}
  }

  Future<void> _restoreEq(AndroidEqualizer? eq) async {
    if (eq == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final eqOn = prefs.getBool('equalizer_enabled') ?? true;
      final p = await eq.parameters;
      final bands = p.bands;
      for (var i = 0; i < bands.length; i++) {
        double g = 0.0;
        if (_savedEqGains != null && i < _savedEqGains!.length) {
          g = _savedEqGains![i];
        } else {
          g = prefs.getDouble('eq_band_${bands[i].index}') ?? 0.0;
        }
        await bands[i]
            .setGain(g.clamp(p.minDecibels, p.maxDecibels).toDouble());
      }
      await eq.setEnabled(eqOn);
    } catch (_) {}
  }

  String get presetName => activePreset?.name ?? 'none';
}
