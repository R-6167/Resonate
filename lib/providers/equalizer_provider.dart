import 'package:flutter/material.dart';
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

class EqualizerProvider extends ChangeNotifier {
  final AndroidEqualizer? _androidEqualizer;
  final Map<String, double> bands = {};
  final List<EqualizerBandState> bandStates = [];

  bool isEnabled = true;
  String preset = 'Flat';
  double preamp = 0.0;

  EqualizerProvider({AndroidEqualizer? equalizer})
      : _androidEqualizer = equalizer {
    _initialize();
  }

  bool get isAvailable => _androidEqualizer != null && bandStates.isNotEmpty;

  Future<void> _initialize() async {
    try {
      if (_androidEqualizer != null) {
        final parameters = await _androidEqualizer.parameters;
        bandStates
          ..clear()
          ..addAll(parameters.bands.map((band) => EqualizerBandState(
                index: band.index,
                centerFrequency: band.centerFrequency,
                minGain: parameters.minDecibels,
                maxGain: parameters.maxDecibels,
                gain: band.gain,
              )));
        for (final band in bandStates) {
          bands[_labelForFrequency(band.centerFrequency)] = band.gain;
        }
        await _androidEqualizer.setEnabled(true);
      }

      final prefs = await SharedPreferences.getInstance();
      isEnabled = prefs.getBool('equalizer_enabled') ?? true;
      preset = prefs.getString('equalizer_preset') ?? 'Flat';
      preamp = prefs.getDouble('equalizer_preamp') ?? 0.0;

      for (final band in bandStates) {
        final saved = prefs.getDouble('eq_band_${band.index}');
        if (saved != null) {
          band.gain = saved.clamp(band.minGain, band.maxGain).toDouble();
          await _setNativeBand(band);
        }
      }

      if (_androidEqualizer != null) {
        await _androidEqualizer.setEnabled(isEnabled);
      }
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

  Future<void> _setNativeBand(EqualizerBandState band) async {
    if (_androidEqualizer == null) return;
    try {
      final parameters = await _androidEqualizer.parameters;
      final nativeBand = parameters.bands.firstWhere((b) => b.index == band.index);
      await nativeBand.setGain(band.gain);
    } catch (e) {
      debugPrint('Equalizer band update failed: $e');
    }
  }

  Future<void> setBandGain(int index, double gain) async {
    final match = bandStates.where((band) => band.index == index).firstOrNull;
    if (match == null) return;
    match.gain = gain.clamp(match.minGain, match.maxGain).toDouble();
    bands[_labelForFrequency(match.centerFrequency)] = match.gain;
    preset = 'Custom';
    await _setNativeBand(match);
    await _save();
    notifyListeners();
  }

  Future<void> setGain(String band, double gain) async {
    final match = bandStates.firstWhere(
      (item) => _labelForFrequency(item.centerFrequency) == band,
      orElse: () => EqualizerBandState(
        index: -1,
        centerFrequency: 0,
        minGain: -12,
        maxGain: 12,
        gain: 0,
      ),
    );
    if (match.index >= 0) await setBandGain(match.index, gain);
  }

  Future<void> setEnabled(bool value) async {
    isEnabled = value;
    if (_androidEqualizer != null) {
      try {
        await _androidEqualizer.setEnabled(value);
      } catch (e) {
        debugPrint('Equalizer enable failed: $e');
      }
    }
    await _save();
    notifyListeners();
  }

  Future<void> setPreamp(double value) async {
    preamp = value.clamp(-12.0, 6.0).toDouble();
    await _save();
    notifyListeners();
  }

  Future<void> applyPreset(String name) async {
    final presets = <String, List<double>>{
      'Flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      'Bass Boost': [5, 4, 3, 2, 1, 0, 0, 0, 0, 0],
      'Treble Boost': [0, 0, 0, 0, 0, 1, 2, 3, 4, 5],
      'Vocal': [-2, -1, 0, 2, 4, 3, 2, 1, 0, -1],
      'Rock': [4, 3, 1, 0, -1, 1, 3, 4, 4, 3],
      'Pop': [-1, 1, 3, 4, 3, 1, 0, 1, 2, 2],
      'Jazz': [3, 2, 0, 1, -1, -1, 0, 1, 2, 3],
      'Classical': [3, 2, 1, 0, -1, -1, 0, 2, 3, 4],
      'Electronic': [4, 3, 1, 0, -2, 1, 3, 2, 3, 4],
    };

    final values = presets[name] ?? presets['Flat']!;
    for (var i = 0; i < bandStates.length; i++) {
      final sourceIndex = bandStates.length == 1
          ? 0
          : ((i * (values.length - 1)) / (bandStates.length - 1)).round();
      final gain = values[sourceIndex];
      await setBandGain(bandStates[i].index, gain);
    }
    preset = name;
    await _save();
    notifyListeners();
  }

  Future<void> reset() async {
    await applyPreset('Flat');
    preamp = 0.0;
    preset = 'Flat';
    await _save();
    notifyListeners();
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
