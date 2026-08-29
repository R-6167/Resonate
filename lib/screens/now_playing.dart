import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../providers/library_provider.dart';
import '../models/song.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({Key? key}) : super(key: key);

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _animController.repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final music = Provider.of<MusicProvider>(context);
    final library = Provider.of<LibraryProvider>(context);
    final song = music.currentSong;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Now playing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music),
            onPressed: () async {
              // show queue modal
              await showModalBottomSheet(
                context: context,
                builder: (ctx) {
                  final queue = library.allSongs; // simple queue for now
                  return ReorderableListView(
                    onReorder: (oldIndex, newIndex) {
                      // placeholder: reordering logic to be implemented in QueueProvider
                    },
                    children: [
                      for (int i = 0; i < queue.length; i++)
                        ListTile(key: ValueKey(queue[i].id), title: Text(queue[i].title), subtitle: Text(queue[i].artist)),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            width: double.infinity,
            height: 300,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Icon(Icons.music_note, size: 96, color: Colors.grey.shade700),
            ),
          ),
          const SizedBox(height: 16),
          if (song != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(song.artist, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Expanded(child: _Visualizer(animController: _animController)),
          _NowPlayingControls(),
        ],
      ),
    );
  }
}

class _Visualizer extends StatefulWidget {
  final AnimationController animController;
  const _Visualizer({Key? key, required this.animController}) : super(key: key);

  @override
  State<_Visualizer> createState() => _VisualizerState();
}

class _VisualizerState extends State<_Visualizer> {
  final _random = Random();

  @override
  Widget build(BuildContext context) {
    final music = Provider.of<MusicProvider>(context);
    return AnimatedBuilder(
      animation: widget.animController,
      builder: (context, child) {
        final playing = music.isPlaying;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(20, (i) {
            final base = playing ? (0.2 + _random.nextDouble() * 0.8) : 0.05 + _random.nextDouble() * 0.05;
            final height = base * MediaQuery.of(context).size.height * 0.25;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Container(width: 6, height: height, color: Colors.indigoAccent),
            );
          }),
        );
      },
    );
  }
}

class _NowPlayingControls extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final music = Provider.of<MusicProvider>(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(icon: const Icon(Icons.skip_previous), onPressed: () {}),
              IconButton(icon: Icon(music.isPlaying ? Icons.pause_circle_filled : Icons.play_circle), iconSize: 56, onPressed: () => music.playPause()),
              IconButton(icon: const Icon(Icons.skip_next), onPressed: () {}),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
