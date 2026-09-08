from pathlib import Path

# 1 + 6: completion recovery + one native-operation serialization lane.
path = 'lib/providers/music_provider.dart'
p = Path(path)
s = p.read_text()
s = s.replace(
    "  bool _completionAdvanceInProgress = false;\n",
    "  bool _completionAdvanceInProgress = false;\n  bool _completionObservedDuringCrossfade = false;\n",
    1,
)
old_listener = """      if (state.processingState == ProcessingState.completed) { currentPosition = currentDuration ?? currentPosition; isPlaying = false; notifyListeners(); _publishServiceState(); if (!_completionAdvanceInProgress && !_crossfadeInProgress) unawaited(_advanceAfterCompletion()); }"""
new_listener = """      if (state.processingState == ProcessingState.completed) {
        currentPosition = currentDuration ?? currentPosition;
        isPlaying = false;
        notifyListeners();
        _publishServiceState();
        final upcoming = _queueIndex < _queue.length - 1 || _repeatMode == PlaybackRepeatMode.all;
        unawaited(ResonateDiagnostics.record('completion_detected', {
          'songId': currentSong?.id,
          'queueIndex': _queueIndex,
          'queueLength': _queue.length,
          'upcomingCount': upcoming ? _queue.length - _queueIndex - 1 : 0,
          'repeatMode': _repeatMode.name,
          'crossfadeInProgress': _crossfadeInProgress,
        }));
        if (_crossfadeInProgress) {
          _completionObservedDuringCrossfade = true;
        } else if (!_completionAdvanceInProgress) {
          unawaited(_advanceAfterCompletion());
        }
      }"""
if old_listener not in s: raise SystemExit('completion listener pattern not found')
s = s.replace(old_listener, new_listener, 1)
old_advance = """  Future<void> _advanceAfterCompletion() async {
    if (_completionAdvanceInProgress) return; _completionAdvanceInProgress = true;
    try {
      await _finishHistoryEvent(completed: true);
      if (_repeatMode == PlaybackRepeatMode.one) { currentPosition = Duration.zero; await audioPlayer.seek(Duration.zero); await audioPlayer.play(); isPlaying = true; await _startHistoryEvent(currentSong!); _publishServiceState(); notifyListeners(); return; }
      if (_queueIndex < _queue.length - 1) { await _playSongInternal(_queue[_queueIndex + 1], queue: _queue, startIndex: _queueIndex + 1, playbackIntentToken: _playbackIntentGate.currentToken); return; }
      if (_repeatMode == PlaybackRepeatMode.all && _queue.isNotEmpty) { await _playSongInternal(_queue.first, queue: _queue, startIndex: 0, playbackIntentToken: _playbackIntentGate.currentToken); return; }
      isPlaying = false; currentPosition = currentDuration ?? currentPosition; await _persistQueue(); _publishServiceState(); notifyListeners();
    } finally { _completionAdvanceInProgress = false; }
  }"""
new_advance = """  Future<void> _advanceAfterCompletion() async {
    if (_completionAdvanceInProgress) return;
    _completionAdvanceInProgress = true;
    final fromSongId = currentSong?.id;
    final targetIndex = _repeatMode == PlaybackRepeatMode.one
        ? _queueIndex
        : (_queueIndex < _queue.length - 1 ? _queueIndex + 1 : (_repeatMode == PlaybackRepeatMode.all && _queue.isNotEmpty ? 0 : -1));
    await ResonateDiagnostics.record('completion_advance_attempt', {
      'fromSongId': fromSongId,
      'queueIndex': _queueIndex,
      'queueLength': _queue.length,
      'targetIndex': targetIndex,
      'repeatMode': _repeatMode.name,
    });
    try {
      await _finishHistoryEvent(completed: true);
      if (_repeatMode == PlaybackRepeatMode.one) {
        currentPosition = Duration.zero;
        await audioPlayer.seek(Duration.zero);
        await audioPlayer.play();
        isPlaying = true;
        await _startHistoryEvent(currentSong!);
        _publishServiceState();
        notifyListeners();
        await ResonateDiagnostics.record('completion_advance_result', {'result': 'repeated', 'songId': currentSong?.id});
        return;
      }
      if (_queueIndex < _queue.length - 1) {
        final ok = await _playSongInternal(_queue[_queueIndex + 1], queue: _queue, startIndex: _queueIndex + 1, playbackIntentToken: _playbackIntentGate.currentToken);
        await ResonateDiagnostics.record('completion_advance_result', {'result': ok ? 'advanced' : 'failed', 'fromSongId': fromSongId, 'toSongId': currentSong?.id, 'queueIndex': _queueIndex});
        return;
      }
      if (_repeatMode == PlaybackRepeatMode.all && _queue.isNotEmpty) {
        final ok = await _playSongInternal(_queue.first, queue: _queue, startIndex: 0, playbackIntentToken: _playbackIntentGate.currentToken);
        await ResonateDiagnostics.record('completion_advance_result', {'result': ok ? 'wrapped' : 'failed', 'fromSongId': fromSongId, 'toSongId': currentSong?.id, 'queueIndex': _queueIndex});
        return;
      }
      isPlaying = false;
      currentPosition = currentDuration ?? currentPosition;
      await _persistQueue();
      _publishServiceState();
      notifyListeners();
      await ResonateDiagnostics.record('completion_advance_result', {'result': 'queue_exhausted', 'fromSongId': fromSongId, 'queueIndex': _queueIndex});
    } catch (e) {
      await ResonateDiagnostics.record('completion_advance_result', {'result': 'exception', 'fromSongId': fromSongId, 'error': e.toString()});
      rethrow;
    } finally {
      _completionAdvanceInProgress = false;
    }
  }"""
