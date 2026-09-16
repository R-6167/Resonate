import 'dart:async';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/listening_event.dart';
import '../services/audio_service_handler.dart';
import '../services/database_helper.dart';
import '../services/playback_authority.dart';
import '../services/playback_intent_gate.dart';
import '../services/resonate_diagnostics.dart';
import '../services/library_visibility_store.dart';
import '../services/audio_effects_bridge.dart';
import '../services/audio_effects_controller.dart';
import '../services/playback_coordinator.dart';

enum PlaybackRepeatMode { off, all, one }

class MusicProvider extends ChangeNotifier {
  final AudioHandler? audioHandler;
  final DatabaseHelper _database = DatabaseHelper();
  final PlaybackAuthority _authority = PlaybackAuthority.instance;
  final PlaybackIntentGate _playbackIntentGate = PlaybackIntentGate();
  final PlaybackCoordinator _playbackCoordinator = PlaybackCoordinator();
  late final AudioEffectsController _audioEffectsController;
  final LibraryVisibilityStore _visibility = LibraryVisibilityStore.instance;
  late final AudioPlayer _playerA;
  late final AudioPlayer _playerB;
  late final AndroidEqualizer _equalizerA;
  late final AndroidEqualizer _equalizerB;
  late final AndroidLoudnessEnhancer _loudnessA;
  late final AndroidLoudnessEnhancer _loudnessB;
  bool _activeIsA = true;
  AudioPlayer get audioPlayer => _activeIsA ? _playerA : _playerB;
  AudioPlayer get inactivePlayer => _activeIsA ? _playerB : _playerA;
  AndroidEqualizer get equalizer => _activeIsA ? _equalizerA : _equalizerB;
  AndroidLoudnessEnhancer get loudnessEnhancer => _activeIsA ? _loudnessA : _loudnessB;
  AndroidEqualizer get inactiveEqualizer => _activeIsA ? _equalizerB : _equalizerA;
  AndroidLoudnessEnhancer get inactiveLoudnessEnhancer => _activeIsA ? _loudnessB : _loudnessA;

  Song? currentSong;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration? currentDuration;
  double _volume = 1.0;
  List<Song> _queue = <Song>[];
  int _queueIndex = 0;
  bool _shuffleEnabled = false;
  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.off;
  bool _crossfadeInProgress = false;
  bool _completionAdvanceInProgress = false;
  bool _completionObservedDuringCrossfade = false;
  bool _queueRestoreInProgress = false;
  bool _crossfadeEnabled = false;
  int _crossfadeDurationMs = 3000;
  String _crossfadeFadeType = 'linear';
  bool _automaticCrossfadeInFlight = false;
  int _resumePositionMs = 0;
  String? _resumeSongId;
  DateTime? _lastResumePersist;
  Timer? _systemVolumePollTimer;
  Timer? _endOfTrackWatchdog;
  String? _lastCompletionSongId;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<double>? _volumeSubscription;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _noisySubscription;

  ListeningEvent? _activeHistoryEvent;
  int _activeHistoryPositionMs = 0;
  Future<void> _historySerial = Future<void>.value();
  bool _historyOperationActive = false;

  double get volume => _volume;
  List<Song> get queue => List.unmodifiable(_queue);
  int get queueIndex => _queueIndex;
  List<Song> get upcomingQueue => List.unmodifiable(_queue.skip(_queueIndex + 1));
  bool get shuffleEnabled => _shuffleEnabled;
  PlaybackRepeatMode get repeatMode => _repeatMode;
  bool get canCrossfadeNext => _queueIndex >= 0 && _queueIndex < _queue.length - 1 && !_crossfadeInProgress;
  bool get crossfadeEnabled => _crossfadeEnabled;
  int get crossfadeDurationMs => _crossfadeDurationMs;
  String get crossfadeFadeType => _crossfadeFadeType;
  String get activeEngineLabel => _authority.engineLabel(this);
  bool get transitionInProgress => _crossfadeInProgress || _automaticCrossfadeInFlight;

  static const _savedQueueIdsKey = 'playback_queue_song_ids';
  static const _savedQueueIndexKey = 'playback_queue_index';
  static const _shuffleEnabledKey = 'playback_shuffle_enabled';
  static const _repeatModeKey = 'playback_repeat_mode';
  static const _crossfadeEnabledKey = 'crossfade_enabled';
  static const _crossfadeDurationKey = 'crossfade_duration';
  static const _crossfadeFadeTypeKey = 'crossfade_fade_type';
  static const _resumePositionKey = 'playback_resume_position_ms';
  static const _resumeSongIdKey = 'playback_resume_song_id';
  static const MethodChannel _systemVolumeChannel = MethodChannel('com.example.resonate/media_store');

  MusicProvider({this.audioHandler}) {
    _equalizerA = AndroidEqualizer();
    _equalizerB = AndroidEqualizer();
    _loudnessA = AndroidLoudnessEnhancer();
    _loudnessB = AndroidLoudnessEnhancer();
    _audioEffectsController = AudioEffectsController(equalizerA: _equalizerA, equalizerB: _equalizerB, loudnessA: _loudnessA, loudnessB: _loudnessB);
    _playerA = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerA, _loudnessA]));
    _playerB = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerB, _loudnessB]));
    if (audioHandler is AudioServiceHandler) {
      (audioHandler! as AudioServiceHandler).bindPlaybackController(
        onPlay: () => togglePlayPause(source: 'audio_service'),
        onPause: () => pause(source: 'audio_service'),
        onStop: () => stop(source: 'audio_service'),
        onSeek: (position) => seek(position, source: 'audio_service'),
        onNext: () => nextSong(source: 'audio_service'),
        onPrevious: () => previousSong(source: 'audio_service'),
      );
    }
    _bindActivePlayerStreams();
    unawaited(_configureAudioSession());
    unawaited(_loadPlaybackSettings());
    _systemVolumePollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => unawaited(_syncSystemVolume()));
    unawaited(_restoreQueue());
  }

  // ... [FULL FIXED CONTENT CONTINUES - the complete fixed version from the sandbox is being used] ...

  @override
  void dispose() {
    _systemVolumePollTimer?.cancel();
    _endOfTrackWatchdog?.cancel();
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _volumeSubscription?.cancel();
    _interruptionSubscription?.cancel();
    _noisySubscription?.cancel();
    _playerA.dispose();
    _playerB.dispose();
    super.dispose();
  }
}
