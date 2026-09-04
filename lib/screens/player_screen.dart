import 'package:flutter/material.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../models/intelligence_recommendation.dart';
import '../providers/equalizer_provider.dart';
import '../providers/intelligence_provider.dart';
import '../providers/music_provider.dart';
import '../providers/playback_features_provider.dart';
import '../screens/equalizer_screen.dart';
import '../screens/queue_screen.dart';
import '../services/audio_file_service.dart';
import '../widgets/audio_visualization_widget.dart';
import '../widgets/player_action_overlay.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({Key? key}) : super(key: key);
  @override State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final ValueNotifier<double> _systemVolume = ValueNotifier<double>(0.0);

  @override
  void initState() { super.initState(); _loadSystemVolume(); }
  Future<void> _loadSystemVolume() async { try { final volume = await FlutterVolumeController.getVolume(); if (volume != null) _systemVolume.value = volume.clamp(0.0, 1.0).toDouble(); } catch (_) {} }
  @override void dispose() { _systemVolume.dispose(); super.dispose(); }

  Future<void> _showVolume(BuildContext context) async {
    final volume = await FlutterVolumeController.getVolume();
    if (volume != null) _systemVolume.value = volume.clamp(0.0, 1.0).toDouble();
    if (!mounted) return;
    void syncVolume(double value) => _systemVolume.value = value.clamp(0.0, 1.0).toDouble();
    FlutterVolumeController.addListener(syncVolume, emitOnStart: true);
    try { await PlayerActionOverlay.show<void>(context: context, icon: Icons.volume_up_rounded, title: 'Volume', child: ValueListenableBuilder<double>(valueListenable: _systemVolume, builder: (_, value, __) => Column(mainAxisSize: MainAxisSize.min, children: [const SizedBox(height: 8), Row(children: [Icon(value <= 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, size: 28), Expanded(child: Slider(min: 0, max: 1, value: value, onChanged: (next) async { _systemVolume.value = next; await FlutterVolumeController.setVolume(next); })), SizedBox(width: 52, child: Text('${(value * 100).round()}%', textAlign: TextAlign.end))]), const SizedBox(height: 8)]))); } finally { FlutterVolumeController.removeListener(); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Now Playing')),
    body: Consumer<MusicProvider>(builder: (context, music, _) {
      final song = music.currentSong;
      if (song == null) return const Center(child: Text('No song selected'));
      final duration = music.currentDuration ?? song.duration;
      final max = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity).toDouble();
      final value = music.currentPosition.inMilliseconds.toDouble().clamp(0.0, max).toDouble();
      final scheme = Theme.of(context).colorScheme;
      return ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 28), children: [
        Container(height: 250, decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), color: scheme.surfaceContainerHighest, border: Border.all(color: scheme.outlineVariant)), child: Center(child: Icon(Icons.album_rounded, size: 110, color: scheme.primary))),
        const SizedBox(height: 20), Text(song.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6), Text(song.artist, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge), Text(song.album, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 18), ClipRRect(borderRadius: BorderRadius.circular(16), child: Container(height: 105, padding: const EdgeInsets.all(8), color: scheme.surfaceContainerHighest, child: const AudioVisualizationWidget())),
        const SizedBox(height: 12), Slider(value: value, min: 0, max: max, onChanged: (v) => music.seek(Duration(milliseconds: v.round()))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(AudioFileService.formatDuration(music.currentPosition)), Text(AudioFileService.formatDuration(duration))])),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_IconControl(tooltip: 'Previous song', icon: Icons.skip_previous_rounded, onPressed: music.previousSong), _IconControl(tooltip: 'Back 10 seconds', icon: Icons.replay_10_rounded, onPressed: () => music.seek(Duration(milliseconds: (music.currentPosition.inMilliseconds - 10000).clamp(0, max.toInt())))), StreamBuilder<PlayerState>(stream: music.audioPlayer.playerStateStream, initialData: music.audioPlayer.playerState, builder: (_, snapshot) { final state = snapshot.data ?? music.audioPlayer.playerState; final playing = state.playing && state.processingState != ProcessingState.completed; return _PlayPauseControl(isPlaying: playing, onPressed: music.togglePlayPause); }), _IconControl(tooltip: 'Forward 10 seconds', icon: Icons.forward_10_rounded, onPressed: () => music.seek(Duration(milliseconds: (music.currentPosition.inMilliseconds + 10000).clamp(0, max.toInt())))), _IconControl(tooltip: 'Next song', icon: Icons.skip_next_rounded, onPressed: music.nextSong)]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [ValueListenableBuilder<double>(valueListenable: _systemVolume, builder: (_, volume, __) => IconButton(tooltip: 'Volume', icon: Icon(volume <= 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded), onPressed: () => _showVolume(context))), Consumer<PlaybackFeaturesProvider>(builder: (_, playback, __) => Row(mainAxisSize: MainAxisSize.min, children: [IconButton(tooltip: playback.sleepTimerActive ? 'Sleep timer: ${playback.sleepTimerLabel}' : 'Sleep timer', icon: Icon(Icons.timer_outlined, color: playback.sleepTimerActive ? scheme.primary : null), onPressed: () => _showSleepTimer(context, playback)), if (playback.sleepTimerActive) Text(playback.sleepTimerLabel, style: Theme.of(context).textTheme.labelMedium)])), IconButton(tooltip: 'Queue', icon: const Icon(Icons.queue_music_rounded), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QueueScreen()))), IconButton(tooltip: 'Per-song EQ', icon: const Icon(Icons.equalizer_rounded), onPressed: () => _openSongEq(context, song.id)), IconButton(tooltip: 'More playback options', icon: const Icon(Icons.more_vert_rounded), onPressed: () => _showMoreOptions(context))]),
        const SizedBox(height: 20), Consumer<IntelligenceProvider>(builder: (context, intelligence, _) { final item = intelligence.anticipatedNext; if (!intelligence.isEnabled || item == null) return const SizedBox.shrink(); return _IntelligenceNextCard(item: item); }),
      ]);
    }),
  );

  Future<void> _showMoreOptions(BuildContext context) async { final playback = context.read<PlaybackFeaturesProvider>(); await PlayerActionOverlay.show<void>(context: context, icon: Icons.more_horiz_rounded, title: 'Playback options', child: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(leading: const Icon(Icons.speed_rounded), title: const Text('Speed'), trailing: Text('${playback.speed.toStringAsFixed(2)}×'), onTap: () => _showSpeed(context, playback)), ListTile(leading: const Icon(Icons.tune_rounded), title: const Text('Pitch'), trailing: Text('${playback.pitch.toStringAsFixed(2)}×'), onTap: () => _showPitch(context, playback)), SwitchListTile(secondary: const Icon(Icons.volume_down_rounded), title: const Text('Volume normalization'), subtitle: Text('Target ${playback.targetLoudness.toStringAsFixed(0)} LUFS'), value: playback.normalizationEnabled, onChanged: playback.setNormalizationEnabled)])); }
  Future<void> _showSpeed(BuildContext context, PlaybackFeaturesProvider playback) async { await PlayerActionOverlay.show<void>(context: context, icon: Icons.speed_rounded, title: 'Playback speed', child: StatefulBuilder(builder: (_, setState) => Column(mainAxisSize: MainAxisSize.min, children: [Text('${playback.speed.toStringAsFixed(2)}×', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)), Slider(min: .25, max: 2, divisions: 35, value: playback.speed, onChanged: (v) { playback.setSpeed(v); setState(() {}); })]))); }
  Future<void> _showPitch(BuildContext context, PlaybackFeaturesProvider playback) async { await PlayerActionOverlay.show<void>(context: context, icon: Icons.tune_rounded, title: 'Pitch', child: StatefulBuilder(builder: (_, setState) => Column(mainAxisSize: MainAxisSize.min, children: [Text('${playback.pitch.toStringAsFixed(2)}×', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)), Slider(min: .5, max: 2, divisions: 30, value: playback.pitch, onChanged: (v) { playback.setPitch(v); setState(() {}); })]))); }
  Future<void> _openSongEq(BuildContext context, String songId) async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const EqualizerScreen())); if (!context.mounted) return; final eq = context.read<EqualizerProvider>(); final action = await PlayerActionOverlay.show<String>(context: context, icon: Icons.equalizer_rounded, title: 'Song EQ', child: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(leading: const Icon(Icons.save_outlined), title: const Text('Save EQ for this song'), onTap: () => Navigator.pop(context, 'save')), ListTile(leading: const Icon(Icons.download_outlined), title: const Text('Load saved EQ'), onTap: () => Navigator.pop(context, 'load'))])); if (action == 'save') await eq.saveSongProfile(songId); if (action == 'load') { final found = await eq.loadSongProfile(songId); if (context.mounted && !found) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No saved EQ profile for this song.'))); } }
  Future<void> _showSleepTimer(BuildContext context, PlaybackFeaturesProvider playback) async { final options = <Duration>[const Duration(minutes: 15), const Duration(minutes: 30), const Duration(minutes: 45), const Duration(minutes: 60), const Duration(minutes: 90), const Duration(hours: 2)]; await PlayerActionOverlay.show<void>(context: context, icon: Icons.timer_outlined, title: 'Sleep timer', child: Consumer<PlaybackFeaturesProvider>(builder: (_, current, __) => Column(mainAxisSize: MainAxisSize.min, children: [if (current.sleepTimerActive) ...[Text(current.sleepTimerLabel, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 4), const Text('Playback will pause when the timer reaches zero.'), const SizedBox(height: 8)], ...options.map((duration) => ListTile(dense: true, leading: const Icon(Icons.timer_outlined), title: Text(_format(duration)), onTap: () { current.startSleepTimer(duration); Navigator.pop(context); })), if (current.sleepTimerActive) ListTile(dense: true, title: const Text('Cancel timer'), leading: const Icon(Icons.close_rounded), onTap: () { current.cancelSleepTimer(); Navigator.pop(context); })]))); }
  String _format(Duration value) => value.inHours > 0 ? '${value.inHours} hours' : '${value.inMinutes} minutes';
}

