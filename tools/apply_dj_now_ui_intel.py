#!/usr/bin/env python3
"""NOW slice: DJ chips UI, energy ranking, queue-head warm analysis."""
from pathlib import Path

# ---------- player_screen: DJ chip in AppBar ----------
P = Path('lib/screens/player_screen.dart')
p = P.read_text()
if "import '../widgets/dj_mode_status_chip.dart';" not in p:
    p = p.replace(
        "import '../widgets/audio_visualization_widget.dart';",
        "import '../widgets/audio_visualization_widget.dart';\nimport '../widgets/dj_mode_status_chip.dart';",
        1,
    )
if 'DjModeStatusChip' not in p:
    old = '''        actions: [
          Consumer<MusicProvider>(
            builder: (_, music, __) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: Chip(
                    avatar: Icon(
                      music.activeEngineLabel == 'A'
                          ? Icons.looks_one_rounded
                          : Icons.looks_two_rounded,
                      size: 17,
                    ),
                    label: Text('Engine ${music.activeEngineLabel}'),
                  ),
                ),
              );
            },
          ),
        ],'''
    new = '''        actions: [
          const DjModeStatusChip(dense: true),
          Consumer<MusicProvider>(
            builder: (_, music, __) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: Chip(
                    avatar: Icon(
                      music.activeEngineLabel == 'A'
                          ? Icons.looks_one_rounded
                          : Icons.looks_two_rounded,
                      size: 17,
                    ),
                    label: Text('Engine ${music.activeEngineLabel}'),
                  ),
                ),
              );
            },
          ),
        ],'''
    if old not in p:
        raise SystemExit('player AppBar actions miss')
    p = p.replace(old, new, 1)
    print('player chip')
P.write_text(p)

# ---------- home: chip on now playing card ----------
H = Path('lib/screens/home_screen.dart')
h = H.read_text()
if "import '../widgets/dj_mode_status_chip.dart';" not in h:
    h = h.replace(
        "import '../widgets/resonate_logo.dart';",
        "import '../widgets/resonate_logo.dart';\nimport '../widgets/dj_mode_status_chip.dart';",
        1,
    )
if 'DjModeStatusChip' not in h:
    old = '''        Card(child: ListTile(
          leading: CircleAvatar(child: Icon(music.isPlaying ? Icons.graphic_eq : Icons.pause_rounded)),
          title: Text(music.currentSong!.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(music.currentSong!.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: FilledButton.tonalIcon(onPressed: () => PlaybackAuthority.instance.userToggle(music), icon: Icon(music.isPlaying ? Icons.pause : Icons.play_arrow), label: Text(music.isPlaying ? 'Pause' : 'Play')),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen())),
        )),'''
    new = '''        Card(child: ListTile(
          leading: CircleAvatar(child: Icon(music.isPlaying ? Icons.graphic_eq : Icons.pause_rounded)),
          title: Text(music.currentSong!.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(music.currentSong!.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              const DjModeStatusChip(dense: true),
            ],
          ),
          isThreeLine: true,
          trailing: FilledButton.tonalIcon(onPressed: () => PlaybackAuthority.instance.userToggle(music), icon: Icon(music.isPlaying ? Icons.pause : Icons.play_arrow), label: Text(music.isPlaying ? 'Pause' : 'Play')),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerScreen())),
        )),'''
    if old not in h:
        # softer: just add chip under AppBar logo area
        if 'const DjModeStatusChip' not in h:
            h = h.replace(
                'appBar: AppBar(title: const ResonateLogo(size: 48)),',
                '''appBar: AppBar(
        title: const ResonateLogo(size: 48),
        actions: const [DjModeStatusChip(dense: true)],
      ),''',
                1,
            )
            print('home appbar chip fallback')
    else:
        h = h.replace(old, new, 1)
        print('home now-playing chip')
H.write_text(h)

# ---------- queue banner ----------
Q = Path('lib/screens/queue_screen.dart')
q = Q.read_text()
if "import '../widgets/dj_mode_status_chip.dart';" not in q:
    q = q.replace(
        "import '../providers/music_provider.dart';",
        "import '../providers/music_provider.dart';\nimport '../widgets/dj_mode_status_chip.dart';",
        1,
    )
if 'DjModeStatusBanner' not in q:
    old = '''          return Column(
            children: [
              if (music.currentSong != null)
                Material('''
    new = '''          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: DjModeStatusBanner(
                  contextLabel:
                      'Next handoff may beat-align and adjust crossfade length.',
                ),
              ),
              if (music.currentSong != null)
                Material('''
    if old not in q:
        raise SystemExit('queue column miss')
    q = q.replace(old, new, 1)
    print('queue banner')
Q.write_text(q)

