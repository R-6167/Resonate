import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'music_provider.dart';

class CrossfadeProvider extends ChangeNotifier {
  final MusicProvider music;
  double duration = 0.0;
  bool isEnabled = false;
  String fadeType = 'linear';
  bool _transitionRunning = false;
  Timer? _watchTimer;

  CrossfadeProvider({required this.music}) {
    _load();
    _watchTimer = Timer.periodic(const Duration(milliseconds: 150), (_) => _watchPosition());
  }

  void _watchPosition() {
    if (!isEnabled || _transitionRunning || duration <= 0) return;
    final player = music.audioPlayer;
    if (!player.playing || !music.canCrossfadeNext) return;
    final trackDuration = player.duration;
    if (trackDuration == null || trackDuration <= Duration.zero) return;
    final remaining = trackDuration - player.position;
    if (remaining <= Duration(milliseconds: duration.round()) && remaining > Duration.zero) _performTransition();
  }

  Future<void> _performTransition() async {
    if (_transitionRunning) return;
    _transitionRunning = true;
    try {
      await music.performTrueCrossfade(milliseconds: duration.round(), fadeType: fadeType);
    } catch (e) {
      debugPrint('True crossfade transition failed: $e');
    } finally {
      _transitionRunning = false;
    }
  }

  Future<void> setDuration(double value) async {
    duration = value.clamp(0.0, 12000.0).toDouble();
    if (duration > 0 && !isEnabled) isEnabled = true;
    if (duration == 0) isEnabled = false;
    await _syncLoopMode();
    await _save();
    notifyListeners();
  }

  Future<void> toggleCrossfade(bool value) async {
    isEnabled = value;
    if (!isEnabled) duration = 0.0;
    else if (duration == 0.0) duration = 3000.0;
    await _syncLoopMode();
    await _save();
    notifyListeners();
  }

  Future<void> _syncLoopMode() async {
    // Crossfade must never use LoopMode.one. Loop-one prevents just_audio from
    // reaching completed state and was the cause of tracks repeating after a
    // crossfade transition on real devices.
    try {
      await music.audioPlayer.setLoopMode(LoopMode.off);
    } catch (_) {}
  }

  String getDurationString() {
    if (duration <= 0) return 'Off';
    if (duration < 1000) return '${duration.round()}ms';
    final seconds = duration / 1000;
    return seconds == seconds.roundToDouble() ? '${seconds.toInt()}s' : '${seconds.toStringAsFixed(1)}s';
  }

  Future<void> applyPreset(double value) => setDuration(value);

  Future<void> setFadeType(String value) async {
    const validTypes = ['linear', 'ease_in', 'ease_out', 'ease_in_out'];
    if (validTypes.contains(value)) { fadeType = value; await _save(); notifyListeners(); }
  }

  Future<void> reset() async {
    duration = 0.0; isEnabled = false; fadeType = 'linear';
    await _syncLoopMode(); await _save(); notifyListeners();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isEnabled = prefs.getBool('crossfade_enabled') ?? false;
      duration = prefs.getDouble('crossfade_duration') ?? 0.0;
      fadeType = prefs.getString('crossfade_fade_type') ?? 'linear';
      if (!['linear', 'ease_in', 'ease_out', 'ease_in_out'].contains(fadeType)) fadeType = 'linear';
      await _syncLoopMode();
      notifyListeners();
    } catch (e) { debugPrint('Crossfade settings load failed: $e'); }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('crossfade_enabled', isEnabled);
      await prefs.setDouble('crossfade_duration', duration);
      await prefs.setString('crossfade_fade_type', fadeType);
    } catch (e) { debugPrint('Crossfade settings save failed: $e'); }
  }

  @override
  void dispose() { _watchTimer?.cancel(); super.dispose(); }
}
