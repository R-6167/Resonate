import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/eq_lean_store.dart';
import '../services/resonate_dsp_pipeline.dart';
import 'music_provider.dart';
import 'bluetooth_provider.dart';

/// One band in the app's fixed 10-band software curve (source of truth).
class StudioBand {
  final int index;
  final double frequencyHz;
  final String label;
  double gainDb;

  StudioBand({
    required this.index,
    required this.frequencyHz,
    required this.label,
    this.gainDb = 0.0,
  });
}

/// Hardware band exposed by AndroidEqualizer (device-dependent count).
class EqualizerBandState {
  final int index;
  final double centerFrequency;
  final double minGain;
  final double maxGain;
  double gain;

  EqualizerBandState({
    required this.index,
    required this.centerFrequency,
    required this.minGain,
    required this.maxGain,
    required this.gain,
  });
}

class EqualizerPreset {
  final String name;
  final String category;
  final List<double> gains; // 10 values, dB
  final bool isCustom;

  const EqualizerPreset({
    required this.name,
    required this.category,
    required this.gains,
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'category': category,
        'gains': gains,
        'isCustom': isCustom,
      };

  factory EqualizerPreset.fromJson(Map<String, dynamic> json) => EqualizerPreset(
        name: json['name'] as String? ?? 'Custom',
        category: json['category'] as String? ?? 'Custom',
        gains: ((json['gains'] as List?) ?? const []).map((e) => (e as num).toDouble()).toList(),
        isCustom: json['isCustom'] as bool? ?? true,
      );
}

/// Software 10-band equalizer model.
///
/// Android's [AndroidEqualizer] only exposes as many bands as the device DSP
/// provides (often 5). This provider always owns a fixed 10-band studio curve
/// and maps it onto hardware bands. Preamp is applied via
/// [AndroidLoudnessEnhancer] when available.
class EqualizerProvider extends ChangeNotifier {
  AndroidEqualizer? _androidEqualizer;
  AndroidLoudnessEnhancer? _loudnessEnhancer;

  final List<StudioBand> studioBands = [];
  final List<EqualizerBandState> bandStates = []; // hardware mirror
  final Map<String, double> bands = {}; // label → gain for legacy callers

  bool isEnabled = true;
  String preset = 'Flat';
  double preamp = 0.0;
  String? activeSongId;
  List<EqualizerPreset> customPresets = [];

  /// 31-band studio model (ISO-ish centers). Mapped onto device hardware EQ;
  /// true per-band software DSP is a later native step.
  static const List<double> studioFrequencies = [
    20, 25, 32, 40, 50, 63, 80, 100, 125, 160,
    200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600,
    2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000,
  ];

  static const double studioMinDb = -12.0;
  static const double studioMaxDb = 12.0;

  /// Legacy 10-band centers used by older preset definitions.
  static const List<double> _legacy10Hz = [
    31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
  ];

  /// Interpolate a short gain list onto the current studio frequency grid.
  static List<double> expandGainsToStudio(List<double> gains) {
    if (gains.length >= studioFrequencies.length) {
      return gains.take(studioFrequencies.length).map((g) => g.clamp(studioMinDb, studioMaxDb).toDouble()).toList();
    }
    if (gains.isEmpty) {
      return List<double>.filled(studioFrequencies.length, 0.0);
    }
    final srcHz = gains.length == 10 ? _legacy10Hz : [
      for (var i = 0; i < gains.length; i++)
        studioFrequencies.first +
            (studioFrequencies.last - studioFrequencies.first) *
                (i / (gains.length - 1).clamp(1, 1000)),
    ];
    double at(double hz) {
      if (hz <= srcHz.first) return gains.first;
      if (hz >= srcHz.last) return gains.last;
      for (var i = 0; i < srcHz.length - 1; i++) {
        if (hz >= srcHz[i] && hz <= srcHz[i + 1]) {
          final t = (hz - srcHz[i]) / (srcHz[i + 1] - srcHz[i]);
          return gains[i] + (gains[i + 1] - gains[i]) * t;
        }
      }
      return 0.0;
    }
    return [for (final hz in studioFrequencies) at(hz).clamp(studioMinDb, studioMaxDb).toDouble()];
  }

  MusicProvider? _music;
  BluetoothProvider? _bluetooth;
  bool _learnedEqEnabled = false;
  bool _btProfilesEnabled = false;
  String? _lastLeanSongId;
  BluetoothAudioContext? _lastBtContext;
  final Map<String, String> _btProfilePresets = {};
  final ResonateDspPipeline _dspPipeline = ResonateDspPipeline();

