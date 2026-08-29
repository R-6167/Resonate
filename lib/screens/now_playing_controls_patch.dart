import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';

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
              IconButton(icon: const Icon(Icons.skip_previous), onPressed: () => music.skipPrevious()),
              IconButton(icon: Icon(music.isPlaying ? Icons.pause_circle_filled : Icons.play_circle), iconSize: 56, onPressed: () => music.playPause()),
              IconButton(icon: const Icon(Icons.skip_next), onPressed: () => music.skipNext()),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