# ---------- crossfade banner ----------
X = Path('lib/screens/crossfade_screen.dart')
x = X.read_text()
if "import '../widgets/dj_mode_status_chip.dart';" not in x:
    # find a good import anchor
    if "import 'package:provider/provider.dart';" in x:
        x = x.replace(
            "import 'package:provider/provider.dart';",
            "import 'package:provider/provider.dart';\nimport '../widgets/dj_mode_status_chip.dart';",
            1,
        )
if 'DjModeStatusBanner' not in x:
    # after the intro body text paragraph about dual engines
    marker = "'Blend the end of one track into the beginning of the next using dual engines (A → B).'"
    if marker in x:
        # insert banner after the SizedBox following that Text
        old = '''              Text(
                'Blend the end of one track into the beginning of the next using dual engines (A → B).',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),

              Card('''
        new = '''              Text(
                'Blend the end of one track into the beginning of the next using dual engines (A → B).',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              const DjModeStatusBanner(
                contextLabel:
                    'When DJ Mode is on, handoffs may seek to a beat and bias duration.',
              ),
              const SizedBox(height: 12),

              Card('''
        if old in x:
            x = x.replace(old, new, 1)
            print('crossfade banner')
        else:
            print('WARN crossfade insert')
    else:
        print('WARN crossfade marker')
X.write_text(x)

# ---------- intelligence: energy soft boost + half/double bpm ----------
IDE = Path('lib/services/intelligence_decision_engine.dart')
ide = IDE.read_text()
if 'energy soft' not in ide and 'cand.energy' not in ide:
    old = '''          if (currentDj.hasUsableBpm && cand.hasUsableBpm) {
            final a = currentDj.bpm!;
            final b = cand.bpm!;
            final rel = (a - b).abs() / a;
            if (rel <= 0.08) {
              value += 1.15;
            } else if (rel <= 0.12) {
              value += 0.55;
            } else if (rel <= 0.20) {
              value += 0.2;
            }
          }
        }
      }'''
    new = '''          if (currentDj.hasUsableBpm && cand.hasUsableBpm) {
            final a = currentDj.bpm!;
            final b = cand.bpm!;
            // Prefer near tempo; also respect half/double for cross-genre.
            var rel = (a - b).abs() / a;
            final relHalf = (a - b * 2).abs() / a;
            final relDouble = (a * 2 - b).abs() / (a * 2);
            if (relHalf < rel) rel = relHalf;
            if (relDouble < rel) rel = relDouble;
            if (rel <= 0.055) {
              value += 1.35;
            } else if (rel <= 0.10) {
              value += 0.75;
            } else if (rel <= 0.18) {
              value += 0.3;
            }
          }
          // Soft energy continuity (never a hard filter).
          final ea = currentDj.energy;
          final eb = cand.energy;
          if (ea != null && eb != null && ea > 0 && eb > 0) {
            final ed = (ea - eb).abs();
            if (ed <= 0.12) {
              value += 0.55;
            } else if (ed <= 0.25) {
              value += 0.25;
            } else if (ed >= 0.55) {
              value -= 0.2;
            }
          }
        }
      }'''
    if old not in ide:
        raise SystemExit('ide bpm block miss')
    ide = ide.replace(old, new, 1)
    print('ide energy+bpm')
IDE.write_text(ide)

# ---------- music_provider: warm next queue head when any DJ analysis needed ----------
MP = Path('lib/providers/music_provider.dart')
mp = MP.read_text()
old_warm = '''    // DJ Mode: warm BPM cache for A/B without blocking the preload path.
    if (_djBeatAlignActive && _djAnalysis != null) {
      final cur = currentSong;
      if (cur != null) _djAnalysis!.scheduleAnalyze(cur);
      _djAnalysis!.scheduleAnalyze(next);
    }'''
new_warm = '''    // DJ Mode: priority-warm analysis for current + next queue head (not only idle scan).
    if (_djAnalysis != null &&
        (_djBeatAlignActive || _djTempoMatchActive)) {
      final cur = currentSong;
      if (cur != null) _djAnalysis!.scheduleAnalyze(cur);
      _djAnalysis!.scheduleAnalyze(next);
      // Warm a few upcoming rows so Autopilot/Intelligence handoffs stay ready.
      final start = _queueIndex + 1;
      final end = (start + 4).clamp(0, _queue.length);
      for (var i = start; i < end; i++) {
        if (i == _crossfadeTargetIndex) continue;
        _djAnalysis!.scheduleAnalyze(_queue[i]);
      }
    }'''
if old_warm in mp:
    mp = mp.replace(old_warm, new_warm, 1)
    print('queue head warm')
else:
    print('WARN preload warm miss')
MP.write_text(mp)

print('NOW SLICE APPLY DONE')
