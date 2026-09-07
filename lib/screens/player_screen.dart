import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../models/intelligence_recommendation.dart';
import '../providers/intelligence_provider.dart';
import '../providers/music_provider.dart';
import '../providers/playback_features_provider.dart';
import '../services/audio_file_service.dart';
import '../services/playback_authority.dart';
import '../widgets/autopilot_takeover_card.dart';
import '../widgets/audio_visualization_widget.dart';
import 'queue_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({Key? key}) : super(key: key);
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  double? _dragPosition;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Now Playing')),
      body: Consumer<MusicProvider>(builder: (context, music, _) {
        final song = music.currentSong;
        if (song == null) return const Center(child: Text('No song selected'));
        final duration = music.currentDuration ?? song.duration;
        final max = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
        final livePosition = music.currentPosition.inMilliseconds.toDouble().clamp(0.0, max).toDouble();
        final position = (_dragPosition ?? livePosition).clamp(0.0, max).toDouble();
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          children: [
            Container(height: 250, decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), color: Theme.of(context).colorScheme.surfaceContainerHighest), child: const Icon(Icons.album_rounded, size: 110)),
            const SizedBox(height: 18),
            Text(song.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text(song.artist, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(song.album, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),
            const SizedBox(height: 105, child: AudioVisualizationWidget()),
            Slider(
              value: position,
              min: 0,
              max: max,
              onChanged: (value) => setState(() => _dragPosition = value),
              onChangeStart: (value) => setState(() => _dragPosition = value),
              onChangeEnd: (value) async {
                final target = Duration(milliseconds: value.round());
                setState(() => _dragPosition = null);
                await PlaybackAuthority.instance.userSeek(music, target);
              },
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(AudioFileService.formatDuration(_dragPosition == null ? music.currentPosition : Duration(milliseconds: _dragPosition!.round()))), Text(AudioFileService.formatDuration(duration))]),
            const SizedBox(height: 10),
            StreamBuilder<PlayerState>(stream: music.audioPlayer.playerStateStream, initialData: music.audioPlayer.playerState, builder: (_, snapshot) {
              final state = snapshot.data ?? music.audioPlayer.playerState;
              final playing = state.playing && state.processingState != ProcessingState.completed;
              return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                IconButton(iconSize: 36, icon: const Icon(Icons.skip_previous_rounded), onPressed: () => PlaybackAuthority.instance.userPrevious(music)),
                IconButton(iconSize: 30, icon: const Icon(Icons.replay_10_rounded), onPressed: () => PlaybackAuthority.instance.userSeek(music, Duration(milliseconds: (music.currentPosition.inMilliseconds - 10000).clamp(0, max.toInt())))),
                FilledButton(onPressed: () => PlaybackAuthority.instance.userToggle(music), child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded)),
                IconButton(iconSize: 30, icon: const Icon(Icons.forward_10_rounded), onPressed: () => PlaybackAuthority.instance.userSeek(music, Duration(milliseconds: (music.currentPosition.inMilliseconds + 10000).clamp(0, max.toInt())))),
                IconButton(iconSize: 36, icon: const Icon(Icons.skip_next_rounded), onPressed: () => PlaybackAuthority.instance.userNext(music)),
              ]);
            }),
            const SizedBox(height: 10),
            Card(child: Wrap(alignment: WrapAlignment.center, children: [
              IconButton(tooltip: 'Shuffle', icon: Icon(Icons.shuffle_rounded, color: music.shuffleEnabled ? Theme.of(context).colorScheme.primary : null), onPressed: () => music.setShuffleEnabled(!music.shuffleEnabled)),
              IconButton(tooltip: 'Repeat', icon: Icon(music.repeatMode == PlaybackRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded, color: music.repeatMode != PlaybackRepeatMode.off ? Theme.of(context).colorScheme.primary : null), onPressed: () { final next = music.repeatMode == PlaybackRepeatMode.off ? PlaybackRepeatMode.all : music.repeatMode == PlaybackRepeatMode.all ? PlaybackRepeatMode.one : PlaybackRepeatMode.off; music.setRepeatMode(next); }),
              IconButton(tooltip: 'Queue', icon: const Icon(Icons.queue_music_rounded), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QueueScreen()))),
              IconButton(tooltip: 'More options', icon: const Icon(Icons.more_vert_rounded), onPressed: () => _showMoreOptions(context)),
            ])),
            const SizedBox(height: 14),
            Consumer<IntelligenceProvider>(builder: (context, intelligence, _) {
              final item = intelligence.anticipatedNext;
              if (!intelligence.isEnabled || item == null) return const SizedBox.shrink();
              return _NextCard(item: item);
            }),
            const SizedBox(height: 8),
            const AutopilotTakeoverCard(),
          ],
        );
      }),
    );
  }

  Future<void> _showMoreOptions(BuildContext context) async {
    final playback = context.read<PlaybackFeaturesProvider>();
    await showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.speed_rounded), title: const Text('Playback speed'), trailing: Text('${playback.speed.toStringAsFixed(2)}×'), onTap: () { Navigator.pop(context); _showSpeed(context, playback); }),
      SwitchListTile(secondary: const Icon(Icons.volume_down_rounded), title: const Text('Volume normalization'), subtitle: Text('Target ${playback.targetLoudness.toStringAsFixed(0)} LUFS • track gain when available'), value: playback.normalizationEnabled, onChanged: playback.setNormalizationEnabled),
      ListTile(leading: const Icon(Icons.timer_outlined), title: const Text('Sleep timer'), onTap: () { Navigator.pop(context); _showSleepTimer(context, playback); }),
    ])));
  }

  Future<void> _showSpeed(BuildContext context, PlaybackFeaturesProvider playback) async {
    await showDialog<void>(context: context, builder: (_) => AlertDialog(title: const Text('Playback speed'), content: StatefulBuilder(builder: (context, setState) => Column(mainAxisSize: MainAxisSize.min, children: [Text('${playback.speed.toStringAsFixed(2)}×'), Slider(min: .25, max: 2, divisions: 35, value: playback.speed, onChanged: (value) { playback.setSpeed(value); setState(() {}); })]))));
  }

  Future<void> _showSleepTimer(BuildContext context, PlaybackFeaturesProvider playback) async {
    final options = <Duration>[const Duration(minutes: 15), const Duration(minutes: 30), const Duration(minutes: 45), const Duration(minutes: 60), const Duration(minutes: 90), const Duration(hours: 2)];
    final tiles = options.map<Widget>((duration) => ListTile(leading: const Icon(Icons.timer_outlined), title: Text(_format(duration)), onTap: () { playback.startSleepTimer(duration); Navigator.pop(context); })).toList();
    if (playback.sleepTimerActive) tiles.add(ListTile(leading: const Icon(Icons.close_rounded), title: const Text('Cancel timer'), onTap: () { playback.cancelSleepTimer(); Navigator.pop(context); }));
    await showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: tiles)));
  }

  String _format(Duration value) => value.inHours > 0 ? '${value.inHours} hours' : '${value.inMinutes} minutes';
}

class _NextCard extends StatelessWidget {
  final IntelligenceRecommendation item;
  const _NextCard({required this.item});
  @override
  Widget build(BuildContext context) {
    final music = context.read<MusicProvider>();
    return Card(color: Theme.of(context).colorScheme.primaryContainer, child: ListTile(leading: const Icon(Icons.auto_awesome), title: const Text('A thought for your next track'), subtitle: Text('${item.song.title}\n${item.reason}', maxLines: 3, overflow: TextOverflow.ellipsis), trailing: IconButton(icon: const Icon(Icons.play_circle_fill_rounded), onPressed: () => music.playSong(item.song, queue: [item.song], startIndex: 0))));
  }
}