if old_advance not in s: raise SystemExit('advance function pattern not found')
s = s.replace(old_advance, new_advance, 1)
old_serializer = """    // User intent is the priority lane. Do not put a user command behind an
    // older load/play operation: that was the source of pause/next appearing
    // to do nothing until the stale recommendation finished. The intent gate
    // invalidates older work, while automatic transitions remain serialized.
    if (userInitiated) {
      return operation();
    }

    final next = _playOperation.then((_) => operation());
    _playOperation = next.then<void>((_) {}, onError: (_, __) {});
    return next;"""
new_serializer = """    // Every mutation of either native AudioPlayer goes through one FIFO lane.
    // The intent gate still makes stale work harmless at its checkpoints, but
    // the native player itself is never mutated concurrently by two callers.
    await ResonateDiagnostics.record('playback_operation_queued', {
      'command': command,
      'source': source,
      'userInitiated': userInitiated,
      'intentToken': effectiveIntent,
    });
    final next = _playOperation.then((_) => operation());
    _playOperation = next.then<void>((_) {}, onError: (_, __) {});
    return next;"""
if old_serializer not in s: raise SystemExit('serializer pattern not found')
s = s.replace(old_serializer, new_serializer, 1)
old_finally = """    } finally { _crossfadeInProgress = false; notifyListeners(); }
  }"""
new_finally = """    } finally {
      _crossfadeInProgress = false;
      notifyListeners();
      if (_completionObservedDuringCrossfade) {
        _completionObservedDuringCrossfade = false;
        if (currentSong?.id == outgoingSong?.id && !isPlaying && !_completionAdvanceInProgress && _queueIndex < _queue.length - 1) {
          await ResonateDiagnostics.record('completion_crossfade_recovery', {
            'songId': currentSong?.id,
            'queueIndex': _queueIndex,
            'reason': 'crossfade_finished_without_commit',
          });
          unawaited(_advanceAfterCompletion());
        }
      }
    }
  }"""
if old_finally not in s: raise SystemExit('crossfade finally pattern not found')
s = s.replace(old_finally, new_finally, 1)
p.write_text(s)

# 2 + 3 + 4: Player title marquee, higher recommendation card, shared mode presentation.
path = 'lib/screens/player_screen.dart'
p = Path(path); s = p.read_text()
old_title = """              Text(
                song.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),"""
if old_title not in s: raise SystemExit('player title pattern not found')
s = s.replace(old_title, "              _MarqueeSongTitle(title: song.title),", 1)
old_card = """              const SizedBox(height: 14),
              const SizedBox(
                height: 100,
                child: AudioVisualizationWidget(),
              ),"""
new_card = """              const SizedBox(height: 10),
              Consumer<IntelligenceProvider>(
                builder: (context, intelligence, _) {
                  final item = intelligence.anticipatedNext;
                  if (!intelligence.isEnabled || item == null) {
                    return const SizedBox.shrink();
                  }
                  return _NextCard(item: item, mode: intelligence.autonomyLabel);
                },
              ),
              const SizedBox(height: 10),
              const SizedBox(
                height: 100,
                child: AudioVisualizationWidget(),
              ),"""
