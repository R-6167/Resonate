import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/music_provider.dart';
import '../services/lyrics_service.dart';

class LyricsScreen extends StatefulWidget {
  const LyricsScreen({super.key, required this.song});
  final Song song;

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  final LyricsService _service = const LyricsService();
  final Map<int, GlobalKey> _lineKeys = <int, GlobalKey>{};
  late final MusicProvider _music;
  late Future<LyricsDocument?> _lyrics;
  late Song _activeSong;
  String? _observedSongId;
  int _lastActiveIndex = -2;

  @override
  void initState() {
    super.initState();
    _music = context.read<MusicProvider>();
    _activeSong = _music.currentSong ?? widget.song;
    _observedSongId = _activeSong.id;
    _lyrics = _service.loadForSong(_activeSong);
    _music.addListener(_handleMusicChanged);
  }

  void _handleMusicChanged() {
    final current = _music.currentSong;
    if (current == null || current.id == _observedSongId || !mounted) return;
    setState(() {
      _activeSong = current;
      _observedSongId = current.id;
      _lyrics = _service.loadForSong(current);
      _lastActiveIndex = -2;
      _lineKeys.clear();
    });
  }

  @override
  void dispose() {
    _music.removeListener(_handleMusicChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final position = context.select<MusicProvider, Duration>((music) => music.currentPosition);
    final song = _activeSong;

    return Scaffold(
      appBar: AppBar(title: Text('Lyrics · ${song.title}', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: FutureBuilder<LyricsDocument?>(
        future: _lyrics,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final document = snapshot.data;
          if (document == null || document.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lyrics_outlined, size: 52, color: colors.primary),
                    const SizedBox(height: 14),
                    Text('No local lyrics found', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Place a sidecar .lrc or .txt file beside the audio file to show lyrics offline.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          }

          final activeIndex = document.isTimed
              ? document.lines.lastIndexWhere(
                  (line) => line.timestamp != null && line.timestamp! <= position,
                )
              : -1;

          if (activeIndex >= 0 && activeIndex != _lastActiveIndex) {
            _lastActiveIndex = activeIndex;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final lineContext = _lineKeys[activeIndex]?.currentContext;
              if (lineContext != null) {
                Scrollable.ensureVisible(
                  lineContext,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: 0.45,
                );
              }
            });
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
            itemCount: document.lines.length,
            itemBuilder: (context, index) {
              final line = document.lines[index];
              final active = index == activeIndex;
              final lineKey = _lineKeys.putIfAbsent(index, GlobalKey.new);
              return Padding(
                key: lineKey,
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 160),
                  style: Theme.of(context).textTheme.titleMedium!.copyWith(
                    height: 1.35,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                    color: active ? colors.primary : colors.onSurfaceVariant,
                  ),
                  child: Text(line.text, textAlign: TextAlign.center),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
