import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../providers/equalizer_provider.dart';
import '../providers/music_provider.dart';
import '../providers/playback_features_provider.dart';
import '../screens/equalizer_screen.dart';
import '../services/audio_file_service.dart';
import '../widgets/audio_visualization_widget.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({Key? key}) : super(key: key);
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  double _systemVolume = 0.0;

  @override
  void initState() {
    super.initState();
    FlutterVolumeController.setAndroidAudioStream(stream: AudioStream.music);
    FlutterVolumeController.addListener((volume) {
      if (mounted) setState(() => _systemVolume = volume.clamp(0.0, 1.0));
    }, emitOnStart: true);
  }

  @override
  void dispose() {
    FlutterVolumeController.removeListener();
    super.dispose();
  }

  Future<void> _showVolume(BuildContext context) async {
    final volume = await FlutterVolumeController.getVolume() ?? _systemVolume;
    if (!mounted) return;
    _systemVolume = volume.clamp(0.0, 1.0);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Row(children: [
            Icon(_systemVolume <= 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded),
            Expanded(child: Slider(
              min: 0, max: 1, value: _systemVolume,
              onChanged: (value) async {
                await FlutterVolumeController.setVolume(value);
                if (mounted) setState(() => _systemVolume = value);
                setSheetState(() {});
              },
            )),
            SizedBox(width: 48, child: Text('${(_systemVolume * 100).round()}%', textAlign: TextAlign.end)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Now Playing'),
      actions: [Consumer<MusicProvider>(builder: (_, music, __) => IconButton(
        tooltip: 'Stop', icon: const Icon(Icons.stop_rounded),
        onPressed: music.currentSong == null ? null : music.stop,
      ))],
    ),
    body: Consumer<MusicProvider>(builder: (context, music, _) {
      final song = music.currentSong;
      if (song == null) return const Center(child: Text('No song selected'));
      final duration = music.currentDuration ?? song.duration;
      final max = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity).toDouble();
      final value = music.currentPosition.inMilliseconds.toDouble().clamp(0.0, max).toDouble();
      final scheme = Theme.of(context).colorScheme;
      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          Container(height: 250, decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), color: scheme.surfaceContainerHighest, border: Border.all(color: scheme.outlineVariant)), child: Center(child: Icon(Icons.album_rounded, size: 110, color: scheme.primary))),
          const SizedBox(height: 20),
          Text(song.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(song.artist, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          Text(song.album, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 18),
          ClipRRect(borderRadius: BorderRadius.circular(16), child: Container(height: 105, padding: const EdgeInsets.all(8), color: scheme.surfaceContainerHighest, child: const AudioVisualizationWidget())),
          const SizedBox(height: 12),
          Slider(value: value, min: 0, max: max, onChanged: (v) => music.seek(Duration(milliseconds: v.round()))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(AudioFileService.formatDuration(music.currentPosition)), Text(AudioFileService.formatDuration(duration))])),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _IconControl(tooltip: 'Previous song', icon: Icons.skip_previous_rounded, onPressed: music.previousSong),
            _IconControl(tooltip: 'Back 10 seconds', icon: Icons.replay_10_rounded, onPressed: () => music.seek(Duration(milliseconds: (music.currentPosition.inMilliseconds - 10000).clamp(0, max.toInt())))),
            StreamBuilder<PlayerState>(stream: music.audioPlayer.playerStateStream, initialData: music.audioPlayer.playerState, builder: (_, snapshot) {
              final state = snapshot.data ?? music.audioPlayer.playerState;
              final playing = state.playing && state.processingState != ProcessingState.completed;
              return _PlayPauseControl(isPlaying: playing, onPressed: music.togglePlayPause);
            }),
            _IconControl(tooltip: 'Forward 10 seconds', icon: Icons.forward_10_rounded, onPressed: () => music.seek(Duration(milliseconds: (music.currentPosition.inMilliseconds + 10000).clamp(0, max.toInt())))),
            _IconControl(tooltip: 'Next song', icon: Icons.skip_next_rounded, onPressed: music.nextSong),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(tooltip: 'Volume', icon: Icon(_systemVolume <= 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded), onPressed: () => _showVolume(context)),
            IconButton(tooltip: 'Sleep timer', icon: Icon(Icons.timer_outlined, color: context.watch<PlaybackFeaturesProvider>().sleepTimerActive ? scheme.primary : null), onPressed: () => _showSleepTimer(context, context.read<PlaybackFeaturesProvider>())),
            IconButton(tooltip: 'Per-song EQ', icon: const Icon(Icons.equalizer_rounded), onPressed: () => _openSongEq(context, song.id)),
            IconButton(tooltip: 'More playback options', icon: const Icon(Icons.more_vert_rounded), onPressed: () => _showMoreOptions(context)),
          ]),
        ],
      );
    }),
  );

  Future<void> _showMoreOptions(BuildContext context) async {
    final playback = context.read<PlaybackFeaturesProvider>();
    await showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (sheetContext) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(18, 4, 18, 20), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const ListTile(title: Text('Playback options', style: TextStyle(fontWeight: FontWeight.bold))),
      ListTile(leading: const Icon(Icons.speed_rounded), title: const Text('Speed'), trailing: Text('${playback.speed.toStringAsFixed(2)}×'), onTap: () => _showSpeed(sheetContext, playback)),
      ListTile(leading: const Icon(Icons.tune_rounded), title: const Text('Pitch'), trailing: Text('${playback.pitch.toStringAsFixed(2)}×'), onTap: () => _showPitch(sheetContext, playback)),
      SwitchListTile(secondary: const Icon(Icons.volume_down_rounded), title: const Text('Volume normalization'), subtitle: Text('Target ${playback.targetLoudness.toStringAsFixed(0)} LUFS'), value: playback.normalizationEnabled, onChanged: playback.setNormalizationEnabled),
    ]))));
  }

  Future<void> _showSpeed(BuildContext context, PlaybackFeaturesProvider playback) async {
    await showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => StatefulBuilder(builder: (_, setState) => Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 28), child: Column(mainAxisSize: MainAxisSize.min, children: [Text('Playback speed: ${playback.speed.toStringAsFixed(2)}×'), Slider(min: .25, max: 2, divisions: 35, value: playback.speed, onChanged: (v) { playback.setSpeed(v); setState(() {}); })]))));
  }

  Future<void> _showPitch(BuildContext context, PlaybackFeaturesProvider playback) async {
    await showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => StatefulBuilder(builder: (_, setState) => Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 28), child: Column(mainAxisSize: MainAxisSize.min, children: [Text('Pitch: ${playback.pitch.toStringAsFixed(2)}×'), Slider(min: .5, max: 2, divisions: 30, value: playback.pitch, onChanged: (v) { playback.setPitch(v); setState(() {}); })]))));
  }

  Future<void> _openSongEq(BuildContext context, String songId) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const EqualizerScreen()));
    if (!context.mounted) return;
    final eq = context.read<EqualizerProvider>();
    final action = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.save_outlined), title: const Text('Save EQ for this song'), onTap: () => Navigator.pop(sheetContext, 'save')),
      ListTile(leading: const Icon(Icons.download_outlined), title: const Text('Load saved EQ'), onTap: () => Navigator.pop(sheetContext, 'load')),
    ])));
    if (action == 'save') await eq.saveSongProfile(songId);
    if (action == 'load') {
      final found = await eq.loadSongProfile(songId);
      if (context.mounted && !found) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No saved EQ profile for this song.')));
    }
  }

  Future<void> _showSleepTimer(BuildContext context, PlaybackFeaturesProvider playback) async {
    final options = <Duration>[const Duration(minutes: 15), const Duration(minutes: 30), const Duration(minutes: 45), const Duration(minutes: 60), const Duration(minutes: 90), const Duration(hours: 2)];
    final selected = await showModalBottomSheet<Duration>(context: context, showDragHandle: true, builder: (sheetContext) => SafeArea(child: ListView(shrinkWrap: true, children: [
      ListTile(title: Text(playback.sleepTimerActive ? 'Timer: ${playback.sleepTimerLabel}' : 'Sleep timer', style: const TextStyle(fontWeight: FontWeight.bold))),
      ...options.map((duration) => ListTile(title: Text(_format(duration)), leading: const Icon(Icons.timer_outlined), onTap: () => Navigator.pop(sheetContext, duration))),
      if (playback.sleepTimerActive) ListTile(title: const Text('Cancel timer'), leading: const Icon(Icons.close_rounded), onTap: () { playback.cancelSleepTimer(); Navigator.pop(sheetContext); }),
    ])));
    if (selected != null) await playback.startSleepTimer(selected);
  }

  String _format(Duration value) => value.inHours > 0 ? '${value.inHours} hours' : '${value.inMinutes} minutes';
}

class _IconControl extends StatelessWidget {
  final String tooltip; final IconData icon; final VoidCallback onPressed;
  const _IconControl({required this.tooltip, required this.icon, required this.onPressed});
  @override
  Widget build(BuildContext context) => IconButton(tooltip: tooltip, icon: Icon(icon, size: 32), onPressed: onPressed);
}

class _PlayPauseControl extends StatelessWidget {
  final bool isPlaying; final VoidCallback onPressed;
  const _PlayPauseControl({required this.isPlaying, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(message: isPlaying ? 'Pause' : 'Play', child: Material(color: scheme.primary, shape: const CircleBorder(), elevation: 2, child: InkWell(customBorder: const CircleBorder(), onTap: onPressed, child: SizedBox(width: 68, height: 68, child: Center(child: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 42, color: scheme.onPrimary)))));
  }
}