if old_card not in s: raise SystemExit('player insertion point not found')
s = s.replace(old_card, new_card, 1)
old_lower = """              const SizedBox(height: 14),
              Consumer<IntelligenceProvider>(
                builder: (context, intelligence, _) {
                  final item = intelligence.anticipatedNext;
                  if (!intelligence.isEnabled || item == null) {
                    return const SizedBox.shrink();
                  }
                  return _NextCard(item: item);
                },
              ),
              const SizedBox(height: 8),"""
if old_lower not in s: raise SystemExit('old player card location not found')
s = s.replace(old_lower, """              const SizedBox(height: 14),
              const SizedBox(height: 8),""", 1)
old_next_decl = """class _NextCard extends StatelessWidget {
  final IntelligenceRecommendation item;

  const _NextCard({required this.item});"""
if old_next_decl not in s: raise SystemExit('next card declaration not found')
s = s.replace(old_next_decl, """class _NextCard extends StatelessWidget {
  final IntelligenceRecommendation item;
  final String mode;

  const _NextCard({required this.item, required this.mode});""", 1)
old_next_row = """      child: ListTile(
        leading: const Icon(Icons.auto_awesome),
        title: const Text('A thought for your next track'),"""
if old_next_row not in s: raise SystemExit('next card title pattern not found')
s = s.replace(old_next_row, """      child: ListTile(
        leading: const Icon(Icons.auto_awesome),
        title: Row(
          children: [
            const Expanded(child: Text('A thought for your next track')),
            Chip(label: Text(mode), visualDensity: VisualDensity.compact),
          ],
        ),""", 1)
s = s.replace("import 'dart:math' as math;\n", "import 'dart:async';\nimport 'dart:math' as math;\n", 1)
marquee = r'''

class _MarqueeSongTitle extends StatefulWidget {
  final String title;
  const _MarqueeSongTitle({required this.title});
  @override State<_MarqueeSongTitle> createState() => _MarqueeSongTitleState();
}

class _MarqueeSongTitleState extends State<_MarqueeSongTitle> {
  late final ScrollController _controller;
  Timer? _timer;
  @override void initState() { super.initState(); _controller = ScrollController(); WidgetsBinding.instance.addPostFrameCallback((_) => _schedule()); }
  @override void didUpdateWidget(covariant _MarqueeSongTitle oldWidget) { super.didUpdateWidget(oldWidget); if (oldWidget.title != widget.title) { _timer?.cancel(); if (_controller.hasClients) _controller.jumpTo(0); WidgetsBinding.instance.addPostFrameCallback((_) => _schedule()); } }
  void _schedule() { if (!mounted || !_controller.hasClients || _controller.position.maxScrollExtent <= 1) return; _timer?.cancel(); _timer = Timer(const Duration(milliseconds: 1200), _run); }
  Future<void> _run() async { if (!mounted || !_controller.hasClients) return; final max = _controller.position.maxScrollExtent; if (max <= 1) return; await _controller.animateTo(max, duration: const Duration(milliseconds: 1800), curve: Curves.easeInOut); if (!mounted || !_controller.hasClients) return; await Future<void>.delayed(const Duration(milliseconds: 500)); if (!mounted || !_controller.hasClients) return; await _controller.animateTo(0, duration: const Duration(milliseconds: 1800), curve: Curves.easeInOut); if (mounted) _timer = Timer(const Duration(milliseconds: 1200), _run); }
  @override void dispose() { _timer?.cancel(); _controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) { final style = Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold); return LayoutBuilder(builder: (context, constraints) => SizedBox(height: 34, child: SingleChildScrollView(controller: _controller, scrollDirection: Axis.horizontal, physics: const NeverScrollableScrollPhysics(), child: ConstrainedBox(constraints: BoxConstraints(minWidth: constraints.maxWidth), child: Text(widget.title, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.visible, style: style))))); }
}
'''
s = s.replace('\nclass _NextCard extends StatelessWidget {', marquee + '\nclass _NextCard extends StatelessWidget {', 1)
p.write_text(s)

