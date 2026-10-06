#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "lib/widgets/mode_shelf_card.dart"
t = p.read_text()

t = t.replace("Icons.shelves", "Icons.playlist_play_rounded")

old_play = """                          onTap: () {
                            final music = context.read<MusicProvider>();
                            final idx = tracks.indexWhere((x) => x.id == s.id);
                            PlaybackAuthority.instance.userPlay(
                              () => music.playSong(
                                s,
                                queue: tracks,
                                startIndex: idx < 0 ? 0 : idx,
                              ),
                            );
                          },
"""
new_play = """                          onTap: () {
                            final music = context.read<MusicProvider>();
                            final idx = tracks.indexWhere((x) => x.id == s.id);
                            PlaybackAuthority.instance.markExternalUserCommand(
                              'mode_shelf',
                              'play_track',
                            );
                            unawaited(music.playSong(
                              s,
                              queue: tracks,
                              startIndex: idx < 0 ? 0 : idx,
                            ));
                          },
"""
if old_play in t:
    t = t.replace(old_play, new_play, 1)
    print("track play fixed")
else:
    print("WARN track play pattern")

old_shelf = """                      FilledButton.tonalIcon(
                        onPressed: () {
                          final music = context.read<MusicProvider>();
                          PlaybackAuthority.instance.userPlay(
                            () => music.playSong(
                              tracks.first,
                              queue: tracks,
                              startIndex: 0,
                            ),
                          );
                        },
"""
new_shelf = """                      FilledButton.tonalIcon(
                        onPressed: () {
                          final music = context.read<MusicProvider>();
                          PlaybackAuthority.instance.markExternalUserCommand(
                            'mode_shelf',
                            'play_shelf',
                          );
                          unawaited(music.playSong(
                            tracks.first,
                            queue: tracks,
                            startIndex: 0,
                          ));
                        },
"""
if old_shelf in t:
    t = t.replace(old_shelf, new_shelf, 1)
    print("shelf play fixed")
else:
    print("WARN shelf play pattern")

if "import 'dart:async';" not in t:
    t = "import 'dart:async';\n" + t

p.write_text(t)
print("done")
