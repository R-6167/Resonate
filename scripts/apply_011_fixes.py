from pathlib import Path


def edit(path, fn):
    p = Path(path)
    s = p.read_text()
    ns = fn(s)
    if ns == s:
        raise SystemExit(f'No change made to {path}')
    p.write_text(ns)


def music(s):
    s=s.replace("  DateTime? _lastResumePersist;\n  Future<void> _playOperation", "  DateTime? _lastResumePersist;\n  Timer? _systemVolumePollTimer;\n  String? _lastCompletionSongId;\n  Future<void> _playOperation")
    s=s.replace("    unawaited(_loadPlaybackSettings());\n    unawaited(_restoreQueue());", "    unawaited(_loadPlaybackSettings());\n    _systemVolumePollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => unawaited(_syncSystemVolume()));\n    unawaited(_restoreQueue());")
    old="""      if (state.processingState == ProcessingState.completed) {
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
    new="""      if (state.processingState == ProcessingState.completed) {
        final completedSongId = currentSong?.id;
        // just_audio can replay completed while A/B listeners are rebound.
        // Advance only once per song to prevent competing source loads.
        if (completedSongId == null || completedSongId == _lastCompletionSongId) return;
        _lastCompletionSongId = completedSongId;
        currentPosition = currentDuration ?? currentPosition;
        isPlaying = false;
        notifyListeners();
        _publishServiceState();
        final upcoming = _queueIndex < _queue.length - 1 || _repeatMode == PlaybackRepeatMode.all;
        unawaited(ResonateDiagnostics.record('completion_detected', {
          'songId': completedSongId,
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
    if old not in s: raise SystemExit('completion block not found')
    s=s.replace(old,new)
    s=s.replace("      _queue = nextQueue;\n      _queueIndex = nextIndex;\n      currentSong = _queue[_queueIndex];", "      _queue = nextQueue;\n      _queueIndex = nextIndex;\n      currentSong = _queue[_queueIndex];\n      _lastCompletionSongId = null;")
    s=s.replace("      if (_repeatMode == PlaybackRepeatMode.one) {\n        currentPosition = Duration.zero;", "      if (_repeatMode == PlaybackRepeatMode.one) {\n        _lastCompletionSongId = null;\n        currentPosition = Duration.zero;")
    s=s.replace("      _activeIsA = !_activeIsA; _queueIndex = nextIndex; currentSong = nextSong;", "      _activeIsA = !_activeIsA; _queueIndex = nextIndex; currentSong = nextSong; _lastCompletionSongId = null;")
    s=s.replace("const {'toggle', 'pause', 'stop', 'seek', 'next', 'previous'}", "const {'toggle', 'pause', 'stop', 'seek'}")
    old_recovery="""      if (_completionObservedDuringCrossfade) {
        _completionObservedDuringCrossfade = false;
        if (currentSong?.id == outgoingSong?.id && !isPlaying && !_completionAdvanceInProgress && _queueIndex < _queue.length - 1) {
          await ResonateDiagnostics.record('completion_crossfade_recovery', {
            'songId': currentSong?.id,
            'queueIndex': _queueIndex,
            'reason': 'crossfade_finished_without_commit',
          });
          unawaited(_advanceAfterCompletion());
        }
      }"""
    s=s.replace(old_recovery, "      _completionObservedDuringCrossfade = false;\n")
    old_sync="""        if (max > 0) { _volume = (current / max).clamp(0.0, 1.0).toDouble(); notifyListeners(); }"""
    new_sync="""        if (max > 0) {
          final next = (current / max).clamp(0.0, 1.0).toDouble();
          if ((next - _volume).abs() > 0.001) { _volume = next; notifyListeners(); }
        }"""
    s=s.replace(old_sync,new_sync)
    s=s.replace("  @override void dispose() { _playerStateSubscription", "  @override void dispose() { _systemVolumePollTimer?.cancel(); _playerStateSubscription")
    return s


def library_provider(s):
    s=s.replace("  bool _isScanning = false;", "  bool _isScanning = false;\n  bool _autoScanEnabled = true;\n  int _minimumScanDurationMs = 30000;")
    s=s.replace("  bool get isScanning => _isScanning;", "  bool get isScanning => _isScanning;\n  bool get autoScanEnabled => _autoScanEnabled;\n  int get minimumScanDurationMs => _minimumScanDurationMs;")
    s=s.replace("  Future<void> _autoScanOnStartup() async { try { final granted = await AudioFileService.requestAudioPermission(); if (!granted) return; await scanDeviceAudio(); } catch (e) { debugPrint('Startup audio scan failed: $e'); } }", "  Future<void> _autoScanOnStartup() async { try { final granted = await AudioFileService.requestAudioPermission(); if (!granted || !_autoScanEnabled) return; await scanDeviceAudio(); } catch (e) { debugPrint('Startup audio scan failed: $e'); } }")
    s=s.replace("final songs = await AudioFileService.scanAudioFiles(folderUris: folders.isEmpty ? null : folders.map((folder) => folder['uri']!).toList());", "final songs = await AudioFileService.scanAudioFiles(folderUris: folders.isEmpty ? const <String>[] : folders.map((folder) => folder['uri']!).toList(), minimumDurationMs: _minimumScanDurationMs);")
    s=s.replace("  Future<void> _loadPreferences() async { final prefs = await SharedPreferences.getInstance(); _sortBy = prefs.getString('library_sort_by') ?? 'title'; _filterBy = prefs.getString('library_filter_by') ?? 'all'; }", "  Future<void> setAutoScanEnabled(bool enabled) async { _autoScanEnabled = enabled; final prefs = await SharedPreferences.getInstance(); await prefs.setBool('library_auto_scan', enabled); notifyListeners(); }\n  Future<void> setMinimumScanDuration(int milliseconds) async { _minimumScanDurationMs = milliseconds.clamp(0, 3600000).toInt(); final prefs = await SharedPreferences.getInstance(); await prefs.setInt('library_min_duration_ms', _minimumScanDurationMs); notifyListeners(); }\n  Future<void> _loadPreferences() async { final prefs = await SharedPreferences.getInstance(); _sortBy = prefs.getString('library_sort_by') ?? 'title'; _filterBy = prefs.getString('library_filter_by') ?? 'all'; _autoScanEnabled = prefs.getBool('library_auto_scan') ?? true; _minimumScanDurationMs = prefs.getInt('library_min_duration_ms') ?? 30000; }")
    return s


def audio_service(s):
    s=s.replace("static Future<List<Song>> scanAudioFiles({List<String>? folderUris}) async { if (!await requestAudioPermission()) return []; final folders = folderUris ?? (await getSelectedFolders()).map((folder) => folder['uri']!).toList(); if (folders.isEmpty) return []; try { final result = await _channel.invokeMethod<List<dynamic>>('scanAudio', {'folders': folders});", "static Future<List<Song>> scanAudioFiles({List<String>? folderUris, int minimumDurationMs = 30000}) async { if (!await requestAudioPermission()) return []; final folders = folderUris ?? (await getSelectedFolders()).map((folder) => folder['uri']!).toList(); try { final result = await _channel.invokeMethod<List<dynamic>>('scanAudio', {'folders': folders, 'minimumDurationMs': minimumDurationMs});")
    return s


def main_activity(s):
    s=s.replace('"scanAudio" -> result.success(scanAudio(call.argument<List<String>>("folders") ?: emptyList()))', '"scanAudio" -> result.success(scanAudio(call.argument<List<String>>("folders") ?: emptyList(), call.argument<Int>("minimumDurationMs") ?: 30000))')
    s=s.replace('private fun scanAudio(folders: List<String>): List<Map<String, Any?>> {', 'private fun scanAudio(folders: List<String>, minimumDurationMs: Int): List<Map<String, Any?>> {')
    needle='                val mediaId = cursor.getLong(id)\n                songs.add(mapOf('
    repl='                if (cursor.getLong(duration) < minimumDurationMs.toLong()) continue\n                val mediaId = cursor.getLong(id)\n                songs.add(mapOf('
    if needle not in s: raise SystemExit('scan insertion point not found')
    return s.replace(needle,repl)


def library_screen(s):
    s=s.replace("  @override void initState() { super.initState(); _searchController.addListener(_onSearchChanged); }", "  bool _hasSelectedFolders = false;\n  @override void initState() { super.initState(); _searchController.addListener(_onSearchChanged); _refreshFolderVisibility(); }\n  Future<void> _refreshFolderVisibility() async { final folders = await AudioFileService.getSelectedFolders(); if (mounted) setState(() => _hasSelectedFolders = folders.isNotEmpty); }")
    if "../services/audio_file_service.dart" not in s:
        s=s.replace("import '../providers/playlist_provider.dart';", "import '../providers/playlist_provider.dart';\nimport '../services/audio_file_service.dart';")
    s=s.replace("    await context.read<LibraryProvider>().loadAllSongs();\n  }", "    await context.read<LibraryProvider>().loadAllSongs();\n    await _refreshFolderVisibility();\n  }", 1)
    s=s.replace("        IconButton(tooltip: 'Choose music folders', icon: const Icon(Icons.folder_open_rounded), onPressed: _chooseFolders),\n", "")
    old="""        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Card(child: ListTile(leading: const Icon(Icons.folder_open_rounded), title: const Text('Choose music folders'), subtitle: const Text('Limit scanning to folders you select on this device.'), trailing: const Icon(Icons.chevron_right_rounded), onTap: _chooseFolders))),"""
    new="""        if (!_hasSelectedFolders) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Card(child: ListTile(leading: const Icon(Icons.folder_open_rounded), title: const Text('Choose a music folder'), subtitle: const Text('Optional — tap to limit future scans to a folder.'), trailing: const Icon(Icons.chevron_right_rounded), onTap: _chooseFolders))),"""
    if old not in s: raise SystemExit('library card not found')
    return s.replace(old,new)


def library_management(s):
    marker="""        const SizedBox(height: 14),
        Card(child: ListTile(leading: const Icon(Icons.music_note_rounded),"""
    insert="""        const SizedBox(height: 14),
        Card(
          child: Consumer<LibraryProvider>(
            builder: (_, current, __) => Column(children: [
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.auto_awesome_rounded),
                title: const Text('Scan music automatically'),
                subtitle: const Text('Scan local audio when Resonate starts. Selected folders are used when you add a folder restriction.'),
                value: current.autoScanEnabled,
                onChanged: current.setAutoScanEnabled,
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Minimum audio length'),
                subtitle: Text(_durationLabel(current.minimumScanDurationMs)),
                trailing: DropdownButton<int>(
                  value: [0, 30000, 60000, 120000, 300000, 600000].contains(current.minimumScanDurationMs) ? current.minimumScanDurationMs : 30000,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Any length')),
                    DropdownMenuItem(value: 30000, child: Text('30 seconds')),
                    DropdownMenuItem(value: 60000, child: Text('1 minute')),
                    DropdownMenuItem(value: 120000, child: Text('2 minutes')),
                    DropdownMenuItem(value: 300000, child: Text('5 minutes')),
                    DropdownMenuItem(value: 600000, child: Text('10 minutes')),
                  ],
                  onChanged: (value) { if (value != null) current.setMinimumScanDuration(value); },
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        Card(child: ListTile(leading: const Icon(Icons.music_note_rounded),"""
    if marker not in s: raise SystemExit('management marker not found')
    s=s.replace(marker,insert)
    return s.replace("  @override Widget build(BuildContext context) {", "  String _durationLabel(int ms) { if (ms <= 0) return 'Include audio of any length.'; final seconds = ms ~/ 1000; if (seconds < 60) return 'Only audio at least $seconds seconds long.'; final minutes = seconds ~/ 60; return 'Only audio at least $minutes minute${minutes == 1 ? '' : 's'} long.'; }\n\n  @override Widget build(BuildContext context) {")


def diagnostics(s):
    return s.replace("final uri = Uri(\n      scheme: 'mailto',", "final uri = Uri(\n      scheme: 'mailto',\n      path: 'innotrepid@gmail.com',")


def player(s):
    start=s.index('  Future<void> _showVolume(')
    end=s.index('  Future<void> _showMoreOptions(', start)
    method="""  Future<void> _showVolume(BuildContext context, MusicProvider music) async {
    await showModalBottomSheet<void>(
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

"""
    return s[:start]+method+s[end:]


edit('lib/providers/music_provider.dart', music)
edit('lib/providers/library_provider.dart', library_provider)
edit('lib/services/audio_file_service.dart', audio_service)
edit('android/app/src/main/kotlin/com/example/resonate/MainActivity.kt', main_activity)
edit('lib/screens/library_screen.dart', library_screen)
edit('lib/screens/library_management_screen.dart', library_management)
edit('lib/screens/diagnostics_screen.dart', diagnostics)
edit('lib/screens/player_screen.dart', player)
edit('pubspec.yaml', lambda s: s.replace('version: 0.1.0+1', 'version: 0.1.1+2'))