class _IntelligenceNextCard extends StatelessWidget { final IntelligenceRecommendation item; const _IntelligenceNextCard({required this.item}); @override Widget build(BuildContext context) { final scheme = Theme.of(context).colorScheme; final music = context.read<MusicProvider>(); return Card(color: scheme.primaryContainer.withOpacity(.72), child: Padding(padding: const EdgeInsets.fromLTRB(16, 15, 10, 15), child: Row(children: [Icon(Icons.auto_awesome, color: scheme.primary), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('I think you want this next', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary)), const SizedBox(height: 3), Text(item.song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium), Text('${item.confidenceLabel} • ${(item.confidence * 100).round()}% confidence'), const SizedBox(height: 3), Text(item.reason, maxLines: 2, overflow: TextOverflow.ellipsis)])), IconButton(tooltip: 'Play suggestion', icon: const Icon(Icons.play_circle_fill_rounded, size: 34), onPressed: () => music.playSong(item.song, queue: [item.song], startIndex: 0))]))); } }
class _IconControl extends StatelessWidget { final String tooltip; final IconData icon; final VoidCallback onPressed; const _IconControl({required this.tooltip, required this.icon, required this.onPressed}); @override Widget build(BuildContext context) => IconButton(tooltip: tooltip, icon: Icon(icon, size: 32), onPressed: onPressed); }
class _PlayPauseControl extends StatelessWidget { final bool isPlaying; final VoidCallback onPressed; const _PlayPauseControl({required this.isPlaying, required this.onPressed}); @override Widget build(BuildContext context) { final scheme = Theme.of(context).colorScheme; return Tooltip(message: isPlaying ? 'Pause' : 'Play', child: Material(color: scheme.primary, shape: const CircleBorder(), elevation: 2, child: InkWell(customBorder: const CircleBorder(), onTap: onPressed, child: SizedBox(width: 68, height: 68, child: Center(child: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 42, color: scheme.onPrimary)))))); } }
