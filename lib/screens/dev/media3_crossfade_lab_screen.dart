import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/media3_playback_client.dart';

/// Debug-only UI for stressing the isolated native two-deck crossfade path.
class Media3CrossfadeLabScreen extends StatefulWidget {
  const Media3CrossfadeLabScreen({super.key});

  @override
  State<Media3CrossfadeLabScreen> createState() => _Media3CrossfadeLabScreenState();
}

class _Media3CrossfadeLabScreenState extends State<Media3CrossfadeLabScreen> {
  final Media3PlaybackClient _client = Media3PlaybackClient();
  StreamSubscription<Media3PlaybackState>? _subscription;
  Timer? _timer;
  Media3PlaybackState? _state;
  Uri? _currentUri;
  Uri? _nextUri;
  String? _currentName;
  String? _nextName;
  String _fadeStatus = 'idle';
  String? _error;
  bool _busy = false;
  double _durationSeconds = 5;

  @override
  void initState() {
    super.initState();
    _subscription = _client.states.listen(
      (state) {
        if (mounted) setState(() => _state = state);
      },
      onError: (Object error) {
        if (mounted) setState(() => _error = error.toString());
      },
    );
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    unawaited(_client.cancelCrossfade().catchError((_) {}));
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    try {
      final state = await _client.getState();
      final fade = await _client.getCrossfadeState();
      if (!mounted) return;
      setState(() {
        _state = state;
        _fadeStatus = fade['status']?.toString() ?? 'unknown';
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _pick({required bool incoming}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final path = file.path;
      if (path == null || path.trim().isEmpty) {
        throw StateError('Android did not provide a readable path. Choose another local audio file.');
      }
      final uri = path.startsWith('content://') || path.startsWith('file://')
          ? Uri.parse(path)
          : Uri.file(path);
      if (incoming) {
        await _client.preloadNext(uri);
      } else {
        await _client.setSource(uri);
      }
      if (!mounted) return;
      setState(() {
        if (incoming) {
          _nextUri = uri;
          _nextName = file.name;
        } else {
          _currentUri = uri;
          _currentName = file.name;
          _nextUri = null;
          _nextName = null;
        }
      });
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _command(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('Crossfade Lab is only available in debug builds.')));
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Media3 Crossfade Lab')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Isolated two-deck experiment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  const Text('This is a development-only prototype. It does not use or modify Resonate’s normal just_audio playback. Start the current track, prepare the incoming track, then run the fade.'),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.play_circle_outline_rounded),
                    title: Text(_currentName ?? 'Current track'),
                    subtitle: Text(_state?.isPlaying == true ? 'Playing' : 'Not playing'),
                    trailing: TextButton(
                      onPressed: _busy ? null : () => _pick(incoming: false),
                      child: const Text('Choose'),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.queue_music_rounded),
                    title: Text(_nextName ?? 'Incoming track'),
                    subtitle: Text(_nextName == null ? 'Not prepared' : 'Preload requested'),
                    trailing: TextButton(
                      onPressed: _busy || _currentUri == null ? null : () => _pick(incoming: true),
                      child: const Text('Choose'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: _busy || _currentUri == null ? null : () => _command(_client.play),
                        child: const Text('Play current'),
                      ),
                      FilledButton.tonal(
                        onPressed: _busy || _currentUri == null ? null : () => _command(_client.pause),
                        child: const Text('Pause'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Fade duration: ${_durationSeconds.round()} seconds'),
                  Slider(
                    min: 1,
                    max: 12,
                    divisions: 11,
                    value: _durationSeconds,
                    onChanged: _busy ? null : (value) => setState(() => _durationSeconds = value),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy || _currentUri == null || _nextUri == null || _fadeStatus != 'ready'
                              ? null
                              : () => _command(() => _client.crossfade(
                                    duration: Duration(milliseconds: (_durationSeconds * 1000).round()),
                                  )),
                          icon: const Icon(Icons.compare_arrows_rounded),
                          label: const Text('Crossfade now'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _command(_client.cancelCrossfade),
                        child: const Text('Cancel'),
                      ),
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
                  Text('Live status', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _line('Transition', _fadeStatus),
                  _line('Current position', _format(_state?.position ?? Duration.zero)),
                  _line('Incoming deck', _nextName == null ? 'Not selected' : _fadeStatus == 'ready' ? 'Ready' : _fadeStatus),
                  _line('Playback state', _state?.isPlaying == true ? 'Playing' : 'Paused / idle'),
                  const SizedBox(height: 8),
                  const Text('Stress cases: cancel during fade; start a second fade; rapidly change tracks; lock the screen during a fade; pause or stop during a fade. Listen for dips, spikes, doubled audio and stale track controls.'),
                ],
              ),
            ),
          ),
          if (_error != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText('Error\n$_error', style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Flexible(child: Text(value, textAlign: TextAlign.end)),
          ],
        ),
      );

  String _format(Duration value) {
    final seconds = value.inSeconds.clamp(0, 1 << 31);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
