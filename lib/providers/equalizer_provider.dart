import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dsp_settings.dart';
import '../services/eq_lean_store.dart';
import '../services/resonate_dsp_pipeline.dart';
import 'music_provider.dart';
import 'bluetooth_provider.dart';
import '../services/audio_effects_bridge.dart';
import '../services/audio_output_route.dart';
import '../services/equalizer_dvc_sync.dart';

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

  bool isEnabled = true; // Permanent: Resonate always processes the playback signal.
  String preset = 'Flat';
  double preamp = 0.0;
  bool autoEqHeadroom = false;
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
  /// The native Resonate DSP path is always enabled; no user bypass exists.
  bool _nativeDspEnabled = true;
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
    // Output route → speaker protection / virtual bass on live DSP engines.
    unawaited(AudioOutputRouteService.instance.start());
    AudioOutputRouteService.instance.addListener(_onOutputRouteChanged);
    _onOutputRouteChanged();
    // Reconnected: session events drive native DSP only when the user has
    // enabled it. Hardware EQ still binds after playback has been running.
    _music?.onAndroidSession = (sessionId) {
      unawaited(attachNativeSession(sessionId));
    unawaited(AudioOutputRouteService.instance.refreshNow());
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
    final playing = _music?.isPlaying ?? false;
    if (playing && !_hardwareBound) {
      unawaited(Future<void>.delayed(const Duration(milliseconds: 1800), () {
        if (_music?.isPlaying == true) unawaited(_bindHardwareAfterPlayback());
      }));
    }
    final id = _music?.currentSong?.id;
    if (id == null || id == _lastLeanSongId) return;
    _lastLeanSongId = id;
    unawaited(_applyLeanForCurrent());
  }

  Future<void> _applyLeanForCurrent() async {
    final requestRevision = ++_leanRequestRevision;
    final manualRevision = _manualPresetRevision;
    final song = _music?.currentSong;
    String? lean;
    if (_learnedEqEnabled && song != null) {
      lean = await EqLeanStore.presetFor(songId: song.id, artist: song.artist);
    }
    // A slow lookup for a previous track must never overwrite a newer track
    // or a profile the listener selected while the lookup was in flight.
    if (requestRevision != _leanRequestRevision ||
        manualRevision != _manualPresetRevision) {
      return;
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

  void _onOutputRouteChanged() {
    final route = AudioOutputRouteService.instance;
    // Auto DSP posture: phone speaker → protection + virtual bass;
    // headphones / BT → full DSP, light bass; car → full DSP, no virtual bass.
    syncSpeakerPolicy(
      needsSpeakerProtection: route.needsSpeakerProtection,
      virtualBassAmount: route.suggestedVirtualBass,
      route: route.route,
    );
  }


  bool get btProfilesEnabled => _btProfilesEnabled;
  bool get nativeDspUserEnabled => _nativeDspEnabled;

  Future<void> setNativeDspEnabled(bool value) async {
    // Compatibility shim for older callers: processing cannot be disabled.
    _nativeDspEnabled = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('equalizer_native_dsp', true);
      await DspSettings.update((settings) => settings.copyWith(masterEnabled: true));
    } catch (_) {}
    // Persisted master state must be applied to the registry even when no sink
    // exists yet; the registry carries it forward to future A/B engines.
    await ResonateNativeDspBridge.setEnabled(true);
    final sid = _music?.audioPlayer.androidAudioSessionId;
    if (sid != null && sid > 0) unawaited(attachNativeSession(sid));
    notifyListeners();
  }


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
      // The preset-driven Bluetooth switch has been removed from the product
      // UI. Keep old profile data for compatibility, but do not silently change
      // the listener's sound when a route changes.
      _btProfilesEnabled = false;
      await prefs.setBool('equalizer_bt_profiles', false);
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

  /// First-party Resonate profiles. These are deliberately restrained starting
  /// curves, not claims of universally correct or listening-validated tuning.
  /// Keep these alongside the classic presets so existing names and user
  /// libraries remain compatible.
  static const List<EqualizerPreset> resonatePresets = [
    EqualizerPreset(
      name: 'Resonate Signature',
      category: 'Resonate',
      gains: [1.5, 1.5, 1, 0.5, 0, 0, 0.5, 1, 1.5, 1],
    ),
    EqualizerPreset(
      name: 'Resonate Warmth',
      category: 'Resonate',
      gains: [2, 1.5, 1, 0.5, 0, -0.5, -0.5, 0, 0.5, 0.5],
    ),
    EqualizerPreset(
      name: 'Resonate Clarity',
      category: 'Resonate',
      gains: [-1, -0.5, 0, 0.5, 1, 1.5, 2, 2, 1.5, 1],
    ),
    EqualizerPreset(
      name: 'Resonate Afterhours',
      category: 'Resonate',
      gains: [1.5, 1, 0.5, 0, -0.5, -0.5, 0, 0.5, 0.5, 0],
    ),
    EqualizerPreset(
      name: 'Resonate Pulse',
      category: 'Resonate',
      gains: [2.5, 2, 1, 0, -0.5, 0, 0.5, 1, 1.5, 1],
    ),
    // Listening-context profiles are first-party Resonate curves too. Keep
    // gains intentionally bounded; real-world validation is tracked separately.
    EqualizerPreset(
      name: 'Resonate Deep Bass',
      category: 'Resonate',
      gains: [2.5, 2.25, 1.75, 1, 0.25, -0.5, -0.5, 0, 0, 0],
    ),
    EqualizerPreset(
      name: 'Resonate Drive',
      category: 'Resonate',
      gains: [2.5, 2, 1, 0, 0.5, 1, 1.5, 1, 0.5, 0],
    ),
    EqualizerPreset(
      name: 'Resonate Focus',
      category: 'Resonate',
      gains: [-1, -0.5, 0, 1, 1.5, 1.5, 1, 0, -0.5, -1],
    ),
    EqualizerPreset(
      name: 'Resonate Speaker',
      category: 'Resonate',
      gains: [1.5, 1, 0.5, 0, 0, 0.5, 1, 0.5, 0, -0.5],
    ),
    EqualizerPreset(
      name: 'Resonate Vocal Presence',
      category: 'Resonate',
      gains: [-1, -0.5, 0, 1, 2, 2, 1.5, 1, 0.5, 0],
    ),
  ];

  List<EqualizerPreset> get allPresets => [
        ...builtInPresets,
        ...resonatePresets,
        ...customPresets,
      ];

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
    if (_hardwareBound) unawaited(_reloadHardwareAndApply());
  }

  Future<void> _reloadHardwareAndApply() async {
    await _loadHardwareBands();
    await _pushToHardware();
    await _applyPreamp();
    notifyListeners();
  }

  bool _hardwareBound = false;
  int _leanRequestRevision = 0;
  int _manualPresetRevision = 0;

  /// Expands legacy ten-band curves and validates against the current studio grid.
  static List<double> normalizePresetGains(List<double> gains) {
    if (gains.length != 10 && gains.length != studioFrequencies.length) {
      throw FormatException(
        'Expected 10 legacy bands or ${studioFrequencies.length} studio bands.',
      );
    }
    if (gains.any((gain) => !gain.isFinite || gain < studioMinDb || gain > studioMaxDb)) {
      throw FormatException('Preset gains must be finite values from -12 to +12 dB.');
    }
    return expandGainsToStudio(gains);
  }

  /// Resolves a preset by its stable display name.
  /// Catalog names are kept unique, so a tap always maps to one curve.
  static EqualizerPreset? resolvePresetByName(
    String name, {
    Iterable<EqualizerPreset> custom = const [],
  }) {
    for (final candidate in [...builtInPresets, ...resonatePresets, ...custom]) {
      if (candidate.name == name) return candidate;
    }
    return null;
  }

  /// Returns a stable, unique custom name without shadowing a built-in profile.
  static String uniqueCustomPresetName(
    String requested, {
    Iterable<EqualizerPreset> existingCustomPresets = const [],
    String? replacingName,
  }) {
    final base = requested.trim();
    if (base.isEmpty) return '';
    final occupied = <String>{
      ...builtInPresets.map((item) => item.name.toLowerCase()),
      ...resonatePresets.map((item) => item.name.toLowerCase()),
      ...existingCustomPresets
          .where((item) => item.name != replacingName)
          .map((item) => item.name.toLowerCase()),
    };
    if (!occupied.contains(base.toLowerCase())) return base;
    var candidate = '$base (Custom)';
    var suffix = 2;
    while (occupied.contains(candidate.toLowerCase())) {
      candidate = '$base (Custom $suffix)';
      suffix++;
    }
    return candidate;
  }

  Future<void> _initialize() async {
    try {
      // Do NOT await AndroidEqualizer.parameters here. That completer finishes
      // at first play and then setEnabled/setGain races session attach.
      final prefs = await SharedPreferences.getInstance();
      final canonical = await DspSettings.load();
      isEnabled = canonical.eqEnabled;
      preset = canonical.preset;
      await _loadBtProfiles();
      _nativeDspEnabled = true;
      isEnabled = true;
      await prefs.setBool('equalizer_native_dsp', true);
      await DspSettings.update((settings) => settings.copyWith(masterEnabled: true, eqEnabled: true));
      preamp = canonical.preampDb;
      autoEqHeadroom = canonical.autoEqHeadroom;
      await _loadCustomPresets(prefs);

      // Restore studio curve from prefs if present.
      var restoredStudio = false;
      if (canonical.eqBandGainsDb.length == studioBands.length) {
        for (var i = 0; i < studioBands.length; i++) {
          studioBands[i].gainDb = canonical.eqBandGainsDb[i];
        }
        restoredStudio = true;
      } else {
        for (var i = 0; i < studioBands.length; i++) {
          final v = prefs.getDouble('eq_studio_band_$i');
          if (v != null) {
            studioBands[i].gainDb = v.clamp(studioMinDb, studioMaxDb);
            restoredStudio = true;
          }
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

      // Re-assert saved preset onto studio bands (Custom keeps restored prefs).
      if (preset != 'Custom') {
        final match = allPresets.where((p) => p.name == preset);
        if (match.isNotEmpty) {
          _applyStudioGains(match.first.gains);
          for (final b in studioBands) {
            bands[b.label] = b.gainDb;
          }
        }
      }
      // Restore the full active native profile immediately. These registry
      // calls update sticky state even if playback has not created a sink yet.
      await _applyPreamp();
      await _pushLiveDspCurve(dvcDb: canonical.dvcDb);
      await AudioEffectsBridge.setLiveDspLimiterCeiling(
        highDb: canonical.limiterHighCeilingDb,
        lowDb: canonical.limiterLowCeilingDb,
      );
      await AudioEffectsBridge.setLiveDspCrossoverHz(canonical.crossoverHz);
      final sessionId = _music?.audioPlayer.androidAudioSessionId;
      if (sessionId != null && sessionId > 0) {
        unawaited(attachNativeSession(sessionId));
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Equalizer initialization failed: $e');
    }
  }

  Future<void> _bindHardwareAfterPlayback() async {
    if (_hardwareBound) return;
    _hardwareBound = true;
    try {
      await _loadHardwareBands();
      // Hardware EQ is no longer part of the active audio path. Keep its
      // parameters available for capability/UI inspection only.
      // Re-apply the studio curve through the mature DSP engine.
      if (preset != 'Custom') {
        final match = allPresets.where((p) => p.name == preset);
        if (match.isNotEmpty) {
          _applyStudioGains(match.first.gains);
        }
      }
      await _pushToHardware();
      await _applyPreamp();
      await _pushLiveDspCurve();
      debugPrint('EQ re-applied after hardware bind preset=$preset preamp=$preamp');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('equalizer_enabled', true);
        await prefs.setString('equalizer_preset', preset);
      } catch (_) {}
      notifyListeners();
    } catch (e) {
      debugPrint('deferred hardware EQ bind failed: $e');
      _hardwareBound = false;
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

  /// User-facing name for the in-house engine (never "unknown").
  String get dspEngineId => 'Resonate DSP Engine';
  /// Technical id for diagnostics / logs.
  String get dspEngineTechnicalId => ResonateNativeDspBridge.available
      ? ResonateNativeDspBridge.engineLabel
      : _dspPipeline.id;
  bool get nativeDspActive => ResonateNativeDspBridge.available;
  int get nativeDspBandCount => ResonateNativeDspBridge.lastBandCount ?? 0;

  /// Push the studio curve to the mature live DSP engine.
  ///
  /// The native DSP processor is the single audio-path owner for EQ. Android's
  /// device Equalizer/DynamicsProcessing APIs are intentionally not written here;
  /// doing so would stack a second EQ on the same PCM stream.
  Future<void> _pushToHardware() async {
    try {
      final centers = studioBands.map((b) => b.frequencyHz).toList();
      final gains = studioBands.map((b) => b.gainDb).toList();
      // Await the native write so repeated on/off changes are applied in order.
      // A fire-and-forget write could finish after a newer toggle and restore
      // the stale EQ state.
      await syncStudioBandsToNativeEq(
        centersHz: centers,
        gainsDb: gains,
        enabled: true,
      );
    } catch (e) {
      debugPrint('live DSP EQ push failed: $e');
    }
  }

  /// Attach native Resonate DSP to a just_audio Android session id.
  Future<void> attachNativeSession(int sessionId) async {
    // Always attach Resonate DSP to each active Android playback session.
    try {
      final ok = await ResonateNativeDspBridge.attachSession(sessionId);
      if (ok) {
        await _pushToHardware();
        notifyListeners();
      }
    } catch (e, st) {
      debugPrint('attachNativeSession failed: $e');
      debugPrint('$st');
      // Stay on hardware EQ only — never rethrow (prevents Activity death).
    }
  }

  Future<void> _applyPreamp() async {
    // Mature DSP owns EQ preamp/DVC. Do not mirror it into player volume or
    // Android LoudnessEnhancer, otherwise the same gain is applied twice.
    final peakBandBoost = studioBands.isEmpty
        ? 0.0
        : studioBands.map((band) => band.gainDb).fold<double>(0.0, (peak, gain) => math.max(peak, gain).toDouble());
    final requestedPreamp = autoEqHeadroom
        ? math.min(preamp, preamp - math.max(0.0, peakBandBoost))
        : preamp;
    // Conservative estimate based on the largest positive studio-band gain;
    // bounded by the DSP's supported -6 dB preamp floor.
    final effective = requestedPreamp.clamp(-6.0, 6.0).toDouble();
    try {
      await AudioEffectsBridge.setLiveDspPreampDb(effective);
    } catch (e) {
      debugPrint('live DSP preamp push failed: $e');
    }
    // Keep legacy Android LoudnessEnhancer explicitly disabled for this path.
    if (_loudnessEnhancer != null) {
      try {
        await _loudnessEnhancer!.setTargetGain(0);
        await _loudnessEnhancer!.setEnabled(false);
      } catch (_) {}
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


  Future<void> _pushLiveDspCurve({double? dvcDb}) async {
    try {
      final centers = studioBands.map((b) => b.frequencyHz).toList();
      final gains = studioBands.map((b) => b.gainDb).toList();

      // Master bypass, EQ enable, preamp, and DVC are independent stages.
      // Apply the canonical master state even before the first sink registers.
      await ResonateNativeDspBridge.setEnabled(true);
      await AudioEffectsBridge.setLiveDspEqBands(
        centersHz: centers,
        gainsDb: gains,
        // Send the EQ preference independently; the native registry combines
        // it with master DSP state for each live and newly registered engine.
        enabled: true,
      );
      final resolvedDvcDb = dvcDb ?? (await DspSettings.load()).dvcDb;
      await AudioEffectsBridge.setLiveDspDvcDb(resolvedDvcDb);

      // _applyPreamp() owns the effective gain, including automatic headroom.
      // Do not write raw [preamp] here afterwards: that would undo headroom.
      final route = AudioOutputRouteService.instance;
      syncSpeakerPolicy(
        needsSpeakerProtection: route.needsSpeakerProtection,
        virtualBassAmount: route.suggestedVirtualBass,
        route: route.route,
      );
    } catch (e) {
      debugPrint('pushLiveDspCurve failed: $e');
    }
  }

  Future<void> setStudioBandGain(int index, double gainDb) async {
    if (index < 0 || index >= studioBands.length) return;
    _manualPresetRevision++;
    studioBands[index].gainDb = gainDb.clamp(studioMinDb, studioMaxDb);
    bands[studioBands[index].label] = studioBands[index].gainDb;
    preset = 'Custom';
    await _pushToHardware();
    await _applyPreamp();
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
    // Keep the API for compatibility, but EQ remains part of the always-on chain.
    isEnabled = true;
    // The mature live DSP is the authoritative EQ processor. The Android
    // Equalizer remains only as a read-only capability mirror for legacy UI.
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

  Future<void> setAutoEqHeadroom(bool value) async {
    autoEqHeadroom = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('equalizer_auto_headroom', value);
    } catch (_) {}
    await _applyPreamp();
    // Persist through the canonical model as well as the legacy mirror.
    // Otherwise a restart restores the previous headroom setting.
    await _save();
    notifyListeners();
  }

  Future<void> applyPreset(String name, {bool persistSelection = true}) async {
    // Resolve the exact catalog entry before mutating anything. An unknown or
    // stale name must not silently flatten the curve while keeping that label.
    final found = resolvePresetByName(name, custom: customPresets);
    if (found == null) {
      debugPrint('Ignoring unknown EQ preset: $name');
      return;
    }
    if (persistSelection) _manualPresetRevision++;
    _applyStudioGains(found.gains);
    if (persistSelection) {
      preset = name;
      await _save();
    }
    await _pushToHardware();
    await _applyPreamp();
    notifyListeners();
  }

  Future<void> resetToFlat() => applyPreset('Flat');

  /// Return the editable studio curve to neutral without selecting a preset.
  Future<void> resetStudioBandsToNeutral() async {
    _manualPresetRevision++;
    for (final band in studioBands) {
      band.gainDb = 0.0;
      bands[band.label] = 0.0;
    }
    preset = 'Custom';
    await _save();
    await _pushToHardware();
    await _applyPreamp();
    notifyListeners();
  }

  Future<String?> saveCustomPreset(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final replacingExisting = customPresets.any((item) => item.name == trimmed);
    final uniqueName = uniqueCustomPresetName(
      trimmed,
      existingCustomPresets: customPresets,
      replacingName: replacingExisting ? trimmed : null,
    );
    final gains = studioBands.map((b) => b.gainDb).toList();
    customPresets.removeWhere((item) => item.name == trimmed);
    customPresets.add(EqualizerPreset(
      name: uniqueName,
      category: 'Custom',
      gains: gains,
      isCustom: true,
    ));
    _manualPresetRevision++;
    preset = uniqueName;
    await _saveCustomPresets();
    await _save();
    notifyListeners();
    return uniqueName;
  }

  Future<void> deleteCustomPreset(String name) async {
    customPresets.removeWhere((p) => p.name == name);
    if (preset == name) preset = 'Custom';
    await _saveCustomPresets();
    await _save();
    notifyListeners();
  }

  /// Portable, versioned JSON backup for user EQ presets.
  String exportPresetsJson() {
    final presetsToExport = List<EqualizerPreset>.from(customPresets);
    if (presetsToExport.isEmpty) {
      presetsToExport.add(EqualizerPreset(
        name: preset.trim().isEmpty ? 'My EQ' : preset,
        category: 'Imported',
        gains: studioBands.map((band) => band.gainDb).toList(),
        isCustom: true,
      ));
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'resonate-eq-presets',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'presets': presetsToExport.map((item) => item.toJson()).toList(),
    });
  }

  /// Validates the complete bundle before changing saved presets.
  /// Returns the number of presets imported.
  Future<int> importPresetsJson(String source) async {
    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('This file is not valid JSON.');
    }
    if (decoded is! Map) {
      throw const FormatException('Expected a Resonate EQ preset bundle.');
    }
    final bundle = Map<String, dynamic>.from(decoded);
    if (bundle['format'] != 'resonate-eq-presets' ||
        bundle['version'] != 1 ||
        bundle['presets'] is! List) {
      throw const FormatException(
        'Unsupported preset file. Choose a Resonate EQ preset JSON export.',
      );
    }

    final incoming = <EqualizerPreset>[];
    for (final item in bundle['presets'] as List) {
      if (item is! Map) {
        throw const FormatException('A preset entry is malformed.');
      }
      final raw = Map<String, dynamic>.from(item);
      final name = raw['name'];
      final category = raw['category'];
      final rawGains = raw['gains'];
      if (name is! String || name.trim().isEmpty || name.length > 64 ||
          category is! String || category.trim().isEmpty ||
          rawGains is! List ||
          (rawGains.length != 10 && rawGains.length != studioBands.length)) {
        throw FormatException(
          'Each preset needs a name, category, and either 10 legacy bands or ${studioBands.length} studio bands.',
        );
      }
      final rawValues = <double>[];
      for (final value in rawGains) {
        if (value is! num || !value.toDouble().isFinite) {
          throw const FormatException('Preset gains must be finite numbers.');
        }
        final gain = value.toDouble();
        if (gain < studioMinDb || gain > studioMaxDb) {
          throw FormatException(
            'Preset "$name" contains a gain outside '
            '${studioMinDb.toStringAsFixed(0)} to ${studioMaxDb.toStringAsFixed(0)} dB.',
          );
        }
        rawValues.add(gain);
      }
      incoming.add(EqualizerPreset(
        name: name.trim(),
        category: 'Custom',
        gains: normalizePresetGains(rawValues),
        isCustom: true,
      ));
    }
    if (incoming.isEmpty) {
      throw const FormatException('The file contains no presets to import.');
    }

    final occupied = <String>{
      ...builtInPresets.map((p) => p.name.toLowerCase()),
      ...resonatePresets.map((p) => p.name.toLowerCase()),
      ...customPresets.map((p) => p.name.toLowerCase()),
    };
    var imported = 0;
    for (final item in incoming) {
      var candidate = item.name;
      var suffix = 2;
      while (occupied.contains(candidate.toLowerCase())) {
        candidate = '${item.name} (Imported${suffix == 2 ? '' : ' $suffix'})';
        suffix++;
      }
      occupied.add(candidate.toLowerCase());
      customPresets.add(EqualizerPreset(
        name: candidate,
        category: 'Custom',
        gains: List<double>.from(item.gains),
        isCustom: true,
      ));
      imported++;
    }
    await _saveCustomPresets();
    notifyListeners();
    return imported;
  }

  Future<void> _loadCustomPresets(SharedPreferences prefs) async {
    try {
      final raw = prefs.getString('equalizer_custom_presets_v1');
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      final loaded = list
          .whereType<Map>()
          .map((e) => EqualizerPreset.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      customPresets = [];
      for (final item in loaded) {
        final safeGains = normalizePresetGains(item.gains);
        final safeName = uniqueCustomPresetName(
          item.name,
          existingCustomPresets: customPresets,
        );
        customPresets.add(EqualizerPreset(
          name: safeName.isEmpty ? 'Custom Preset' : safeName,
          category: 'Custom',
          gains: safeGains,
          isCustom: true,
        ));
      }
      // Persist repairs so names and legacy curve shapes stay stable on restart.
      if (customPresets.length != loaded.length ||
          customPresets.asMap().entries.any((entry) =>
              entry.value.name != loaded[entry.key].name ||
              entry.value.gains.length != loaded[entry.key].gains.length)) {
        await _saveCustomPresets();
      }
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
      await prefs.setBool('equalizer_enabled', true);
      await prefs.setString('equalizer_preset', preset);
      await prefs.setDouble('equalizer_preamp', preamp);
      for (var i = 0; i < studioBands.length; i++) {
        await prefs.setDouble('eq_studio_band_$i', studioBands[i].gainDb);
      }
      for (final band in bandStates) {
        await prefs.setDouble('eq_band_${band.index}', band.gain);
      }
      // Keep the versioned canonical snapshot aligned while legacy keys are
      // retained for compatibility during the staged migration.
      await DspSettings.update((canonical) => canonical.copyWith(
        masterEnabled: true,
        eqEnabled: true,
        preset: preset,
        eqBandGainsDb: studioBands.map((band) => band.gainDb).toList(),
        preampDb: preamp,
        autoEqHeadroom: autoEqHeadroom,
      ));
    } catch (e) {
      debugPrint('equalizer save failed: $e');
    }
  }
}
