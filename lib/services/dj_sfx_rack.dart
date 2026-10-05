import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_effects_bridge.dart';
import '../dj_engine/core/dj_types.dart';

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
  repeat,
  repeatRestart,
  scratch,
  stutter,
  beatRepeat,
  retrigger,
  brake,
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
  int _delayedSfxGen = 0;
  int _trackFxGen = 0;
  bool _trackActionRunning = false;
  List<int> _beatMs = const <int>[];
  List<int> _phraseAnchors = const <int>[];

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
      DjSfxPreset.repeat: 2,
      DjSfxPreset.repeatRestart: high ? 2 : 1,
      DjSfxPreset.scratch: 2,
      DjSfxPreset.stutter: high ? 2 : 1,
      DjSfxPreset.beatRepeat: high ? 2 : 1,
      DjSfxPreset.retrigger: 2,
      DjSfxPreset.brake: 2,
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
    String? outgoingUri,
    List<int> beatMs = const <int>[],
    List<DjSection> sections = const <DjSection>[],
    DjTransitionKind? transitionKind,
  }) async {
    final score =
        energyScore.isFinite ? energyScore.clamp(0.0, 1.0).toDouble() : 0.5;
    activePreset = preset ?? _pickPhraseAwarePreset(energyScore: score, transitionKind: transitionKind, sections: sections, positionMs: outgoing?.position.inMilliseconds ?? 0);
    engaged = true;
    _eqTouched = false;
    _outgoing = outgoing;
    _beatMs = List<int>.from(beatMs)..sort();
    _phraseAnchors = _buildPhraseAnchors(_beatMs);
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
      if (_usesTrackManipulation(activePreset!)) {
        unawaited(_runTrackManipulation(activePreset!));
      }
      if (activePreset == DjSfxPreset.echo || activePreset == DjSfxPreset.dryEcho) {
        unawaited(_playTrackEcho(outgoingUri, score));
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
    ++_delayedSfxGen;
    ++_trackFxGen;
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
      _beatMs = const <int>[];
      _phraseAnchors = const <int>[];
    }
  }

  /// Schedule an actual-track SFX without blocking transition playback.\n  Future<void> engageDelayed({
    required Duration delay,
    required double energyScore,
    DjSfxPreset? preset,
    AndroidEqualizer? equalizerA,
    AndroidEqualizer? equalizerB,
    AudioPlayer? outgoing,
    String? outgoingUri,
    List<int> beatMs = const <int>[],
    List<DjSection> sections = const <DjSection>[],
    DjTransitionKind? transitionKind,
  }) async {
    final gen = ++_delayedSfxGen;
    engaged = true;
    try {
      await Future<void>.delayed(delay);
      if (gen != _delayedSfxGen || !engaged) return;
      await engage(
        energyScore: energyScore,
        preset: preset,
        equalizerA: equalizerA,
        equalizerB: equalizerB,
        outgoing: outgoing,
        outgoingUri: outgoingUri,
        beatMs: beatMs,
        sections: sections,
        transitionKind: transitionKind,
      );
    } catch (e) {
      debugPrint('DjSfxRack.engageDelayed: $e');
    }
  }

  Future<void> _playOneshot(DjSfxPreset preset, double score) async {
    final asset = sampleAssets[preset];
    if (asset == null) return;
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

  Future<void> _playTrackEcho(String? uri, double score) async {
    if (uri == null || uri.trim().isEmpty) return;
    final out = _outgoing;
    if (out == null) return;
    final gen = ++_oneshotGen;
    try {
      final startMs = _musicalEchoStart(out.position.inMilliseconds);
      if (startMs < 0) return;
      final durationMs = out.duration?.inMilliseconds;
      final endMs = math.min(
        durationMs ?? (startMs + 900),
        startMs + 850,
      );
      if (endMs <= startMs + 80) return;

      await _stopOneshot();
      final player = AudioPlayer();
      _oneshot = player;
      final volume = score >= 0.85 ? 0.14 : (score >= 0.7 ? 0.17 : 0.20);
      await player.setVolume(volume.clamp(0.10, 0.24));
      final sourceUri = uri.startsWith('content://') ||
              uri.startsWith('file://') ||
              uri.startsWith('http://') ||
              uri.startsWith('https://')
          ? Uri.parse(uri)
          : Uri.file(uri);
      await player.setAudioSource(
        ClippingAudioSource(
          child: AudioSource.uri(sourceUri),
          start: Duration(milliseconds: startMs),
          end: Duration(milliseconds: endMs),
        ),
      );
      if (gen != _oneshotGen || !engaged) return;
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (gen != _oneshotGen || !engaged) return;
      await player.play();
      Future<void>.delayed(const Duration(milliseconds: 1100), () async {
        if (gen != _oneshotGen) return;
        await _stopOneshot();
      });
    } catch (e) {
      debugPrint('DjSfxRack track echo: $e');
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

  bool _usesTrackManipulation(DjSfxPreset p) =>
      p == DjSfxPreset.repeat ||
      p == DjSfxPreset.repeatRestart ||
      p == DjSfxPreset.scratch ||
      p == DjSfxPreset.stutter ||
      p == DjSfxPreset.beatRepeat ||
      p == DjSfxPreset.retrigger ||
      p == DjSfxPreset.brake;

  /// Manipulates the actual outgoing track using just_audio controls.
  Future<void> _runTrackManipulation(DjSfxPreset preset) async {
    final out = _outgoing;
    if (out == null || _trackActionRunning) return;
    final gen = ++_trackFxGen;
    _trackActionRunning = true;
    try {
      final originalSpeed = _savedOutgoingSpeed.clamp(0.5, 1.5).toDouble();
      final current = out.position.inMilliseconds;
      if (current < 120) return;

      if (preset == DjSfxPreset.repeat || preset == DjSfxPreset.repeatRestart) {
        final anchor = _musicalPhraseAnchor(current);
        final sliceMs = _musicalSliceMs(anchor);
        final repeatAnchor = math.max(0, anchor - sliceMs);
        for (var i = 0; i < 3; i++) {
          if (gen != _trackFxGen || !engaged) return;
          await out.seek(Duration(milliseconds: repeatAnchor));
          await out.setSpeed(originalSpeed);
          await Future<void>.delayed(const Duration(milliseconds: 680));
        }
        if (preset == DjSfxPreset.repeatRestart &&
            gen == _trackFxGen &&
            engaged) {
          await out.seek(Duration.zero);
          await out.setSpeed(originalSpeed);
        }
        return;
      }

      if (preset == DjSfxPreset.stutter || preset == DjSfxPreset.beatRepeat) {
        final anchor = _musicalAnchor(current);
        final beat = _musicalSliceMs(anchor);
        final slice = preset == DjSfxPreset.stutter ? (beat ~/ 2).clamp(120, 700) : beat.clamp(250, 1400);
        final start = math.max(0, anchor - slice);
        final count = preset == DjSfxPreset.stutter ? 5 : 4;
        for (var i = 0; i < count; i++) {
          if (gen != _trackFxGen || !engaged) return;
          await out.seek(Duration(milliseconds: start));
          await out.setSpeed(originalSpeed);
          await Future<void>.delayed(Duration(milliseconds: slice));
        }
        return;
      }

      if (preset == DjSfxPreset.retrigger) {
        final anchor = _musicalAnchor(current);
        final beat = _musicalSliceMs(anchor);
        final start = math.max(0, anchor - beat);
        for (var i = 0; i < 3; i++) {
          if (gen != _trackFxGen || !engaged) return;
          await out.seek(Duration(milliseconds: start));
          await out.setSpeed(originalSpeed);
          await Future<void>.delayed(Duration(milliseconds: beat.clamp(250, 1400)));
        }
        return;
      }

      if (preset == DjSfxPreset.brake) {
        for (final multiplier in <double>[0.94, 0.82, 0.70, 0.58, 0.50]) {
          if (gen != _trackFxGen || !engaged) return;
          await out.setSpeed((originalSpeed * multiplier).clamp(0.5, 1.5));
          await Future<void>.delayed(const Duration(milliseconds: 110));
        }
        if (gen == _trackFxGen && engaged) await out.setSpeed(originalSpeed);
        return;
      }
      final center = _musicalPhraseAnchor(current);
      const strokes = <int>[120, -100, 150, -130, 80];
      for (final delta in strokes) {
        if (gen != _trackFxGen || !engaged) return;
        final target = math.max(0, center + delta);
        await out.seek(Duration(milliseconds: target));
        await out.setSpeed(
          delta >= 0 ? originalSpeed * 1.55 : originalSpeed * 0.62,
        );
        await Future<void>.delayed(const Duration(milliseconds: 115));
      }
      if (gen == _trackFxGen) await out.setSpeed(originalSpeed);
    } catch (e) {
      debugPrint('DjSfxRack track manipulation $preset: $e');
    } finally {
      if (gen == _trackFxGen) _trackActionRunning = false;
    }
  }

  int _musicalAnchor(int currentMs) {
    if (_beatMs.isEmpty) return math.max(0, currentMs - 350);
    var best = _beatMs.first;
    var distance = (best - currentMs).abs();
    for (final beat in _beatMs) {
      if (beat > currentMs + 900) break;
      final d = (beat - currentMs).abs();
      if (d < distance) { best = beat; distance = d; }
    }
    return math.max(0, best);
  }

  int _musicalSliceMs(int anchorMs) {
    final i = _beatMs.indexOf(anchorMs);
    if (i < 0 || i + 1 >= _beatMs.length) return 700;
    return (_beatMs[i + 1] - _beatMs[i]).clamp(250, 1400);
  }

  DjSfxPreset _pickPhraseAwarePreset({
    required double energyScore,
    required DjTransitionKind? transitionKind,
    required List<DjSection> sections,
    required int positionMs,
  }) {
    DjSection? section;
    for (final s in sections) {
      if (positionMs >= s.startMs && positionMs < s.endMs) {
        section = s;
        break;
      }
    }
    switch (transitionKind) {
      case DjTransitionKind.breakdownDrop:
        return energyScore >= 0.72 ? DjSfxPreset.impact : DjSfxPreset.whoosh;
      case DjTransitionKind.phraseBlend:
        return section?.type == DjSectionType.breakdown
            ? DjSfxPreset.repeatRestart
            : DjSfxPreset.repeat;
      case DjTransitionKind.beatBlend:
        return energyScore >= 0.86 ? DjSfxPreset.stutter : (energyScore >= 0.78 ? DjSfxPreset.scratch : DjSfxPreset.repeat);
      case DjTransitionKind.energyBridge:
        return energyScore >= 0.75 ? DjSfxPreset.whoosh : DjSfxPreset.echo;
      case DjTransitionKind.outroIntro:
        return energyScore >= 0.82 ? DjSfxPreset.brake : (energyScore >= 0.75 ? DjSfxPreset.filterClose : DjSfxPreset.echo);
      case DjTransitionKind.safeCrossfade:
        return DjSfxPreset.dryEcho;
      case null:
        break;
    }
    if (section?.type == DjSectionType.build ||
        section?.type == DjSectionType.chorus ||
        section?.type == DjSectionType.drop) {
      return energyScore >= 0.86 ? DjSfxPreset.stutter : (energyScore >= 0.8 ? DjSfxPreset.scratch : DjSfxPreset.echo);
    }
    return pickRandom(energyScore: energyScore);
  }

  List<int> _buildPhraseAnchors(List<int> beats) {
    if (beats.length < 16) return const <int>[];
    final result = <int>[];
    for (var i = 0; i < beats.length; i += 16) {
      result.add(beats[i]);
    }
    return result;
  }

  int _musicalPhraseAnchor(int currentMs) {
    if (_phraseAnchors.isEmpty) return _musicalAnchor(currentMs);
    var best = _phraseAnchors.first;
    var distance = (best - currentMs).abs();
    for (final anchor in _phraseAnchors) {
      if (anchor > currentMs + 1400) break;
      final d = (anchor - currentMs).abs();
      if (d < distance) {
        best = anchor;
        distance = d;
      }
    }
    return math.max(0, best);
  }

  int _musicalEchoStart(int currentMs) {
    if (_beatMs.length < 2) return math.max(0, currentMs - 850);
    final anchor = _musicalAnchor(currentMs);
    final i = _beatMs.indexOf(anchor);
    if (i <= 0) return math.max(0, anchor - 850);
    final beatDuration = (_beatMs[i] - _beatMs[i - 1]).clamp(250, 1400);
    return math.max(0, anchor - beatDuration);
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
        case DjSfxPreset.repeat:
        case DjSfxPreset.repeatRestart:
        case DjSfxPreset.scratch:
          width = (0.05 * env).clamp(0.0, 0.10);
          reverb = (0.06 * env).clamp(0.0, 0.12);
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
