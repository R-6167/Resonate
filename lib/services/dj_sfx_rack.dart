import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_effects_bridge.dart';

/// DJ transition SFX presets (soft, always restorable).
enum DjSfxPreset {
  /// Classic club open: bass + reverb glue + width.
  clubOpen,
  /// Low-pass → open (EQ high bands rise).
  filterOpen,
  /// High-pass darken then full (EQ low bands rise).
  filterClose,
  /// Bass punch mid-fade then settle.
  bassDrop,
  /// Wide virtualizer + light reverb.
  wideSpace,
  /// Tight reverb glue, minimal width.
  tightGlue,
  /// Mostly dry with a short mid reverb bump.
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

  /// Weighted random — filter sweeps slightly less often than glue styles.
  DjSfxPreset pickRandom() {
    const weights = <DjSfxPreset, int>{
      DjSfxPreset.clubOpen: 3,
      DjSfxPreset.filterOpen: 2,
      DjSfxPreset.filterClose: 2,
      DjSfxPreset.bassDrop: 2,
      DjSfxPreset.wideSpace: 2,
      DjSfxPreset.tightGlue: 3,
      DjSfxPreset.dryPunch: 2,
    };
    final total = weights.values.fold<int>(0, (a, b) => a + b);
    var r = _rng.nextInt(total);
    for (final e in weights.entries) {
      r -= e.value;
      if (r < 0) return e.key;
    }
    return DjSfxPreset.clubOpen;
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
    activePreset = preset ?? pickRandom();
    engaged = true;
    _eqTouched = false;

    try {
      await _snapshotEq(equalizerA);
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
    final x = t.clamp(0.0, 1.0).toDouble();
    try {
      await _applyNativeAt(x, score, mismatch);
      if (_usesEq(activePreset!)) {
        await _applyEqAt(equalizerA, x);
        await _applyEqAt(equalizerB, x);
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

  Future<void> _applyNativeAt(double t, double score, double mismatch) async {
    final p = activePreset ?? DjSfxPreset.clubOpen;
    double bass = 0.0, width = 0.0, reverb = 0.0;
    switch (p) {
      case DjSfxPreset.clubOpen:
        bass = (0.38 * (1.0 - t) + 0.06).clamp(0.05, 0.42);
        width = (0.08 + 0.40 * t).clamp(0.08, 0.48);
        reverb = (0.16 + 0.34 * math.sin(t * math.pi)).clamp(0.12, 0.52);
        break;
      case DjSfxPreset.filterOpen:
        bass = (0.28 * (1.0 - t) + 0.05).clamp(0.04, 0.35);
        width = (0.06 + 0.25 * t).clamp(0.05, 0.35);
        reverb = (0.12 + 0.22 * math.sin(t * math.pi)).clamp(0.08, 0.40);
        break;
      case DjSfxPreset.filterClose:
        bass = (0.12 + 0.28 * t).clamp(0.05, 0.40);
        width = (0.22 * (1.0 - t) + 0.08).clamp(0.06, 0.32);
        reverb = (0.10 + 0.18 * (1.0 - t)).clamp(0.06, 0.32);
        break;
      case DjSfxPreset.bassDrop:
        final punch = math.sin(t * math.pi);
        bass = (0.15 + 0.45 * punch).clamp(0.08, 0.55);
        width = (0.08 + 0.12 * t).clamp(0.06, 0.28);
        reverb = (0.10 + 0.15 * punch).clamp(0.06, 0.30);
        break;
      case DjSfxPreset.wideSpace:
        bass = (0.10 + 0.08 * mismatch).clamp(0.05, 0.25);
        width = (0.22 + 0.40 * t + mismatch * 0.1).clamp(0.15, 0.62);
        reverb = (0.14 + 0.28 * math.sin(t * math.pi)).clamp(0.10, 0.48);
        break;
      case DjSfxPreset.tightGlue:
        bass = (0.12 + mismatch * 0.1).clamp(0.06, 0.28);
        width = (0.06 + 0.08 * t).clamp(0.04, 0.20);
        reverb = (0.22 + mismatch * 0.25 + 0.12 * math.sin(t * math.pi))
            .clamp(0.18, 0.55);
        break;
      case DjSfxPreset.dryPunch:
        bass = (0.18 * math.sin(t * math.pi)).clamp(0.0, 0.28);
        width = (0.05 + 0.06 * t).clamp(0.0, 0.15);
        reverb = (0.08 + 0.20 * math.sin(t * math.pi * 2).abs())
            .clamp(0.0, 0.28);
        break;
    }
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
      for (var i = 0; i < n; i++) {
        final frac = n <= 1 ? 0.5 : i / (n - 1);
        double gain = 0.0;
        switch (activePreset!) {
          case DjSfxPreset.filterOpen:
            // Muffled highs → open (LP open).
            gain = -9.0 * (1.0 - t) * frac;
            break;
          case DjSfxPreset.filterClose:
            // Thin lows → full (HP open).
            gain = -8.0 * (1.0 - t) * (1.0 - frac);
            break;
          case DjSfxPreset.bassDrop:
            // Low bands dip then boom.
            final low = frac < 0.35;
            final punch = math.sin(t * math.pi);
            gain = low ? (-4.0 + 10.0 * punch) : (-2.0 * (1.0 - t) * frac);
            break;
          default:
            gain = 0.0;
        }
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
