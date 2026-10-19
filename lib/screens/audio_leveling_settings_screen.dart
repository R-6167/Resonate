import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/music_provider.dart';
import '../services/loudness_service.dart';
import '../ui/resonate_glass.dart';

/// User-facing analysis controls for Phase A audio leveling.
/// This screen reports sampled RMS only; it does not label the estimate LUFS
/// and does not change playback gain until the playback integration is enabled.
class AudioLevelingSettingsScreen extends StatefulWidget {
  const AudioLevelingSettingsScreen({super.key});

  @override
  State<AudioLevelingSettingsScreen> createState() =>
      _AudioLevelingSettingsScreenState();
}

class _AudioLevelingSettingsScreenState
    extends State<AudioLevelingSettingsScreen> {
  final LoudnessService _service = LoudnessService();
  double _targetRmsDbfs = LoudnessService.defaultTargetRmsDbfs;
  LoudnessScanResult? _result;
  String? _resultSongId;
  bool _scanning = false;
  bool _targetInitialized = false;
  String? _message;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final music = context.read<MusicProvider>();
    if (!_targetInitialized) {
      _targetRmsDbfs = music.audioLevelingTargetRmsDbfs;
      _targetInitialized = true;
    }
    final song = music.currentSong;
    if (song != null && song.id != _resultSongId) {
      _result = null;
      _resultSongId = null;
      _message = null;
      _loadCached(song);
    }
  }

  Future<void> _loadCached(Song song) async {
    final cached = await _service.getCached(song);
    if (!mounted || context.read<MusicProvider>().currentSong?.id != song.id) {
      return;
    }
    final matchesTarget = cached != null &&
        (cached.targetRmsDbfs - _targetRmsDbfs).abs() < 0.001;
    setState(() {
      _result = matchesTarget ? cached : null;
      _resultSongId = matchesTarget ? song.id : null;
    });
  }

  Future<void> _scanCurrentSong() async {
    final song = context.read<MusicProvider>().currentSong;
    if (song == null) {
      setState(() => _message = 'Start or select a song before scanning.');
      return;
    }
    setState(() {
      _scanning = true;
      _message = null;
      _result = null;
      _resultSongId = null;
    });
    try {
      final result = await _service.scanSong(
        song,
        targetRmsDbfs: _targetRmsDbfs,
        force: true,
      );
      if (!mounted) return;
      await context.read<MusicProvider>().refreshTrackLevelingFor(song);
      if (!mounted) return;
      setState(() {
        _result = result;
        _resultSongId = result == null ? null : song.id;
        _message = result == null
            ? 'This track could not be decoded for loudness analysis.'
            : 'Analysis complete for “${song.title}”.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Analysis failed. Playback was not changed.');
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) => ResonateGlassScaffold(
        title: const Text('Audio leveling'),
        body: Consumer<MusicProvider>(
          builder: (context, music, _) {
            final song = music.currentSong;
            final result = song != null && song.id == _resultSongId
                ? _result
                : null;
            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
              children: [
                ResonateGlassCard(
                  blurEnabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Track loudness analysis',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(
                        song == null
                            ? 'Select a track to analyze its loudness.'
                            : '${song.title} — ${song.artist}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Apply conservative leveling'),
                        subtitle: const Text('Attenuates tracks measured louder than the target; does not boost quiet tracks.'),
                        value: music.audioLevelingEnabled,
                        onChanged: (enabled) => music.setAudioLevelingEnabled(enabled),
                      ),
                      Text('Target sampled RMS: ${music.audioLevelingTargetRmsDbfs.toStringAsFixed(0)} dBFS'),
                      Slider(
                        value: music.audioLevelingTargetRmsDbfs,
                        min: -24,
                        max: -12,
                        divisions: 12,
                        label: '${_targetRmsDbfs.toStringAsFixed(0)} dBFS',
                        onChanged: _scanning
                            ? null
                            : (value) {
                                setState(() {
                                  _targetRmsDbfs = value;
                                  _result = null;
                                  _resultSongId = null;
                                });
                                music.setAudioLevelingTargetRmsDbfs(value);
                              },
                      ),
                      const SizedBox(height: 4),
                      FilledButton.icon(
                        onPressed: _scanning || song == null
                            ? null
                            : _scanCurrentSong,
                        icon: _scanning
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.graphic_eq_rounded),
                        label: Text(_scanning ? 'Analyzing track…' : 'Analyze current track'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (result != null)
                  ResonateGlassCard(
                    blurEnabled: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Analysis result',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        _metric(context, 'Measured RMS',
                            '${result.measuredRmsDbfs.toStringAsFixed(1)} dBFS'),
                        _metric(context, 'Sampled peak',
                            '${result.sampledPeakDbfs.toStringAsFixed(1)} dBFS'),
                        _metric(context, 'Suggested gain',
                            '${result.gainDb >= 0 ? '+' : ''}${result.gainDb.toStringAsFixed(1)} dB'),
                        _metric(context, 'Samples analyzed',
                            result.sampleCount.toString()),
                        const SizedBox(height: 8),
                        Text(
                          'The recommendation is limited to −12 dB through +6 dB. '
                          'It is an estimate from several PCM windows, not LUFS or true-peak metering.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_message!),
                  ),
                const SizedBox(height: 8),
                const ResonateGlassCard(
                  blurEnabled: false,
                  child: Text(
                    'Safety note: leveling applies attenuation only, bounded to −12 dB, and never boosts above the existing EQ/preamp master. '
                    'Positive gain recommendations remain informational until a peak-safe boost stage is available. '
                    'Measurements are sampled RMS, not LUFS or true-peak metering. The trim follows the existing EQ, sleep-fade, focus and crossfade volume paths.',
                  ),
                ),
              ],
            );
          },
        ),
      );

  Widget _metric(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
          ],
        ),
      );
}
