import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static const List<double> studioFrequencies = [
    31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
  ];

  static const double studioMinDb = -12.0;
  static const double studioMaxDb = 12.0;

  EqualizerProvider({
    AndroidEqualizer? equalizer,
    AndroidLoudnessEnhancer? loudnessEnhancer,
  })  : _androidEqualizer = equalizer,
        _loudnessEnhancer = loudnessEnhancer {
    _initStudioBands();
    _initialize();
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
    const EqualizerPreset(name: 'Bass Boost', category: 'Bass', gains: [6, 5, 4, 2, 1, 0, 0, 0, 0, 0]),
    const EqualizerPreset(name: 'Deep Bass', category: 'Bass', gains: [7, 6, 4, 1, 0, -1, 0, 0, 0, 0]),
    const EqualizerPreset(name: 'Sub Focus', category: 'Bass', gains: [8, 6, 3, 0, -1, -1, 0, 0, 0, 0]),
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
    const EqualizerPreset(name: 'Hip-Hop', category: 'Genre', gains: [5, 4, 2, 0, -1, 0, 1, 1, 2, 2]),
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

  /// Map 10 studio gains onto N hardware bands by nearest frequency + blend.
  List<double> mapStudioToHardware(List<double> studioGains) {
    if (bandStates.isEmpty) return const [];
    final src = List<double>.from(studioGains);
    while (src.length < 10) {
      src.add(0);
    }
    return bandStates.map((band) {
      var best = 0;
      var bestDist = (studioFrequencies[0] - band.centerFrequency).abs();
      for (var i = 1; i < studioFrequencies.length; i++) {
        final d = (studioFrequencies[i] - band.centerFrequency).abs();
        if (d < bestDist) {
          bestDist = d;
          best = i;
        }
      }
      if (best > 0 && best < studioFrequencies.length - 1) {
        final left = src[best - 1];
        final mid = src[best];
        final right = src[best + 1];
        return left * 0.15 + mid * 0.7 + right * 0.15;
      }
      return src[best.clamp(0, src.length - 1)];
    }).toList();
  }

  Future<void> _pushToHardware() async {
    if (_androidEqualizer == null || bandStates.isEmpty) return;
    final studioGains = studioBands.map((b) => b.gainDb).toList();
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

  Future<void> _applyPreamp() async {
    if (_loudnessEnhancer == null) return;
    try {
      // Many OEMs implement LoudnessEnhancer poorly (mute / hard clip).
      // Apply only a soft fraction of the labeled dB and keep a narrow window.
      // Labeled preamp stays -6..+6 for a centered zero on the slider.
      if (!isEnabled || preamp.abs() < 0.15) {
        await _loudnessEnhancer!.setTargetGain(0);
        await _loudnessEnhancer!.setEnabled(false);
        return;
      }
      final softDb = (preamp * 0.35).clamp(-2.0, 2.0); // max ±2 dB real effect
      final mb = softDb * 100.0;
      await _loudnessEnhancer!.setTargetGain(mb);
      await _loudnessEnhancer!.setEnabled(true);
    } catch (e) {
      debugPrint('preamp apply failed: $e');
    }
  }

  void _applyStudioGains(List<double> gains) {
    for (var i = 0; i < studioBands.length; i++) {
      final g = i < gains.length ? gains[i] : 0.0;
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
