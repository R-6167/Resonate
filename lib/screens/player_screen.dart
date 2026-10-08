import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../ui/resonate_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/blur_sheet.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../models/intelligence_recommendation.dart';
import '../providers/equalizer_provider.dart';
import '../providers/intelligence_provider.dart';
import '../providers/music_provider.dart';
import '../providers/playback_features_provider.dart';
import '../services/audio_file_service.dart';
import '../services/playback_authority.dart';
import '../widgets/audio_visualization_widget.dart';
import '../widgets/dj_mode_status_chip.dart';
import '../widgets/resonate_mode_chip.dart';
import '../widgets/mode_player_density.dart';
import 'mode_shelf_screen.dart';
import '../widgets/mode_guarded_action.dart';
import '../modes/models/mode_action.dart';
import '../modes/models/resonate_mode.dart';
import '../modes/providers/mode_provider.dart';
import '../widgets/autopilot_takeover_card.dart';
import 'equalizer_screen.dart';
import 'queue_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  double? _dragPosition;
  bool _swipeTutorialChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Leaving the player must not silence active playback.
    _keepAudioAlive();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _keepAudioAlive();
    }
  }

  void _keepAudioAlive() {
    try {
      final music = context.read<MusicProvider>();
      if (music.isPlaying || music.currentSong != null) {
        unawaited(music.ensureAudiblePlayback());
      }
    } catch (_) {}
  }

  Future<void> _maybeShowSwipeTutorial() async {
    if (_swipeTutorialChecked) return;
    _swipeTutorialChecked = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('player_swipe_tutorial_seen') == true) return;
      if (!mounted) return;
      await showBlurredDialog(
        context: context,
        builder: (ctx) => const _SwipeTutorialDialog(),
      );
      await prefs.setBool('player_swipe_tutorial_seen', true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ResonateGlassScaffold(
      title: const Text('Now Playing'),
      actions: [
          const ResonateModeChip(dense: true),
          const DjModeStatusChip(dense: true),
          Consumer<MusicProvider>(
            builder: (_, music, __) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: Chip(
                    avatar: Icon(
                      music.activeEngineLabel == 'A'
                          ? Icons.looks_one_rounded
                          : Icons.looks_two_rounded,
                      size: 17,
                    ),
                    label: Text('Engine ${music.activeEngineLabel}'),
                  ),
                ),
              );
            },
          ),
        ],

      body: Consumer2<MusicProvider, ModeProvider>(
        builder: (context, music, modes, _) {
          final song = music.currentSong;
          if (song == null) {
            return _PlayerEmptyState();
          }

          final density = ModePlayerDensity.fromMode(modes);

          final duration = music.currentDuration ?? song.duration;
          final max = duration.inMilliseconds > 0
              ? duration.inMilliseconds.toDouble()
              : 1.0;
          final livePosition = music.currentPosition.inMilliseconds
              .toDouble()
              .clamp(0.0, max)
              .toDouble();
          final position = (_dragPosition ?? livePosition)
              .clamp(0.0, max)
              .toDouble();

          WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowSwipeTutorial());

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
            children: [
              GestureDetector(
                onHorizontalDragEnd: density.allowHorizontalSwipe
                    ? (details) {
                        final v = details.primaryVelocity ?? 0;
                        if (v < -400) {
                          music.nextSong(source: 'player_swipe');
                        } else if (v > 400) {
                          music.previousSong(source: 'player_swipe');
                        }
                      }
                    : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: SizedBox(
                    height: density.artworkHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                          child: const AudioVisualizationWidget(),
                        ),
                        Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(context).colorScheme.surface.withOpacity(.82),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(28),
                              child: Icon(Icons.album_rounded, size: 86),
                            ),
                          ),
                        ),
                        const Positioned(
                          bottom: 8,
                          left: 0,
                          right: 0,
                          child: _SwipeHintBadge(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _MarqueeSongTitle(title: song.title),
              const SizedBox(height: 5),
              Text(
                song.artist,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                song.album,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const ResonateModeChip(dense: true),
              const SizedBox(height: 6),
              const DjTransitionReasonChip(),
              if (density.hintLabel != null) ...[
                const SizedBox(height: 6),
                Text(
                  density.hintLabel!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.tertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (modes.mode.name != 'normal')
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ModeShelfScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.playlist_play_rounded, size: 18),
                  label: const Text('Mode shelf'),
                ),
              const SizedBox(height: 10),
              const SizedBox(height: 8),
              _WaveSeekBar(
                value: position,
                max: max,
                hitHeight: density.seekHitHeight,
                strokeScale: density.seekStrokeScale,
                onStart: (value) {
                  setState(() => _dragPosition = value);
                },
                onUpdate: (value) {
                  setState(() => _dragPosition = value);
                },
                onEnd: (value) async {
                  final target = Duration(milliseconds: value.round());
                  setState(() => _dragPosition = null);
                  await PlaybackAuthority.instance.userSeek(music, target);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AudioFileService.formatDuration(
                        Duration(milliseconds: position.round()),
                      ),
                    ),
                    Text(AudioFileService.formatDuration(duration)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              StreamBuilder<PlayerState>(
                stream: music.audioPlayer.playerStateStream,
                initialData: music.audioPlayer.playerState,
                builder: (_, snapshot) {
                  final state =
                      snapshot.data ?? music.audioPlayer.playerState;
                  final playing = state.playing &&
                      state.processingState != ProcessingState.completed;
                  final currentMs = music.currentPosition.inMilliseconds;

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ModeGuardedAction(
                        action: ModeAction.previous,
                        onAllowed: () =>
                            PlaybackAuthority.instance.userPrevious(music),
                        child: SizedBox(
                          width: density.transportIconSize + 28,
                          height: density.transportIconSize + 28,
                          child: Icon(
                            Icons.skip_previous_rounded,
                            size: density.transportIconSize,
                          ),
                        ),
                      ),
                      ModeGuardedAction(
                        action: ModeAction.seekBackward,
                        onAllowed: () => PlaybackAuthority.instance.userSeek(
                          music,
                          Duration(
                            milliseconds: math.max(0, currentMs - 10000),
                          ),
                        ),
                        child: SizedBox(
                          width: density.transportIconSize + 20,
                          height: density.transportIconSize + 20,
                          child: Icon(
                            Icons.replay_10_rounded,
                            size: density.largeControls
                                ? density.transportIconSize - 6
                                : 30,
                          ),
                        ),
                      ),
                      ModeGuardedAction(
                        action: ModeAction.playPause,
                        onAllowed: () {
                          music.togglePlayPause();
                        },
                        child: SizedBox(
                          width: density.playButtonSize,
                          height: density.playButtonSize,
                          child: FilledButton(
                            onPressed: null,
                            style: FilledButton.styleFrom(
                              minimumSize: Size(
                                density.playButtonSize,
                                density.playButtonSize,
                              ),
                              maximumSize: Size(
                                density.playButtonSize,
                                density.playButtonSize,
                              ),
                              padding: EdgeInsets.zero,
                              shape: const CircleBorder(),
                              disabledBackgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primary,
                              disabledForegroundColor: Theme.of(context)
                                  .colorScheme
                                  .onPrimary,
                            ),
                            child: Icon(
                              playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: density.playIconSize,
                            ),
                          ),
                        ),
                      ),
                      ModeGuardedAction(
                        action: ModeAction.seekForward,
                        onAllowed: () => PlaybackAuthority.instance.userSeek(
                          music,
                          Duration(
                            milliseconds:
                                math.min(max.toInt(), currentMs + 10000),
                          ),
                        ),
                        child: SizedBox(
                          width: density.transportIconSize + 20,
                          height: density.transportIconSize + 20,
                          child: Icon(
                            Icons.forward_10_rounded,
                            size: density.largeControls
                                ? density.transportIconSize - 6
                                : 30,
                          ),
                        ),
                      ),
                      ModeGuardedAction(
                        action: ModeAction.next,
                        onAllowed: () => music.nextSong(),
                        child: SizedBox(
                          width: density.transportIconSize + 28,
                          height: density.transportIconSize + 28,
                          child: Icon(
                            Icons.skip_next_rounded,
                            size: density.transportIconSize,
                          ),
                        ),
                      ),
                                        ],
                  );
                },
              ),
              if (density.requiresTwoFingerPlayback)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Two-finger taps for play / skip / seek',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (density.showSecondaryRow)
              ResonateGlassCard(
                padding: EdgeInsets.zero,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        tooltip: 'Volume',
                        icon: Icon(_volumeIcon(music.volume)),
                        onPressed: () => _showVolume(context, music),
                      ),
                      IconButton(
                        tooltip: 'Shuffle',
                        icon: Icon(
                          Icons.shuffle_rounded,
                          color: music.shuffleEnabled
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        onPressed: () =>
                            music.setShuffleEnabled(!music.shuffleEnabled),
                      ),
                      IconButton(
                        tooltip: 'Repeat',
                        icon: Icon(
                          music.repeatMode == PlaybackRepeatMode.one
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                          color: music.repeatMode != PlaybackRepeatMode.off
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        onPressed: () {
                          final next = music.repeatMode == PlaybackRepeatMode.off
                              ? PlaybackRepeatMode.all
                              : music.repeatMode == PlaybackRepeatMode.all
                                  ? PlaybackRepeatMode.one
                                  : PlaybackRepeatMode.off;
                          music.setRepeatMode(next);
                        },
                      ),
                      IconButton(
                        tooltip: 'Queue',
                        icon: const Icon(Icons.queue_music_rounded),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const QueueScreen(),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'More options',
                        icon: const Icon(Icons.more_vert_rounded),
                        onPressed: () => _showMoreOptions(context),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (density.showIntelligenceCards)
              Consumer<IntelligenceProvider>(
                builder: (context, intelligence, _) {
                  final item = intelligence.anticipatedNext;
                  if (!intelligence.isEnabled || item == null) return const SizedBox.shrink();
                  return Column(
                    children: [
                      _NextCard(item: item, mode: intelligence.autonomyLabel),
                      const SizedBox(height: 10),
                      const AutopilotTakeoverCard(),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _volumeIcon(double volume) {
    if (volume <= 0.001) return Icons.volume_off_rounded;
    if (volume < 0.45) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  Future<void> _showVolume(BuildContext context, MusicProvider music) async {
    await showBlurredModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Consumer<MusicProvider>(
        builder: (_, current, __) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Icon(_volumeIcon(current.volume)),
                  const SizedBox(width: 12),
                  const Text('Volume', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${(current.volume * 100).round()}%'),
                ]),
                Slider(value: current.volume, min: 0, max: 1, divisions: 100, onChanged: current.setVolume),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  TextButton.icon(onPressed: () => current.setVolume(0), icon: const Icon(Icons.volume_off_rounded), label: const Text('Mute')),
                  TextButton(onPressed: () => current.setVolume(1), child: const Text('100%')),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMoreOptions(BuildContext context) async {
    final playback = context.read<PlaybackFeaturesProvider>();
    final eq = context.read<EqualizerProvider>();
    final modes = context.read<ModeProvider>();
    final density = ModePlayerDensity.fromMode(modes);
    await showBlurredModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        final speedTile = ListTile(
          leading: Icon(Icons.speed_rounded, color: density.speedControlsEmphasized ? Theme.of(context).colorScheme.primary : null),
          title: Text(density.speedControlsEmphasized ? 'Playback speed · ${modes.mode.label}' : 'Playback speed', style: density.speedControlsEmphasized ? const TextStyle(fontWeight: FontWeight.w700) : null),
          trailing: Text('${playback.speed.toStringAsFixed(2)}×'),
          onTap: () { Navigator.pop(context); _showSpeed(context, playback); },
        );
        final sleepTile = ListTile(
          leading: Icon(Icons.timer_outlined, color: density.sleepTimerSuggested ? Theme.of(context).colorScheme.primary : null),
          title: Text(density.sleepTimerSuggested ? 'Sleep timer · Suggested' : 'Sleep timer', style: density.sleepTimerSuggested ? const TextStyle(fontWeight: FontWeight.w700) : null),
          trailing: Text(playback.sleepTimerLabel),
          onTap: () { Navigator.pop(context); _showSleepTimer(context, playback); },
        );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (density.speedControlsEmphasized) speedTile,
            if (density.sleepTimerSuggested) sleepTile,
            ListTile(
              leading: const Icon(Icons.equalizer_rounded),
              title: const Text('Equalizer'),
              subtitle: Text(eq.isEnabled ? eq.preset : 'Disabled'),
              onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const EqualizerScreen())); },
            ),
            if (!density.speedControlsEmphasized) speedTile,
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('Pitch'),
              trailing: Text('${playback.pitch.toStringAsFixed(2)}×'),
              onTap: () { Navigator.pop(context); _showPitch(context, playback); },
            ),
            Consumer<PlaybackFeaturesProvider>(
              builder: (_, current, __) => SwitchListTile(
                secondary: const Icon(Icons.volume_down_rounded),
                title: const Text('Volume normalization'),
                subtitle: Text('Target ${current.targetLoudness.toStringAsFixed(0)} LUFS • track gain when available'),
                value: current.normalizationEnabled,
                onChanged: current.setNormalizationEnabled,
              ),
            ),
            if (!density.sleepTimerSuggested) sleepTile,
          ]),
        );
      },
    );
  }
  Future<void> _showSpeed(
    BuildContext context,
    PlaybackFeaturesProvider playback,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Playback speed'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${playback.speed.toStringAsFixed(2)}×'),
                  Slider(
                    min: 0.25,
                    max: 2,
                    divisions: 35,
                    value: playback.speed,
                    onChanged: (value) {
                      playback.setSpeed(value);
                      setDialogState(() {});
                    },
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showPitch(
    BuildContext context,
    PlaybackFeaturesProvider playback,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Pitch'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${playback.pitch.toStringAsFixed(2)}×'),
                  Slider(
                    min: 0.5,
                    max: 2,
                    divisions: 30,
                    value: playback.pitch,
                    onChanged: (value) {
                      playback.setPitch(value);
                      setDialogState(() {});
                    },
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showSleepTimer(
    BuildContext context,
    PlaybackFeaturesProvider playback,
  ) async {
    final options = <Duration>[
      const Duration(minutes: 15),
      const Duration(minutes: 30),
      const Duration(minutes: 45),
      const Duration(minutes: 60),
      const Duration(minutes: 90),
      const Duration(hours: 2),
    ];

    final tiles = options
        .map<Widget>(
          (duration) => ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(_format(duration)),
            onTap: () {
              playback.startSleepTimer(duration);
              Navigator.pop(context);
            },
          ),
        )
        .toList();

    if (playback.sleepTimerActive) {
      tiles.add(
        ListTile(
          leading: const Icon(Icons.close_rounded),
          title: const Text('Cancel timer'),
          onTap: () {
            playback.cancelSleepTimer();
            Navigator.pop(context);
          },
        ),
      );
    }

    await showBlurredModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: tiles),
      ),
    );
  }

  String _format(Duration value) {
    return value.inHours > 0
        ? '${value.inHours} hours'
        : '${value.inMinutes} minutes';
  }
}

