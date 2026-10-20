#!/usr/bin/env python3
"""Generate synthetic DJ transition one-shots and wire them into DjSfxRack."""
from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SFX_DIR = ROOT / 'assets' / 'sfx'
PUBSPEC = ROOT / 'pubspec.yaml'
RACK = ROOT / 'lib' / 'services' / 'dj_sfx_rack.dart'
MUSIC = ROOT / 'lib' / 'providers' / 'music_provider.dart'

SR = 44100


def write_wav(path: Path, samples: list[float], amp: float = 0.55) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = b''.join(
        struct.pack('<h', int(max(-1.0, min(1.0, s * amp)) * 32767))
        for s in samples
    )
    with wave.open(str(path), 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(frames)


def env_adsr(n: int, a: float, d: float, s: float, r: float) -> list[float]:
    out = []
    na, nd, nr = int(n * a), int(n * d), int(n * r)
    ns = max(0, n - na - nd - nr)
    for i in range(n):
        if i < na and na:
            out.append(i / na)
        elif i < na + nd and nd:
            t = (i - na) / nd
            out.append(1.0 - t * (1.0 - s))
        elif i < na + nd + ns:
            out.append(s)
        else:
            t = (i - na - nd - ns) / max(1, nr)
            out.append(s * (1.0 - t))
    return out


def tone(freq: float, n: int, phase0: float = 0.0) -> list[float]:
    return [math.sin(phase0 + 2 * math.pi * freq * i / SR) for i in range(n)]


def noise(n: int, seed: int = 1) -> list[float]:
    # Simple LCG noise, deterministic.
    x = seed & 0xFFFFFFFF
    out = []
    for _ in range(n):
        x = (1664525 * x + 1013904223) & 0xFFFFFFFF
        out.append((x / 0xFFFFFFFF) * 2.0 - 1.0)
    return out


def gen_airhorn() -> list[float]:
    n = int(SR * 0.55)
    e = env_adsr(n, 0.05, 0.1, 0.75, 0.35)
    out = []
    for i in range(n):
        # Classic dual-tone siren rise
        f = 380 + 220 * (i / n)
        s = 0.55 * math.sin(2 * math.pi * f * i / SR)
        s += 0.35 * math.sin(2 * math.pi * (f * 1.5) * i / SR)
        out.append(s * e[i])
    return out


def gen_gunshot() -> list[float]:
    n = int(SR * 0.28)
    e = [math.exp(-8.0 * i / n) for i in range(n)]
    nz = noise(n, seed=42)
    out = []
    for i in range(n):
        # Click + noise tail
        click = math.sin(2 * math.pi * 180 * i / SR) * math.exp(-40 * i / n)
        out.append((0.35 * click + 0.65 * nz[i]) * e[i])
    return out


def gen_vinyl_scratch() -> list[float]:
    n = int(SR * 0.4)
    e = env_adsr(n, 0.02, 0.15, 0.5, 0.35)
    nz = noise(n, seed=7)
    out = []
    for i in range(n):
        # Filtered-ish noise with pitch wiggle
        f = 900 + 600 * math.sin(2 * math.pi * 6 * i / SR)
        tone_s = math.sin(2 * math.pi * f * i / SR)
        out.append((0.55 * nz[i] + 0.45 * tone_s) * e[i] * 0.7)
    return out


def gen_rewind() -> list[float]:
    n = int(SR * 0.5)
    e = env_adsr(n, 0.02, 0.1, 0.7, 0.3)
    out = []
    for i in range(n):
        # Descending chirp
        f = 1400 - 1100 * (i / n)
        s = math.sin(2 * math.pi * f * i / SR)
        s += 0.3 * math.sin(2 * math.pi * (f * 0.5) * i / SR)
        out.append(s * e[i])
    return out


def gen_whoosh() -> list[float]:
    n = int(SR * 0.45)
    e = env_adsr(n, 0.15, 0.2, 0.55, 0.3)
    nz = noise(n, seed=99)
    out = []
    for i in range(n):
        # High-pass-ish: difference of noise with simple lag
        lag = nz[i - 3] if i >= 3 else 0.0
        s = (nz[i] - lag) * 0.7
        out.append(s * e[i])
    return out


def gen_impact() -> list[float]:
    n = int(SR * 0.18)
    e = [math.exp(-12.0 * i / n) for i in range(n)]
    out = []
    for i in range(n):
        s = math.sin(2 * math.pi * 90 * i / SR) * 0.4
        s += math.sin(2 * math.pi * 220 * i / SR) * 0.25
        s += noise(1, seed=i + 3)[0] * 0.2
        out.append(s * e[i])
    return out


def gen_samples() -> dict[str, Path]:
    specs = {
        'airhorn.wav': gen_airhorn,
        'gunshot.wav': gen_gunshot,
        'vinyl_scratch.wav': gen_vinyl_scratch,
        'rewind.wav': gen_rewind,
        'whoosh.wav': gen_whoosh,
        'impact.wav': gen_impact,
    }
    paths = {}
    for name, fn in specs.items():
        p = SFX_DIR / name
        write_wav(p, fn(), amp=0.5)
        paths[name] = p
        print('wrote', p, p.stat().st_size, 'bytes')
    return paths


RACK_CONTENT = r'''import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_effects_bridge.dart';

/// Transition SFX — engine FX + optional one-shot sample packs.
enum DjSfxPreset {
  echo,
  vinylStop,
  rewind,
  filterOpen,
  filterClose,
  tightGlue,
  dryEcho,
  airHorn,
  gunshot,
  vinylScratch,
  whoosh,
  impact,
}

class DjSfxRack {
  DjSfxRack({math.Random? random}) : _rng = random ?? math.Random();

  final math.Random _rng;
  DjSfxPreset? activePreset;
  bool engaged = false;
  List<double>? _savedEqGains;
  bool _eqTouched = false;
  double _savedOutgoingSpeed = 1.0;
  AudioPlayer? _outgoing;
  AudioPlayer? _oneshot;
  int _oneshotGen = 0;

  static const presets = DjSfxPreset.values;

  /// Asset paths for sample-based presets.
  static const sampleAssets = <DjSfxPreset, String>{
    DjSfxPreset.airHorn: 'assets/sfx/airhorn.wav',
    DjSfxPreset.gunshot: 'assets/sfx/gunshot.wav',
    DjSfxPreset.vinylScratch: 'assets/sfx/vinyl_scratch.wav',
    DjSfxPreset.rewind: 'assets/sfx/rewind.wav',
    DjSfxPreset.whoosh: 'assets/sfx/whoosh.wav',
    DjSfxPreset.impact: 'assets/sfx/impact.wav',
  };

  bool _isSample(DjSfxPreset p) => sampleAssets.containsKey(p);

  DjSfxPreset pickRandom({double energyScore = 0.5}) {
    final high = energyScore >= 0.75;
    // Mix character FX + samples; avoid stacking loudness.
    final weights = <DjSfxPreset, int>{
      DjSfxPreset.echo: 2,
      DjSfxPreset.vinylStop: high ? 2 : 2,
      DjSfxPreset.rewind: 2,
      DjSfxPreset.filterOpen: high ? 2 : 2,
      DjSfxPreset.filterClose: 2,
      DjSfxPreset.tightGlue: 2,
      DjSfxPreset.dryEcho: 1,
      DjSfxPreset.airHorn: high ? 3 : 2,
      DjSfxPreset.gunshot: high ? 2 : 1,
      DjSfxPreset.vinylScratch: 2,
      DjSfxPreset.whoosh: 2,
      DjSfxPreset.impact: high ? 2 : 1,
    };
    final total = weights.values.fold<int>(0, (a, b) => a + b);
    var r = _rng.nextInt(total);
    for (final e in weights.entries) {
      r -= e.value;
      if (r < 0) return e.key;
    }
    return DjSfxPreset.echo;
  }

  Future<void> engage({
    required double energyScore,
    DjSfxPreset? preset,
    AndroidEqualizer? equalizerA,
    AndroidEqualizer? equalizerB,
    AudioPlayer? outgoing,
  }) async {
    final score =
        energyScore.isFinite ? energyScore.clamp(0.0, 1.0).toDouble() : 0.5;
    activePreset = preset ?? pickRandom(energyScore: score);
    engaged = true;
    _eqTouched = false;
    _outgoing = outgoing;
    _savedOutgoingSpeed = 1.0;
    try {
      if (outgoing != null) {
        _savedOutgoingSpeed = outgoing.speed;
      }
    } catch (_) {}

    try {
      await _snapshotEq(equalizerA);
      await AudioEffectsBridge.setBassBoost(0.0);
      await _applyFxAt(0.0, score);
      if (_usesEq(activePreset!)) {
        await _applyEqAt(equalizerA, 0.0);
        await _applyEqAt(equalizerB, 0.0);
        _eqTouched = true;
      }
      // Fire one-shot early so it sits over the outgoing fade.
      if (_isSample(activePreset!)) {
        unawaited(_playOneshot(activePreset!, score));
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
    AudioPlayer? outgoing,
  }) async {
    if (!engaged || activePreset == null) return;
    final score =
        energyScore.isFinite ? energyScore.clamp(0.0, 1.0).toDouble() : 0.5;
    if (outgoing != null) _outgoing = outgoing;
    try {
      await _applyFxAt(t, score);
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
      final out = _outgoing;
      if (out != null) {
        try {
          await out.setSpeed(_savedOutgoingSpeed.clamp(0.5, 1.5));
        } catch (_) {
          try {
            await out.setSpeed(1.0);
          } catch (_) {}
        }
      }
      await _stopOneshot();
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
      _outgoing = null;
      _savedOutgoingSpeed = 1.0;
    }
  }

  Future<void> _playOneshot(DjSfxPreset preset, double score) async {
    final asset = sampleAssets[preset];
    if (asset == None) return;
    final gen = ++_oneshotGen;
    try {
      await _stopOneshot();
      final player = AudioPlayer();
      _oneshot = player;
      // Keep one-shots under the music — never dominate.
      final vol = (score >= 0.85 ? 0.28 : (score >= 0.7 ? 0.34 : 0.40))
          .clamp(0.2, 0.45);
      await player.setVolume(vol);
      await player.setAudioSource(AudioSource.asset(asset));
      if (gen != _oneshotGen) return;
      await player.play();
      // Auto-stop after max sample length.
      Future<void>.delayed(const Duration(milliseconds: 900), () async {
        if (gen != _oneshotGen) return;
        await _stopOneshot();
      });
    } catch (e) {
      debugPrint('DjSfxRack oneshot $preset: $e');
    }
  }

  Future<void> _stopOneshot() async {
    final p = _oneshot;
    _oneshot = null;
    if (p == null) return;
    try {
      await p.stop();
    } catch (_) {}
    try {
      await p.dispose();
    } catch (_) {}
  }

  bool _usesEq(DjSfxPreset p) =>
      p == DjSfxPreset.filterOpen || p == DjSfxPreset.filterClose;

  bool _usesSpeed(DjSfxPreset p) =>
      p == DjSfxPreset.vinylStop ||
      (p == DjSfxPreset.rewind && !_isSample(p));

  double _envelope(double t) {
    if (t <= 0) return 0.0;
    if (t < 0.15) return (t / 0.15).clamp(0.0, 1.0);
    if (t <= 1.0) return 1.0;
    return ((1.55 - t) / 0.55).clamp(0.0, 1.0);
  }

  Future<void> _applyFxAt(double t, double score) async {
    final p = activePreset ?? DjSfxPreset.echo;
    final env = _envelope(t);
    final x = t.clamp(0.0, 1.0);
    await AudioEffectsBridge.setBassBoost(0.0);

    // Sample presets: light reverb bed only (the WAV is the character).
    double width = 0.0;
    double reverb = 0.0;
    if (_isSample(p)) {
      width = (0.04 * env).clamp(0.0, 0.08);
      reverb = (0.10 * env).clamp(0.0, 0.16);
    } else {
      switch (p) {
        case DjSfxPreset.echo:
          width = (0.04 + 0.10 * x).clamp(0.0, 0.18);
          reverb = (0.22 + 0.28 * math.sin(x * math.pi)).clamp(0.12, 0.48);
          break;
        case DjSfxPreset.vinylStop:
          width = (0.06 * (1.0 - x)).clamp(0.0, 0.10);
          reverb = (0.08 + 0.12 * x).clamp(0.04, 0.22);
          break;
        case DjSfxPreset.rewind:
          width = (0.05 * (1.0 - x)).clamp(0.0, 0.10);
          reverb = (0.08 + 0.10 * x).clamp(0.04, 0.20);
          break;
        case DjSfxPreset.filterOpen:
        case DjSfxPreset.filterClose:
          width = (0.05 + 0.08 * x).clamp(0.0, 0.16);
          reverb = (0.08 + 0.10 * math.sin(x * math.pi)).clamp(0.04, 0.22);
          break;
        case DjSfxPreset.tightGlue:
          width = (0.04 + 0.06 * x).clamp(0.0, 0.12);
          reverb = (0.14 + 0.16 * math.sin(x * math.pi)).clamp(0.08, 0.32);
          break;
        case DjSfxPreset.dryEcho:
          width = 0.03;
          reverb = (0.16 * math.sin(x * math.pi)).clamp(0.0, 0.22);
          break;
        default:
          break;
      }
    }
    final energyScale = score >= 0.85 ? 0.7 : (score >= 0.7 ? 0.85 : 1.0);
    width = (width * env * energyScale).clamp(0.0, 0.28);
    reverb = (reverb * env * energyScale).clamp(0.0, 0.48);
    await AudioEffectsBridge.setVirtualizer(width);
    await AudioEffectsBridge.setReverb(reverb);

    if (_usesSpeed(p) && _outgoing != null) {
      final speed = p == DjSfxPreset.vinylStop
          ? (1.0 - 0.45 * x).clamp(0.55, 1.0)
          : (1.0 - 0.55 * x).clamp(0.45, 1.0);
      try {
        await _outgoing!.setSpeed(speed);
      } catch (_) {}
    }
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
            gain = -6.0 * (1.0 - x) * frac;
            break;
          case DjSfxPreset.filterClose:
            gain = -5.5 * (1.0 - x) * (1.0 - frac);
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

// Local helper — avoid importing dart:async only for unawaited in some SDK configs.
void unawaited(Future<void> f) {
  f.catchError((_) {});
}
'''

# Fix the None typo - in Dart it should be null. I wrote `if (asset == None)` by mistake.
RACK_CONTENT = RACK_CONTENT.replace('if (asset == None) return;', 'if (asset == null) return;')


def patch_pubspec() -> None:
    t = PUBSPEC.read_text()
    if 'assets/sfx/' in t:
        print('skip pubspec already has sfx')
        return
    old = '''  assets:
    - assets/branding/resonate_in_app_logo.png
    - assets/branding/resonate_app_icon.png'''
    new = '''  assets:
    - assets/branding/resonate_in_app_logo.png
    - assets/branding/resonate_app_icon.png
    - assets/sfx/'''
    if old not in t:
        print('skip pubspec pattern')
        return
    PUBSPEC.write_text(t.replace(old, new, 1))
    print('ok pubspec')


def main() -> None:
    gen_samples()
    RACK.write_text(RACK_CONTENT)
    print('ok wrote rack')
    patch_pubspec()
    print('sample pack done')


if __name__ == '__main__':
    main()
