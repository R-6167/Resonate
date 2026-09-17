import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// User-saved or built-in curve. Values are always a 10-point studio curve
/// (31/62/125/250/500/1k/2k/4k/8k/16k Hz style) and are mapped onto whatever
/// hardware band count AndroidEqualizer exposes.
class EqualizerPreset {
  final String name;
  final String category;
  final List<double> gains; // length 10, dB relative
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

class EqualizerProvider extends ChangeNotifier {
  final AndroidEqualizer? _androidEqualizer;
  final Map<String, double> bands = {};
  final List<EqualizerBandState> bandStates = [];
  bool isEnabled = true;
  String preset = 'Flat';
  double preamp = 0.0;
  String? activeSongId;
  List<EqualizerPreset> customPresets = [];

  /// Canonical 10-band studio frequencies (Hz) used for presets & mapping.
  static const List<double> studioFrequencies = [
    31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
  ];

  EqualizerProvider({AndroidEqualizer? equalizer}) : _androidEqualizer = equalizer {
    _initialize();
  }

  bool get isAvailable => _androidEqualizer != null && bandStates.isNotEmpty;
  int get hardwareBandCount => bandStates.length;

  static final List<EqualizerPreset> builtInPresets = [
    // Utility
    const EqualizerPreset(name: 'Flat', category: 'Utility', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    const EqualizerPreset(name: 'Soft', category: 'Utility', gains: [2, 1, 0, 0, -1, -1, 0, 1, 2, 2]),
    const EqualizerPreset(name: 'Warm', category: 'Utility', gains: [3, 2, 1, 1, 0, -1, -1, -1, 0, 1]),
    const EqualizerPreset(name: 'Bright', category: 'Utility', gains: [-1, -1, 0, 0, 1, 2, 3, 4, 4, 4]),
    const EqualizerPreset(name: 'Balanced', category: 'Utility', gains: [2, 1, 0, 1, 2, 1, 0, 1, 2, 2]),
    // Bass / low end
    const EqualizerPreset(name: 'Bass Boost', category: 'Bass', gains: [6, 5, 4, 2, 1, 0, 0, 0, 0, 0]),
    const EqualizerPreset(name: 'Deep Bass', category: 'Bass', gains: [7, 6, 4, 1, 0, -1, 0, 0, 0, 0]),
    const EqualizerPreset(name: 'Sub Focus', category: 'Bass', gains: [8, 6, 3, 0, -1, -1, 0, 0, 0, 0]),
    // Treble
    const EqualizerPreset(name: 'Treble Boost', category: 'Treble', gains: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
    const EqualizerPreset(name: 'Air', category: 'Treble', gains: [0, 0, 0, 0, 0, 0, 1, 2, 4, 5]),
    // Voice
    const EqualizerPreset(name: 'Vocal', category: 'Voice', gains: [-2, -1, 0, 2, 4, 3, 2, 1, 0, -1]),
    const EqualizerPreset(name: 'Vocal Focus', category: 'Voice', gains: [-3, -2, 0, 3, 5, 4, 2, 1, -1, -2]),
    const EqualizerPreset(name: 'Podcast', category: 'Voice', gains: [-3, -2, 1, 4, 5, 3, 0, -2, -3, -4]),
    const EqualizerPreset(name: 'Spoken Word', category: 'Voice', gains: [-2, -1, 1, 3, 4, 3, 1, -1, -2, -3]),
    // Genre
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
    // Live / space
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

  Future<void> _initialize() async {
    try {
      if (_androidEqualizer != null) {
        final parameters = await _androidEqualizer!.parameters;
        bandStates
          ..clear()
          ..addAll(parameters.bands.map(
            (band) => EqualizerBandState(
              index: band.index,
              centerFrequency: band.centerFrequency,
              minGain: parameters.minDecibels,
              maxGain: parameters.maxDecibels,
              gain: band.gain,
            ),
          ));
        for (final band in bandStates) {
          bands[_labelForFrequency(band.centerFrequency)] = band.gain;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      isEnabled = prefs.getBool('equalizer_enabled') ?? true;
      preset = prefs.getString('equalizer_preset') ?? 'Flat';
      preamp = prefs.getDouble('equalizer_preamp') ?? 0.0;
      await _loadCustomPresets(prefs);
      for (final band in bandStates) {
        final saved = prefs.getDouble('eq_band_${band.index}');
        if (saved != null) {
          band.gain = saved.clamp(band.minGain, band.maxGain).toDouble();
          await _setNativeBand(band);
        }
      }
      // Re-apply named preset if still valid so hardware matches label.
      final match = allPresets.where((p) => p.name == preset);
      if (match.isNotEmpty && preset != 'Custom') {
        await applyPreset(preset, persistSelection: false);
      }
      await _androidEqualizer?.setEnabled(isEnabled);
      notifyListeners();
    } catch (e) {
      debugPrint('Equalizer initialization failed: $e');
    }
  }

  String _labelForFrequency(double hz) {
    if (hz >= 1000) {
      final khz = hz / 1000.0;
      return khz >= 10 ? '${khz.toStringAsFixed(0)}kHz' : '${khz.toStringAsFixed(1)}kHz';
    }
    return '${hz.round()}Hz';
  }

  /// Map a 10-point studio curve onto N hardware bands by nearest frequency.
  List<double> mapStudioToHardware(List<double> studioGains) {
    if (bandStates.isEmpty) return const [];
    final src = List<double>.from(studioGains);
    while (src.length < 10) {
      src.add(0);
    }
    return bandStates.map((band) {
      // Find closest studio frequency index
      var best = 0;
      var bestDist = (studioFrequencies[0] - band.centerFrequency).abs();
      for (var i = 1; i < studioFrequencies.length; i++) {
        final d = (studioFrequencies[i] - band.centerFrequency).abs();
        if (d < bestDist) {
          bestDist = d;
          best = i;
        }
      }
      // Mild blend with neighbors for smoother mapping on sparse hardware EQ
      if (best > 0 && best < studioFrequencies.length - 1) {
        final left = src[best - 1];
        final mid = src[best];
        final right = src[best + 1];
        return (left * 0.15 + mid * 0.7 + right * 0.15);
      }
      return src[best.clamp(0, src.length - 1)];
    }).toList();
  }

  Future<void> _setNativeBand(EqualizerBandState band) async {
    if (_androidEqualizer == null) return;
    try {
      final parameters = await _androidEqualizer!.parameters;
      final nativeBand = parameters.bands.firstWhere((b) => b.index == band.index);
      await nativeBand.setGain(band.gain);
    } catch (e) {
      debugPrint('Equalizer band update failed: $e');
    }
  }

  Future<void> setBandGain(int index, double gain) async {
    final matches = bandStates.where((band) => band.index == index);
    if (matches.isEmpty) return;
    final match = matches.first;
    match.gain = gain.clamp(match.minGain, match.maxGain).toDouble();
    bands[_labelForFrequency(match.centerFrequency)] = match.gain;
    preset = 'Custom';
    await _setNativeBand(match);
    await _save();
    notifyListeners();
  }

  Future<void> setGain(String band, double gain) async {
    for (final item in bandStates) {
      if (_labelForFrequency(item.centerFrequency) == band) {
        await setBandGain(item.index, gain);
        return;
      }
    }
  }

  Future<void> setEnabled(bool value) async {
    isEnabled = value;
    try {
      await _androidEqualizer?.setEnabled(value);
    } catch (e) {
      debugPrint('Equalizer enable failed: $e');
    }
    await _save();
    notifyListeners();
  }

  Future<void> setPreamp(double value) async {
    preamp = value.clamp(-12.0, 6.0).toDouble();
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
    final values = found?.gains ?? builtInPresets.first.gains;
    final mapped = mapStudioToHardware(values);
    for (var i = 0; i < bandStates.length; i++) {
      final g = mapped[i].clamp(bandStates[i].minGain, bandStates[i].maxGain).toDouble();
      bandStates[i].gain = g;
      bands[_labelForFrequency(bandStates[i].centerFrequency)] = g;
      await _setNativeBand(bandStates[i]);
    }
    if (persistSelection) {
      preset = name;
      await _save();
    }
    notifyListeners();
  }

  Future<void> resetToFlat() => applyPreset('Flat');

  Future<void> saveCustomPreset(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || bandStates.isEmpty) return;
    // Capture current hardware curve projected back to 10 studio points
    final studio = List<double>.filled(10, 0.0);
    for (var i = 0; i < studioFrequencies.length; i++) {
      final hz = studioFrequencies[i];
      var best = bandStates.first;
      var bestDist = (best.centerFrequency - hz).abs();
      for (final b in bandStates) {
        final d = (b.centerFrequency - hz).abs();
        if (d < bestDist) {
          bestDist = d;
          best = b;
        }
      }
      studio[i] = best.gain;
    }
    customPresets.removeWhere((p) => p.name == trimmed);
    customPresets.add(EqualizerPreset(
      name: trimmed,
      category: 'Custom',
      gains: studio,
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
      for (final band in bandStates) {
        await prefs.setDouble('eq_band_${band.index}', band.gain);
      }
    } catch (e) {
      debugPrint('Equalizer save failed: $e');
    }
  }
}
