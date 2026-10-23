import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/media3_playback_client.dart';

/// Developer-only surface for testing the native Media3 prototype.
///
/// This screen is reachable only from Settings in debug builds. It never
/// changes MusicProvider and does not start playback until Play is pressed.
class Media3EngineLabScreen extends StatefulWidget {
  const Media3EngineLabScreen({super.key});

  @override
  State<Media3EngineLabScreen> createState() => _Media3EngineLabScreenState();
}

class _Media3EngineLabScreenState extends State<Media3EngineLabScreen> {
  final Media3PlaybackClient _client = Media3PlaybackClient();
  StreamSubscription<Media3PlaybackState>? _stateSubscription;
  Timer? _pollTimer;
  Media3PlaybackState? _state;
  String? _fileName;
  Uri? _source;
  String? _error;
  bool _busy = false;
  double _volume = 1;
  double? _dragPositionMs;

  bool get _hasSource => _source != null;
  Duration get _duration => _state?.duration ?? Duration.zero;
  Duration get _position => _dragPositionMs == null
      ? (_state?.position ?? Duration.zero)
      : Duration(milliseconds: _dragPositionMs!.round());

  @override
  void dispose() {
    _pollTimer?.cancel();
    _stateSubscription?.cancel();
    // Stop the isolated test player when leaving the lab; production playback
    // uses a different engine and is not touched.
    if (_source != null) unawaited(_client.stop().catchError((_) {}));
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
        withData: false,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final path = file.path;
      if (path == null || path.trim().isEmpty) {
        throw StateError(
          'Android did not provide a readable path for this file. Try another local audio file.',
        );
      }
      final uri = path.startsWith('content://') || path.startsWith('file://')
          ? Uri.parse(path)
          : Uri.file(path);
      setState(() {
        _source = uri;
        _fileName = file.name;
      });
      await _client.setSource(uri);
      _stateSubscription ??= _client.states.listen(
        (state) {
          if (!mounted) return;
          setState(() {
            _state = state;
            _volume = state.volume;
            if (state.hasError) _error = state.error ?? 'Media3 reported a playback error.';
          });
        },
        onError: (Object error) {
          if (mounted) setState(() => _error = 'State stream failed: $error');
        },
      );
      _pollTimer ??= Timer.periodic(
        const Duration(milliseconds: 750),
        (_) => _refreshState(),
      );
      final state = await _client.getState();
      if (!mounted) return;
      setState(() {
        _source = uri;
        _fileName = file.name;
        _state = state;
        _volume = state.volume;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshState({bool force = false}) async {
    if (!_hasSource || (_busy && !force)) return;
    try {
      final state = await _client.getState();
      if (mounted) setState(() => _state = state);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _runCommand(
    Future<void> Function() command, {
    String? successMessage,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await command();
      await _refreshState(force: true);
      if (successMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatTime(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 1 << 31);
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  String get _playbackLabel => switch (_state?.playbackState) {
        1 => 'Idle',
        2 => 'Buffering',
        3 => 'Ready',
        4 => 'Ended',
        _ => _state?.connected == true ? 'Connected' : 'Not connected',
      };

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
        body: Center(child: Text('Media3 Engine Lab is only available in debug builds.')),
      );
    }

    final theme = Theme.of(context);
    final maxMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0;
    final currentMs = _position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Media3 Engine Lab'),
        actions: [
          IconButton(
            tooltip: 'Refresh native state',
            onPressed: _busy ? null : _refreshState,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.science_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Isolated native playback test',
                            style: theme.textTheme.titleMedium),
                      ),
                      Chip(label: Text(_playbackLabel)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This uses the experimental AndroidX Media3 service. It does not replace or control Resonate’s normal player.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _pickFile,
                    icon: const Icon(Icons.audio_file_rounded),
                    label: Text(_source == null ? 'Choose local audio file' : 'Choose another file'),
                  ),
                  if (_fileName != null) ...[
                    const SizedBox(height: 12),
                    Text(_fileName!, style: theme.textTheme.titleSmall),
                    SelectableText(_source.toString(),
                        style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatTime(_position)),
                      Text(_state?.duration == null ? '--:--' : _formatTime(_duration)),
                    ],
                  ),
                  Slider(
                    min: 0,
                    max: maxMs,
                    value: currentMs,
                    onChanged: !_hasSource || _duration == Duration.zero
                        ? null
                        : (value) => setState(() => _dragPositionMs = value),
                    onChangeEnd: !_hasSource || _duration == Duration.zero
                        ? null
                        : (value) {
                            setState(() => _dragPositionMs = null);
                            unawaited(_runCommand(
                              () => _client.seekTo(
                                Duration(milliseconds: value.round()),
                              ),
                            ));
                          },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Stop',
                        onPressed: !_hasSource || _busy
                            ? null
                            : () => _runCommand(_client.stop),
                        icon: const Icon(Icons.stop_rounded),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filled(
                        tooltip: _state?.isPlaying == true ? 'Pause' : 'Play',
                        onPressed: !_hasSource || _busy
                            ? null
                            : () => _runCommand(
                                  _state?.isPlaying == true
                                      ? _client.pause
                                      : _client.play,
                                ),
                        icon: Icon(_state?.isPlaying == true
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.volume_down_rounded),
                      Expanded(
                        child: Slider(
                          value: _volume.clamp(0.0, 1.0),
                          onChanged: !_hasSource || _busy
                              ? null
                              : (value) => setState(() => _volume = value),
                          onChangeEnd: !_hasSource || _busy
                              ? null
                              : (value) => _runCommand(() => _client.setVolume(value)),
                        ),
                      ),
                      const Icon(Icons.volume_up_rounded),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Native state', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _stateLine('Service connected', _state?.connected),
                  _stateLine('Playing', _state?.isPlaying),
                  _stateLine('Play when ready', _state?.playWhenReady),
                  _stateLine('Playback state', _playbackLabel),
                  _stateLine('Duration known', _state?.duration != null),
                  _stateLine('Native error flag', _state?.hasError),
                  if (_state?.error != null && _state!.error!.isNotEmpty)
                    SelectableText(_state!.error!),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  'Last error\n$_error',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('Clear error'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Test checklist: load a file, play/pause, seek, stop, lock the screen, try notification controls, then test audio focus and Bluetooth controls. Record device model and Android version with any failures.',
          ),
        ],
      ),
    );
  }

  Widget _stateLine(String label, bool? value) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        trailing: value == null
            ? const Text('—')
            : Icon(
                value ? Icons.check_circle_outline_rounded : Icons.cancel_outlined,
                color: value ? Colors.green : Theme.of(context).colorScheme.outline,
              ),
      );
}