  EqualizerProvider({
    AndroidEqualizer? equalizer,
    AndroidLoudnessEnhancer? loudnessEnhancer,
    MusicProvider? music,
    BluetoothProvider? bluetooth,
  })  : _androidEqualizer = equalizer,
        _loudnessEnhancer = loudnessEnhancer,
        _music = music,
        _bluetooth = bluetooth {
    _initStudioBands();
    _initialize();
    _music?.addListener(_onMusicChanged);
    _bluetooth?.addListener(_onBluetoothChanged);
    _music?.onAndroidSession = (id) {
      unawaited(attachNativeSession(id));
    };
  }

  bool get learnedEqEnabled => _learnedEqEnabled;

  Future<void> setLearnedEqEnabled(bool value) async {
    _learnedEqEnabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('equalizer_learned_eq', value);
    } catch (_) {}
    if (value) unawaited(_applyLeanForCurrent());
    notifyListeners();
  }

  Future<void> rememberLeanForCurrent({bool forArtist = false}) async {
    final song = _music?.currentSong;
    if (song == null) return;
    if (forArtist) {
      await EqLeanStore.rememberArtist(song.artist, preset);
    } else {
      await EqLeanStore.rememberSong(song.id, preset);
    }
    notifyListeners();
  }

  void _onMusicChanged() {
    final id = _music?.currentSong?.id;
    if (id == null || id == _lastLeanSongId) return;
    _lastLeanSongId = id;
    unawaited(_applyLeanForCurrent());
  }

  Future<void> _applyLeanForCurrent() async {
    final song = _music?.currentSong;
    String? lean;
    if (_learnedEqEnabled && song != null) {
      lean = await EqLeanStore.presetFor(songId: song.id, artist: song.artist);
    }
    lean ??= _btProfilePresetName();
    if (lean == null || lean == preset) return;
    await applyPreset(lean, persistSelection: false);
  }

  String? _btProfilePresetName() {
    if (!_btProfilesEnabled || _bluetooth == null) return null;
    if (!_bluetooth!.bluetoothConnected) return null;
    final key = _bluetooth!.audioContext.name;
    return _btProfilePresets[key];
  }

  void _onBluetoothChanged() {
    final ctx = _bluetooth?.audioContext;
    if (ctx == _lastBtContext) return;
    _lastBtContext = ctx;
    unawaited(_applyLeanForCurrent());
  }

  bool get btProfilesEnabled => _btProfilesEnabled;

