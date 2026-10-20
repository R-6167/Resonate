import 'dart:async';

import 'package:flutter/foundation.dart';

import '../providers/music_provider.dart';
import 'resonate_diagnostics.dart';

enum PlaybackEventKind { userCommand, automaticCommand, stateBoundary }

class PlaybackEvent {
  final PlaybackEventKind kind;
  final String source;
  final String command;
  final int generation;
  final DateTime timestamp;

  const PlaybackEvent({
    required this.kind,
    required this.source,
    required this.command,
    required this.generation,
    required this.timestamp,
  });
}

/// Central playback authority. It owns user-command generations and now emits
/// typed events so Autopilot and other policy layers can react to intent rather
/// than polling every provider notification.
class PlaybackAuthority extends ChangeNotifier {
  PlaybackAuthority._();
  static final PlaybackAuthority instance = PlaybackAuthority._();

  int _userGeneration = 0;
  String _lastSource = 'normal_player';
  String _lastCommand = 'none';
  PlaybackEvent? _lastEvent;

  int get userGeneration => _userGeneration;
  String get lastSource => _lastSource;
  String get lastCommand => _lastCommand;
  PlaybackEvent? get lastEvent => _lastEvent;

  String engineLabel(MusicProvider music) => _engineLabelFor(music.audioPlayer);

  Future<void> userPause(MusicProvider music) => music.pause();
  Future<void> userStop(MusicProvider music) => music.stop();
  Future<void> userNext(MusicProvider music) => music.nextSong();
  Future<void> userPrevious(MusicProvider music) => music.previousSong();
  Future<void> userToggle(MusicProvider music) => music.togglePlayPause();
  Future<void> userSeek(MusicProvider music, Duration position) => music.seek(position);

  void markExternalUserCommand(String source, String command) {
    _userGeneration++;
    _lastSource = source;
    _lastCommand = command;
    _emit(PlaybackEvent(
      kind: PlaybackEventKind.userCommand,
      source: source,
      command: command,
      generation: _userGeneration,
      timestamp: DateTime.now(),
    ));
    _recordCommand(source, command);
  }

  bool isStale(int generation) => generation != _userGeneration;

  int beginAutomatic(String command) {
    _lastSource = 'automatic_transition';
    _lastCommand = command;
    _emit(PlaybackEvent(
      kind: PlaybackEventKind.automaticCommand,
      source: 'automatic_transition',
      command: command,
      generation: _userGeneration,
      timestamp: DateTime.now(),
    ));
    unawaited(ResonateDiagnostics.record('automatic_command_started', {
      'command': command,
      'userCommandGeneration': _userGeneration,
    }));
    return _userGeneration;
  }

  void emitStateBoundary(String command, {String source = 'music_provider'}) {
    _emit(PlaybackEvent(
      kind: PlaybackEventKind.stateBoundary,
      source: source,
      command: command,
      generation: _userGeneration,
      timestamp: DateTime.now(),
    ));
  }

  void _emit(PlaybackEvent event) {
    _lastEvent = event;
    notifyListeners();
  }

  void _recordCommand(String source, String command) {
    unawaited(ResonateDiagnostics.recordPlaybackCommand(source: source, command: command, generation: _userGeneration));
  }

  static final Map<int, String> _engineIds = <int, String>{};

  String _engineLabelFor(Object player) {
    final id = identityHashCode(player);
    final known = _engineIds[id];
    if (known != null) return known;
    final label = _engineIds.isEmpty ? 'A' : (_engineIds.values.contains('A') ? 'B' : 'A');
    _engineIds[id] = label;
    return label;
  }
}