class _WaveSeekBar extends StatefulWidget {
  final double value;
  final double max;
  final ValueChanged<double> onStart;
  final ValueChanged<double> onUpdate;
  final ValueChanged<double> onEnd;
  final double hitHeight;
  final double strokeScale;
  const _WaveSeekBar({
    required this.value,
    required this.max,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    this.hitHeight = 64,
    this.strokeScale = 1.0,
  });
  @override
  State<_WaveSeekBar> createState() => _WaveSeekBarState();
}

class _WaveSeekBarState extends State<_WaveSeekBar> {
  double? _interactionValue;
  double _valueFor(Offset local, double width) =>
      width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0) * widget.max;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final display = _interactionValue ?? widget.value;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) {
            final v = _valueFor(d.localPosition, constraints.maxWidth);
            setState(() => _interactionValue = v);
            widget.onStart(v);
          },
          onHorizontalDragUpdate: (d) {
            final v = _valueFor(d.localPosition, constraints.maxWidth);
            setState(() => _interactionValue = v);
            widget.onUpdate(v);
          },
          onHorizontalDragEnd: (_) {
            final v = _interactionValue ?? widget.value;
            setState(() => _interactionValue = null);
            widget.onEnd(v);
          },
          onTapDown: (d) {
            final v = _valueFor(d.localPosition, constraints.maxWidth);
            setState(() => _interactionValue = v);
            widget.onStart(v);
          },
          onTapUp: (d) {
            final v = _valueFor(d.localPosition, constraints.maxWidth);
            setState(() => _interactionValue = null);
            widget.onEnd(v);
          },
          child: SizedBox(
            height: widget.hitHeight,
            child: CustomPaint(
              painter: _WaveSeekPainter(
                progress: widget.max <= 0 ? 0 : display / widget.max,
                color: Theme.of(context).colorScheme.primary,
                muted: Theme.of(context).colorScheme.outlineVariant,
                strokeScale: widget.strokeScale,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WaveSeekPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color muted;
  final double strokeScale;

  _WaveSeekPainter({
    required this.progress,
    required this.color,
    required this.muted,
    this.strokeScale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final count = math.max(36, (size.width / 6).round());
    final step = size.width / count;
    final active = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2, step * 0.46) * strokeScale;
    final inactive = Paint()
      ..color = muted.withOpacity(0.55)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2, step * 0.42) * strokeScale;

    for (var i = 0; i < count; i++) {
      final x = step * (i + 0.5);
      final envelope =
          0.22 + 0.78 * math.pow(math.sin((i + 2) * 0.61).abs(), 1.6);
      final h = size.height * 0.12 + envelope * size.height * 0.34;
      final p = i / count;
      canvas.drawLine(
        Offset(x, size.height / 2 - h),
        Offset(x, size.height / 2 + h),
        p <= progress ? active : inactive,
      );
    }

    final x = size.width * progress.clamp(0.0, 1.0);
    canvas.drawCircle(
      Offset(x, size.height / 2),
      5.5,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _WaveSeekPainter old) {
    return old.progress != progress ||
        old.color != color ||
        old.muted != muted;
  }
}


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
  Future<void> _run() async { if (!mounted || !_controller.hasClients) return; final max = _controller.position.maxScrollExtent; if (max <= 1) return; await _controller.animateTo(max, duration: const Duration(milliseconds: 5200), curve: Curves.easeInOut); if (!mounted || !_controller.hasClients) return; await Future<void>.delayed(const Duration(milliseconds: 1400)); if (!mounted || !_controller.hasClients) return; await _controller.animateTo(0, duration: const Duration(milliseconds: 5200), curve: Curves.easeInOut); if (mounted) _timer = Timer(const Duration(milliseconds: 1200), _run); }
  @override void dispose() { _timer?.cancel(); _controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) { final style = Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold); return LayoutBuilder(builder: (context, constraints) => SizedBox(height: 34, child: SingleChildScrollView(controller: _controller, scrollDirection: Axis.horizontal, physics: const NeverScrollableScrollPhysics(), child: ConstrainedBox(constraints: BoxConstraints(minWidth: constraints.maxWidth), child: Text(widget.title, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.visible, style: style))))); }
}