  Future<void> setBtProfilesEnabled(bool value) async {
    _btProfilesEnabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('equalizer_bt_profiles', value);
    } catch (_) {}
    if (value) unawaited(_applyLeanForCurrent());
    notifyListeners();
  }

  String? btPresetFor(BluetoothAudioContext ctx) => _btProfilePresets[ctx.name];

  Future<void> setBtPreset(BluetoothAudioContext ctx, String presetName) async {
    _btProfilePresets[ctx.name] = presetName;
    await _saveBtProfiles();
    if (_btProfilesEnabled && _bluetooth?.audioContext == ctx) {
      await applyPreset(presetName, persistSelection: false);
    }
    notifyListeners();
  }

  Future<void> _saveBtProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('equalizer_bt_profiles_map', jsonEncode(_btProfilePresets));
    } catch (_) {}
  }

  Future<void> _loadBtProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _btProfilesEnabled = prefs.getBool('equalizer_bt_profiles') ?? false;
      final raw = prefs.getString('equalizer_bt_profiles_map');
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _btProfilePresets
            ..clear()
            ..addAll(decoded.map((k, v) => MapEntry(k.toString(), v.toString())));
        }
      }
    } catch (_) {}
  }

  bool get isAvailable => true; // software curve always available
  bool get hasHardwareEq => _androidEqualizer != null && bandStates.isNotEmpty;
  int get hardwareBandCount => bandStates.length;
  int get studioBandCount => studioBands.length;

  /// Points for drawing a smooth response curve (normalized x 0–1, gain dB).
  List<Offset> responseCurvePoints({int samples = 64}) {
    final pts = <Offset>[];
    if (studioBands.isEmpty) return pts;
    for (var i = 0; i < samples; i++) {
      final t = i / (samples - 1);
      // Log-ish x across studio range
      final minF = studioFrequencies.first;
      final maxF = studioFrequencies.last;
      final hz = minF * math.pow(maxF / minF, t);
      final db = _interpolatedGainAt(hz.toDouble());
      pts.add(Offset(t, db));
    }
    return pts;
  }

  double _interpolatedGainAt(double hz) {
    if (studioBands.isEmpty) return 0;
    if (hz <= studioBands.first.frequencyHz) return studioBands.first.gainDb;
    if (hz >= studioBands.last.frequencyHz) return studioBands.last.gainDb;
    for (var i = 0; i < studioBands.length - 1; i++) {
      final a = studioBands[i];
      final b = studioBands[i + 1];
      if (hz >= a.frequencyHz && hz <= b.frequencyHz) {
        final t = (math.log(hz) - math.log(a.frequencyHz)) /
            (math.log(b.frequencyHz) - math.log(a.frequencyHz));
        return a.gainDb + (b.gainDb - a.gainDb) * t;
      }
    }
    return 0;
  }

  void _initStudioBands() {
    studioBands
      ..clear()
      ..addAll(List.generate(studioFrequencies.length, (i) {
        final hz = studioFrequencies[i];
        return StudioBand(
          index: i,
          frequencyHz: hz,
          label: _labelForFrequency(hz),
          gainDb: 0,
        );
      }));
  }

  static final List<EqualizerPreset> builtInPresets = [
    const EqualizerPreset(name: 'Flat', category: 'Utility', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    const EqualizerPreset(name: 'Soft', category: 'Utility', gains: [2, 1, 0, 0, -1, -1, 0, 1, 2, 2]),
    const EqualizerPreset(name: 'Warm', category: 'Utility', gains: [3, 2, 1, 1, 0, -1, -1, -1, 0, 1]),
    const EqualizerPreset(name: 'Bright', category: 'Utility', gains: [-1, -1, 0, 0, 1, 2, 3, 4, 4, 4]),
    const EqualizerPreset(name: 'Balanced', category: 'Utility', gains: [2, 1, 0, 1, 2, 1, 0, 1, 2, 2]),
    const EqualizerPreset(name: 'Bass Boost', category: 'Bass', gains: [8, 7, 5, 3, 1, 0, 0, 0, 0, 0]),
    const EqualizerPreset(name: 'Deep Bass', category: 'Bass', gains: [9, 8, 6, 3, 0, -1, -1, 0, 0, 0]),
    const EqualizerPreset(name: 'Sub Focus', category: 'Bass', gains: [10, 9, 5, 1, -1, -2, -1, 0, 0, 0]),
    const EqualizerPreset(name: 'Bass Extreme', category: 'Bass', gains: [11, 10, 7, 2, 0, -2, -1, 0, 1, 1]),
    const EqualizerPreset(name: 'Hip-Hop Bass', category: 'Bass', gains: [9, 7, 4, 1, 0, 1, 2, 1, 1, 2]),
    const EqualizerPreset(name: 'Treble Boost', category: 'Treble', gains: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
    const EqualizerPreset(name: 'Air', category: 'Treble', gains: [0, 0, 0, 0, 0, 0, 1, 2, 4, 5]),
    const EqualizerPreset(name: 'Vocal', category: 'Voice', gains: [-2, -1, 0, 2, 4, 3, 2, 1, 0, -1]),
    const EqualizerPreset(name: 'Vocal Focus', category: 'Voice', gains: [-3, -2, 0, 3, 5, 4, 2, 1, -1, -2]),
    const EqualizerPreset(name: 'Podcast', category: 'Voice', gains: [-3, -2, 1, 4, 5, 3, 0, -2, -3, -4]),
    const EqualizerPreset(name: 'Spoken Word', category: 'Voice', gains: [-2, -1, 1, 3, 4, 3, 1, -1, -2, -3]),
    const EqualizerPreset(name: 'Rock', category: 'Genre', gains: [4, 3, 1, 0, -1, 1, 3, 4, 4, 3]),
    const EqualizerPreset(name: 'Pop', category: 'Genre', gains: [-1, 1, 3, 4, 3, 1, 0, 1, 2, 2]),
    const EqualizerPreset(name: 'Jazz', category: 'Genre', gains: [3, 2, 0, 1, -1, -1, 0, 1, 2, 3]),
    const EqualizerPreset(name: 'Classical', category: 'Genre', gains: [3, 2, 1, 0, -1, -1, 0, 2, 3, 4]),
    const EqualizerPreset(name: 'Electronic', category: 'Genre', gains: [4, 3, 1, 0, -2, 1, 3, 2, 3, 4]),
    const EqualizerPreset(name: 'Acoustic', category: 'Genre', gains: [2, 1, 0, 1, 2, 2, 1, 2, 3, 2]),
    const EqualizerPreset(name: 'Hip-Hop', category: 'Genre', gains: [8, 6, 3, 0, -1, 0, 1, 2, 2, 2]),
    const EqualizerPreset(name: 'R&B', category: 'Genre', gains: [4, 3, 1, 1, 2, 2, 1, 2, 3, 3]),
    const EqualizerPreset(name: 'Metal', category: 'Genre', gains: [4, 3, 0, -2, -1, 2, 4, 3, 2, 2]),
    const EqualizerPreset(name: 'Dance', category: 'Genre', gains: [5, 4, 2, 0, -1, 1, 2, 3, 4, 4]),
    const EqualizerPreset(name: 'Latin', category: 'Genre', gains: [3, 2, 0, 1, 2, 2, 1, 2, 3, 3]),
    const EqualizerPreset(name: 'Reggae', category: 'Genre', gains: [4, 3, 0, -1, 0, 2, 3, 2, 1, 1]),
    const EqualizerPreset(name: 'Live', category: 'Space', gains: [-2, 0, 2, 3, 2, 1, 1, 2, 3, 2]),
    const EqualizerPreset(name: 'Club', category: 'Space', gains: [5, 4, 2, 0, -2, 0, 1, 2, 3, 3]),
    const EqualizerPreset(name: 'Headphones', category: 'Space', gains: [3, 2, 0, 1, 2, 1, 0, 2, 3, 4]),
    const EqualizerPreset(name: 'Car', category: 'Space', gains: [4, 3, 1, 0, 0, 1, 2, 3, 3, 2]),
  ];

  List<EqualizerPreset> get allPresets => [...builtInPresets, ...customPresets];

  List<String> get categories {
    final set = <String>{};
    for (final p in allPresets) {
      set.add(p.category);
    }
    return set.toList();
  }

  List<EqualizerPreset> presetsInCategory(String category) =>
      allPresets.where((p) => p.category == category).toList();

  /// Re-bind when MusicProvider switches active engine (A/B).
  void attachHardware({
    AndroidEqualizer? equalizer,
    AndroidLoudnessEnhancer? loudnessEnhancer,
  }) {
    _androidEqualizer = equalizer;
    _loudnessEnhancer = loudnessEnhancer;
    unawaited(_reloadHardwareAndApply());
  }

  Future<void> _reloadHardwareAndApply() async {
    await _loadHardwareBands();
    await _pushToHardware();
    await _applyPreamp();
    notifyListeners();
  }

  Future<void> _initialize() async {
    try {
      await _loadHardwareBands();
      final prefs = await SharedPreferences.getInstance();
      isEnabled = prefs.getBool('equalizer_enabled') ?? true;
      preset = prefs.getString('equalizer_preset') ?? 'Flat';
      await _loadBtProfiles();
      preamp = prefs.getDouble('equalizer_preamp') ?? 0.0;
      await _loadCustomPresets(prefs);

      // Restore studio curve from prefs if present.
      var restoredStudio = false;
      for (var i = 0; i < studioBands.length; i++) {
        final v = prefs.getDouble('eq_studio_band_$i');
        if (v != null) {
          studioBands[i].gainDb = v.clamp(studioMinDb, studioMaxDb);
          restoredStudio = true;
        }
      }
      if (!restoredStudio) {
        // Migrate old hardware-only saves via preset name.
        final match = allPresets.where((p) => p.name == preset);
        if (match.isNotEmpty) {
          _applyStudioGains(match.first.gains);
        }
      }

      for (final b in studioBands) {
        bands[b.label] = b.gainDb;
      }

      await _androidEqualizer?.setEnabled(isEnabled);
      await _pushToHardware();
      await _applyPreamp();
      notifyListeners();
    } catch (e) {
      debugPrint('Equalizer initialization failed: $e');
    }
  }

  Future<void> _loadHardwareBands() async {
    bandStates.clear();
    if (_androidEqualizer == null) return;
    try {
      final parameters = await _androidEqualizer!.parameters;
      bandStates.addAll(parameters.bands.map(
        (band) => EqualizerBandState(
          index: band.index,
          centerFrequency: band.centerFrequency,
          minGain: parameters.minDecibels,
          maxGain: parameters.maxDecibels,
          gain: band.gain,
        ),
      ));
    } catch (e) {
      debugPrint('hardware EQ load failed: $e');
    }
  }

  String _labelForFrequency(double hz) {
    if (hz >= 1000) {
      final khz = hz / 1000.0;
      return khz >= 10 ? '${khz.toStringAsFixed(0)}kHz' : '${khz.toStringAsFixed(1)}kHz';
    }
    return '${hz.round()}Hz';
  }

  /// Map studio gains through the Resonate DSP engine onto hardware centers.
  /// Uses cascaded peaking response (original Resonate model), not a copy of
  /// another app's curve.
  List<double> mapStudioToHardware(List<double> studioGains) {
    if (bandStates.isEmpty) return const [];
    _dspPipeline.updateStudioGains(studioGains);
    final centers = bandStates.map((b) => b.centerFrequency).toList();
    final targets = _dspPipeline.hardwareTargets(centers);
    return [
      for (var i = 0; i < targets.length; i++)
        targets[i].clamp(bandStates[i].minGain, bandStates[i].maxGain).toDouble(),
    ];
  }

  String get dspEngineId => ResonateNativeDspBridge.available
      ? ResonateNativeDspBridge.engineLabel
      : _dspPipeline.id;
  bool get nativeDspActive => ResonateNativeDspBridge.available;
  int get nativeDspBandCount => ResonateNativeDspBridge.lastBandCount ?? 0;

  Future<void> _pushToHardware() async {
    final studioGains = studioBands.map((b) => b.gainDb).toList();
    final centers = studioBands.map((b) => b.frequencyHz).toList();

    // Stage A: classic Android Equalizer (device band count).
    if (_androidEqualizer != null && bandStates.isNotEmpty) {
      final mapped = mapStudioToHardware(studioGains);
      try {
        final parameters = await _androidEqualizer!.parameters;
        for (var i = 0; i < bandStates.length && i < mapped.length; i++) {
          final g = mapped[i].clamp(bandStates[i].minGain, bandStates[i].maxGain).toDouble();
          bandStates[i].gain = g;
          final nativeBand = parameters.bands.firstWhere((b) => b.index == bandStates[i].index);
          await nativeBand.setGain(isEnabled ? g : 0.0);
        }
      } catch (e) {
        debugPrint('push EQ to hardware failed: $e');
      }
    }

    // Stage B: Resonate DynamicsProcessing multi-band (API 28+) when attached.
    try {
      _dspPipeline.updateStudioGains(studioGains);
      final n = ResonateNativeDspBridge.lastBandCount ?? 0;
      if (n > 0) {
        // Sample engine response at evenly spaced points across studio range for native bands.
        final nativeCenters = <double>[
          for (var i = 0; i < n; i++)
            studioFrequencies.first +
                (studioFrequencies.last - studioFrequencies.first) * (i / (n - 1).clamp(1, 100)),
        ];
        final nativeGains = _dspPipeline.hardwareTargets(nativeCenters);
        await ResonateNativeDspBridge.pushBands(
          centersHz: nativeCenters,
          gainsDb: nativeGains,
          enabled: isEnabled,
        );
      }
    } catch (e) {
      debugPrint('push EQ to Resonate native DSP failed: $e');
    }
  }

  /// Attach native Resonate DSP to a just_audio Android session id.
  Future<void> attachNativeSession(int sessionId) async {
    final ok = await ResonateNativeDspBridge.attachSession(sessionId);
    if (ok) {
      await _pushToHardware();
      notifyListeners();
    }
  }

  Future<void> _applyPreamp() async {
    // Negative / zero preamp: digital attenuation via MusicProvider player gain.
    // LoudnessEnhancer is NOT used for cuts — OEMs often mute before -4 dB.
    final effective = isEnabled ? preamp : 0.0;
    final scale = math.pow(10.0, effective.clamp(-12.0, 0.0) / 20.0).toDouble().clamp(0.25, 1.0);
    try {
      if (_music != null) {
        await _music!.setEqPreampScale(scale);
      }
    } catch (e) {
      debugPrint('preamp digital scale failed: $e');
    }
    // Positive preamp only: soft LoudnessEnhancer boost (optional, capped).
    if (_loudnessEnhancer == null) return;
    try {
      if (!isEnabled || effective <= 0.15) {
        await _loudnessEnhancer!.setTargetGain(0);
        await _loudnessEnhancer!.setEnabled(false);
        return;
      }
      final softDb = (effective * 0.4).clamp(0.0, 2.5);
      await _loudnessEnhancer!.setTargetGain(softDb * 100.0);
      await _loudnessEnhancer!.setEnabled(true);
    } catch (e) {
      debugPrint('preamp boost failed: $e');
    }
  }

  void _applyStudioGains(List<double> gains) {
    final expanded = expandGainsToStudio(gains);
    for (var i = 0; i < studioBands.length; i++) {
      final g = i < expanded.length ? expanded[i] : 0.0;
      studioBands[i].gainDb = g.clamp(studioMinDb, studioMaxDb);
      bands[studioBands[i].label] = studioBands[i].gainDb;
    }
  }

  Future<void> setStudioBandGain(int index, double gainDb) async {
    if (index < 0 || index >= studioBands.length) return;
    studioBands[index].gainDb = gainDb.clamp(studioMinDb, studioMaxDb);
    bands[studioBands[index].label] = studioBands[index].gainDb;
    preset = 'Custom';
    await _pushToHardware();
    await _save();
    notifyListeners();
  }

  /// Legacy API used by older screens.
  Future<void> setBandGain(int index, double gain) async {
    // If callers pass hardware index, approximate nearest studio band.
    if (hasHardwareEq && index < bandStates.length) {
      final hz = bandStates[index].centerFrequency;
      var best = 0;
      var bestDist = double.infinity;
      for (var i = 0; i < studioBands.length; i++) {
        final d = (studioBands[i].frequencyHz - hz).abs();
        if (d < bestDist) {
          bestDist = d;
          best = i;
        }
      }
      await setStudioBandGain(best, gain);
      return;
    }
    await setStudioBandGain(index, gain);
  }

  Future<void> setGain(String band, double gain) async {
    for (final item in studioBands) {
      if (item.label == band) {
        await setStudioBandGain(item.index, gain);
        return;
      }
    }
  }

  Future<void> setEnabled(bool value) async {
    isEnabled = value;
    try {
      await _androidEqualizer?.setEnabled(value);
    } catch (e) {
      debugPrint('equalizer enable failed: $e');
    }
    await _pushToHardware();
    await _applyPreamp();
    await _save();
    notifyListeners();
  }

  Future<void> setPreamp(double value) async {
    preamp = value.clamp(-6.0, 6.0).toDouble();
    await _applyPreamp();
    await _save();
    notifyListeners();
  }

  Future<void> applyPreset(String name, {bool persistSelection = true}) async {
    EqualizerPreset? found;
    for (final p in allPresets) {
      if (p.name == name) {
        found = p;
        break;
      }
    }
    _applyStudioGains(found?.gains ?? builtInPresets.first.gains);
    if (persistSelection) {
      preset = name;
      await _save();
    }
    await _pushToHardware();
    notifyListeners();
  }

  Future<void> resetToFlat() => applyPreset('Flat');

  Future<void> saveCustomPreset(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final gains = studioBands.map((b) => b.gainDb).toList();
    customPresets.removeWhere((p) => p.name == trimmed);
    customPresets.add(EqualizerPreset(
      name: trimmed,
      category: 'Custom',
      gains: gains,
      isCustom: true,
    ));
    preset = trimmed;
    await _saveCustomPresets();
    await _save();
    notifyListeners();
  }

  Future<void> deleteCustomPreset(String name) async {
    customPresets.removeWhere((p) => p.name == name);
    if (preset == name) preset = 'Custom';
    await _saveCustomPresets();
    await _save();
    notifyListeners();
  }

  Future<void> _loadCustomPresets(SharedPreferences prefs) async {
    try {
      final raw = prefs.getString('equalizer_custom_presets_v1');
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      customPresets = list
          .whereType<Map>()
          .map((e) => EqualizerPreset.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('custom presets load failed: $e');
      customPresets = [];
    }
  }

  Future<void> _saveCustomPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'equalizer_custom_presets_v1',
        jsonEncode(customPresets.map((p) => p.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('custom presets save failed: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('equalizer_enabled', isEnabled);
      await prefs.setString('equalizer_preset', preset);
      await prefs.setDouble('equalizer_preamp', preamp);
      for (var i = 0; i < studioBands.length; i++) {
        await prefs.setDouble('eq_studio_band_$i', studioBands[i].gainDb);
      }
      for (final band in bandStates) {
        await prefs.setDouble('eq_band_${band.index}', band.gain);
      }
    } catch (e) {
      debugPrint('equalizer save failed: $e');
    }
  }
}