# 4 + 5: Intelligence notification lifecycle, transitions, and queue decisions.
path = 'lib/providers/autopilot_controller.dart'
p = Path(path); s = p.read_text()
s = s.replace("import '../services/intelligence_settings_store.dart';\n", "import '../services/intelligence_settings_store.dart';\nimport '../services/resonate_diagnostics.dart';\n", 1)
s = s.replace("""    _consentGranted = true;
    _pendingTakeover = false;
    _pendingSongId = null;""", """    final pending = _pendingSongId;
    _consentGranted = true;
    _pendingTakeover = false;
    _pendingSongId = null;
    await ResonateDiagnostics.record('intelligence_notification_action', {
      'action': 'accepted', 'songId': pending, 'mode': intelligence.autonomyLabel,
    });""", 1)
s = s.replace("""    if (pending != null) _declinedForSongId = pending;
    notifyListeners();""", """    if (pending != null) _declinedForSongId = pending;
    await ResonateDiagnostics.record('intelligence_notification_action', {
      'action': 'rejected', 'songId': pending, 'mode': intelligence.autonomyLabel,
    });
    notifyListeners();""", 1)
s = s.replace("""        _pendingTakeover = true;
        _pendingSongId = next.id;
        notifyListeners();""", """        _pendingTakeover = true;
        _pendingSongId = next.id;
        await ResonateDiagnostics.record('intelligence_notification_action', {
          'action': 'shown', 'songId': next.id, 'mode': intelligence.autonomyLabel,
          'confidence': recommendation.confidence, 'reason': recommendation.reason,
        });
        notifyListeners();""", 1)
s = s.replace("""    _transitionSongId = music.currentSong?.id;
    _transitionInFlight = true;""", """    _transitionSongId = music.currentSong?.id;
    _transitionInFlight = true;
    await ResonateDiagnostics.record('intelligence_transition', {
      'stage': 'started', 'mode': intelligence.autonomyLabel,
      'fromSongId': music.currentSong?.id, 'toSongId': next.id,
      'confidence': recommendation.confidence, 'reason': recommendation.reason,
    });""", 1)
s = s.replace("""        if (_authority.isStale(automaticGeneration)) return;
        await music.nextSong();
      }
    } finally {""", """        if (_authority.isStale(automaticGeneration)) return;
        await music.nextSong();
      }
      await ResonateDiagnostics.record('intelligence_transition', {
        'stage': 'completed', 'mode': intelligence.autonomyLabel,
        'fromSongId': music.currentSong?.id, 'queueIndex': music.queueIndex,
      });
    } catch (e) {
      await ResonateDiagnostics.record('intelligence_transition', {
        'stage': 'failed', 'mode': intelligence.autonomyLabel, 'error': e.toString(),
      });
      rethrow;
    } finally {""", 1)
s = s.replace("""      if (candidates.isNotEmpty) await music.enqueueSongs(candidates);""", """      if (candidates.isNotEmpty) {
        final added = await music.enqueueSongs(candidates);
        await ResonateDiagnostics.record('intelligence_queue_decision', {
          'mode': intelligence.autonomyLabel,
          'candidates': candidates.map((song) => song.id).toList(),
          'added': added,
          'queueLength': music.queue.length,
          'queueIndex': music.queueIndex,
        });
      }""", 1)
p.write_text(s)

# 4 + 5: recommendation generation telemetry.
path = 'lib/providers/intelligence_provider.dart'
p = Path(path); s = p.read_text()
s = s.replace("import '../services/intelligence_settings_store.dart';\n", "import '../services/intelligence_settings_store.dart';\nimport '../services/resonate_diagnostics.dart';\n", 1)
needle = """      _recommendations = ranked.take(limit).toList();
      await _evaluateAutopilotGraduation();"""
repl = """      _recommendations = ranked.take(limit).toList();
      await ResonateDiagnostics.recordIntelligence(
        'recommendations_generated',
        data: {
          'mode': autonomyLabel,
          'sessionMode': _sessionMode,
          'count': _recommendations.length,
          'topSongId': _recommendations.isEmpty ? null : _recommendations.first.song.id,
          'topConfidence': _recommendations.isEmpty ? 0 : _recommendations.first.confidence,
          'exploration': exploration,
        },
      );
      await _evaluateAutopilotGraduation();"""
if needle not in s: raise SystemExit('intelligence recommendation assignment pattern not found')
s = s.replace(needle, repl, 1)
p.write_text(s)