class _NextCard extends StatelessWidget {
  final IntelligenceRecommendation item;
  final String mode;

  const _NextCard({required this.item, required this.mode});

  @override
  Widget build(BuildContext context) {
    final music = context.read<MusicProvider>();
    final confidence =
        (item.confidence.clamp(0.0, 1.0) * 100).round();

    return ResonateGlassCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.auto_awesome),
        title: Row(
          children: [
            const Expanded(child: Text('A thought for your next track')),
            Chip(label: Text(mode), visualDensity: VisualDensity.compact),
          ],
        ),
        subtitle: Text(
          '${item.song.title}\n$confidence% confidence • ${item.reason}',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.play_circle_fill_rounded),
          onPressed: () => music.playSong(
            item.song,
            queue: [item.song],
            startIndex: 0,
          ),
        ),
      ),
    );
  }
}


class _PlayerEmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note_rounded, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              'Nothing playing yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a song from Library to start. Equalizer, Crossfade, and other audio tools are always available under Settings — no need to play first.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Text(
              'Library · Settings → Audio / Playback',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeHintBadge extends StatelessWidget {
  const _SwipeHintBadge();
  @override
  Widget build(BuildContext context) {
    return Text(
      'Swipe artwork for previous / next',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
          ),
    );
  }
}

class _SwipeTutorialDialog extends StatefulWidget {
  const _SwipeTutorialDialog();
  @override
  State<_SwipeTutorialDialog> createState() => _SwipeTutorialDialogState();
}

class _SwipeTutorialDialogState extends State<_SwipeTutorialDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Material(
        color: scheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Swipe to change tracks',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Swipe the artwork left for next, right for previous.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 72,
                width: 200,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) {
                    final x = (_c.value - 0.5) * 100;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          height: 4,
                          width: 160,
                          decoration: BoxDecoration(
                            color: scheme.outlineVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Transform.translate(
                          offset: Offset(x, 0),
                          child: Icon(Icons.touch_app_rounded, size: 40, color: scheme.primary),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
