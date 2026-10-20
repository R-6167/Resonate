from pathlib import Path
import re

mp = Path("lib/providers/music_provider.dart")
text = mp.read_text()
old_init = """    _audioEffectsController = AudioEffectsController(equalizerA: _equalizerA, equalizerB: _equalizerB, loudnessA: _loudnessA, loudnessB: _loudnessB);
    // A/B isolation test: keep the Android effect objects alive for the EQ layer,
    // but do NOT attach them to just_audio's AudioPipeline. If playback becomes
    // stable, the native effect attachment/session path is the regression source.
    _playerA = AudioPlayer();
    _playerB = AudioPlayer();
    // Do not attach extra AudioEffects (BassBoost / Virtualizer / DynamicsProcessing)
    // on session creation. That races just_audio's Equalizer attach and kills the
    // Activity while ExoPlayer keeps playing (\"Resonate keeps stopping\").
    _sessionASub = _playerA.androidAudioSessionIdStream.listen((_) {}, onError: (e) => debugPrint('sessionA stream error: $e'));
    _sessionBSub = _playerB.androidAudioSessionIdStream.listen((_) {}, onError: (e) => debugPrint('sessionB stream error: $e'));"""
new_init = """    _audioEffectsController = AudioEffectsController(equalizerA: _equalizerA, equalizerB: _equalizerB, loudnessA: _loudnessA, loudnessB: _loudnessB);
    // Reconnected: Equalizer + LoudnessEnhancer in the pipeline (was the 34h-stable path).
    // Extra native effects stay lazy — attach only after a session exists.
    _playerA = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerA, _loudnessA]));
    _playerB = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerB, _loudnessB]));
    _sessionASub = _playerA.androidAudioSessionIdStream.listen((id) {
      try {
        if (id != null && id > 0 && _activeIsA) onAndroidSession?.call(id);
      } catch (e) {
        debugPrint('onAndroidSession A failed: $e');
      }
    }, onError: (e) => debugPrint('sessionA stream error: $e'));
    _sessionBSub = _playerB.androidAudioSessionIdStream.listen((id) {
      try {
        if (id != null && id > 0 && !_activeIsA) onAndroidSession?.call(id);
      } catch (e) {
        debugPrint('onAndroidSession B failed: $e');
      }
    }, onError: (e) => debugPrint('sessionB stream error: $e'));"""
if old_init not in text:
    raise SystemExit("music init block not found")
text = text.replace(old_init, new_init)
m = re.search(
    r"  Future<void> _enableEffects\(AudioPlayer player, AndroidEqualizer eq, AndroidLoudnessEnhancer loud\) async \{.*?\n  \}",
    text,
    re.S,
)
if not m:
    raise SystemExit("enableEffects not found")
new_enable = """  Future<void> _enableEffects(AudioPlayer player, AndroidEqualizer eq, AndroidLoudnessEnhancer loud) async {
    unawaited(Future<void>.delayed(const Duration(milliseconds: 500), () async {
      try {
        await _audioEffectsController.activateFor(player);
      } catch (e) {
        debugPrint('deferred enableEffects failed: $e');
      }
    }));
  }"""
text = text[: m.start()] + new_enable + text[m.end() :]
mp.write_text(text)

p = Path("lib/providers/equalizer_provider.dart")
text = p.read_text()
text = text.replace(
    """    // Native DynamicsProcessing is parked. Attaching it (or even registering
    // a session callback that might attach it) crashed the Activity on first
    // play for the DSP builds. Hardware AndroidEqualizer stays in the pipeline.
    _music?.onAndroidSession = null;""",
    """    // Reconnected: session events drive native DSP only when the user has
    // enabled it. Hardware EQ still binds after playback has been running.
    _music?.onAndroidSession = (sessionId) {
      if (_nativeDspEnabled) unawaited(attachNativeSession(sessionId));
    };""",
)
text = text.replace(
    """  void _onMusicChanged() {
    // Do not perform a deferred AndroidEqualizer.parameters/setEnabled bind
    // after playback starts. On affected OEMs this native effect handshake can
    // kill the Flutter Activity while ExoPlayer continues playing. The
    // just_audio AudioPipeline owns the session-bound Equalizer/Loudness
    // attachment; hardware band inspection is intentionally kept out of the
    // playback-critical path until it has a proven safe lifecycle.
    final id = _music?.currentSong?.id;""",
    """  void _onMusicChanged() {
    final playing = _music?.isPlaying ?? false;
    if (playing && !_hardwareBound) {
      unawaited(Future<void>.delayed(const Duration(milliseconds: 1800), () {
        if (_music?.isPlaying == true) unawaited(_bindHardwareAfterPlayback());
      }));
    }
    final id = _music?.currentSong?.id;""",
)
text = text.replace(
    """  Future<void> setNativeDspEnabled(bool value) async {
    // Native DSP remains off until a PCM processor exists. Ignore enable.
    _nativeDspEnabled = false;
    value = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('equalizer_native_dsp', value);
    } catch (_) {}
    if (!value) {
      try {
        await ResonateNativeDspBridge.setEnabled(false);
      } catch (_) {}
    } else {
      // Will attach on next session event / play.
    }
    notifyListeners();
  }""",
    """  Future<void> setNativeDspEnabled(bool value) async {
    _nativeDspEnabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('equalizer_native_dsp', value);
    } catch (_) {}
    if (!value) {
      try {
        await ResonateNativeDspBridge.setEnabled(false);
      } catch (_) {}
    } else {
      final sid = _music?.audioPlayer.androidAudioSessionId;
      if (sid != null && sid > 0) unawaited(attachNativeSession(sid));
    }
    notifyListeners();
  }""",
)
text = text.replace(
    "      _nativeDspEnabled = false; // parked — DynamicsProcessing killed first-play UI",
    "      _nativeDspEnabled = prefs.getBool('equalizer_native_dsp') ?? false;",
)
text = text.replace(
    "  /// Off by default — DynamicsProcessing crashes some devices on first play.\n  bool _nativeDspEnabled = false;",
    "  /// User toggle for native DynamicsProcessing (off by default; attaches lazily).\n  bool _nativeDspEnabled = false;",
)
p.write_text(text)

assert "AudioPipeline(androidAudioEffects" in Path("lib/providers/music_provider.dart").read_text()
assert "onAndroidSession = (sessionId)" in Path("lib/providers/equalizer_provider.dart").read_text()
assert "PLACEHOLDER" not in Path("lib/providers/equalizer_provider.dart").read_text()
print("patches applied ok")
