#!/usr/bin/env python3
"""Step 4–7: claim focus on play path; policy copy on Crossfade + Settings."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MUSIC = ROOT / 'lib/providers/music_provider.dart'
CROSS = ROOT / 'lib/screens/crossfade_screen.dart'
SETTINGS = ROOT / 'lib/screens/settings_screen.dart'


def try_replace(path: Path, old: str, new: str, label: str) -> bool:
    t = path.read_text()
    if old not in t:
        print('skip', label)
        return False
    path.write_text(t.replace(old, new, 1))
    print('ok', label)
    return True


def main() -> None:
    # Shared helper near _configureAudioSession or after _resumeAfterSystemFocus
    # Insert after _resumeAfterSystemFocus if present, else before _configureAudioSession
    t = MUSIC.read_text()
    helper = '''
  /// Claim media focus before any intentional play. Safe to call often.
  Future<void> _claimAudioFocus({String reason = 'play'}) async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
      unawaited(ResonateDiagnostics.record('audio_focus_claim', {
        'reason': reason,
        'songId': currentSong?.id,
        'userWantsPlaying': _userWantsPlaying,
      }));
    } catch (e) {
      debugPrint('claimAudioFocus ($reason): $e');
    }
  }
'''
    if '_claimAudioFocus' not in t:
        # Place before _configureAudioSession
        marker = '  Future<void> _configureAudioSession() async {'
        if marker in t:
            t = t.replace(marker, helper + '\n' + marker, 1)
            MUSIC.write_text(t)
            print('ok claim_helper')
        else:
            print('skip claim_helper — marker missing')
    else:
        print('skip claim_helper — already present')

    try_replace(
        MUSIC,
        """    // Phase 2: non-crossfade play always on Engine A (rebind if we were on B).
    _ensureEngineA(reason: 'play_song_internal');
    final target = _playerA;
    final targetEq = _equalizerA;
    final targetLoud = _loudnessA;
    final outgoing = null; // never hand off from B on the normal path

    _loadingSource = true;
    _userWantsPlaying = true;""",
        """    // Phase 2: non-crossfade play always on Engine A (rebind if we were on B).
    _ensureEngineA(reason: 'play_song_internal');
    final target = _playerA;
    final targetEq = _equalizerA;
    final targetLoud = _loudnessA;
    final outgoing = null; // never hand off from B on the normal path

    _loadingSource = true;
    _userWantsPlaying = true;
    await _claimAudioFocus(reason: 'play_song_internal');""",
        'claim_on_play_internal',
    )

    # Crossfade screen: mention repeat-one seamless loop
    try_replace(
        CROSS,
        """              Text(
                'Blend one track into the next with two players (A → B). '
                'DJ Mode can refine the handoff when it is on; otherwise this is pure crossfade.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),""",
        """              Text(
                'Blend one track into the next with two players (A → B). '
                'With Repeat one on, the same track loops by crossfading into itself. '
                'DJ Mode can refine next-track handoffs when it is on.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),""",
        'crossfade_repeat_copy',
    )

    try_replace(
        CROSS,
        """                    subtitle: const Text(
                      'The next track loads silently, then both sides fade over your duration. '
                      'After the handoff, only the new track stays active. Skip or pause cancels a transition in progress.',
                    ),""",
        """                    subtitle: const Text(
                      'The next track loads silently, then both sides fade over your duration. '
                      'Repeat one + crossfade loops the current track the same way. '
                      'Skip or pause cancels a transition in progress.',
                    ),""",
        'crossfade_how_copy',
    )

    # Settings: interruptions policy card under Playback
    try_replace(
        SETTINGS,
        """            Card(
              elevation: 0,
              child: ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Audio tools are always available'),
                subtitle: const Text(
                  'Equalizer, Crossfade, DJ Mode, and Effects work from Settings even before you play a song. Open Playback to find DJ Mode.',
                ),
              ),
            ),
            const SizedBox(height: 10),
            _section(context, 'Playback', Icons.play_circle_outline, [
              _item(context, 'Queue', 'View and manage upcoming songs', Icons.queue_music_rounded, const QueueScreen()),
              _item(context, 'Crossfade', 'Transition duration and curve', Icons.compare_arrows_rounded, const CrossfadeScreen()),
              _item(context, 'DJ Mode', 'Optional beat, tempo and harmonic blending', Icons.headphones_rounded, const DjModeSettingsScreen()),
              _item(context, 'Effects', 'Loudness and audio processing', Icons.tune_rounded, const AudioEffectsScreen()),
            ], initiallyExpanded: true),""",
        """            Card(
              elevation: 0,
              child: ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Audio tools are always available'),
                subtitle: const Text(
                  'Equalizer, Crossfade, DJ Mode, and Effects work from Settings even before you play a song. Open Playback to find DJ Mode.',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 0,
              child: ListTile(
                leading: const Icon(Icons.volume_down_rounded),
                title: const Text('Interruptions are automatic'),
                subtitle: const Text(
                  'Calls pause Resonate and resume when they end if you were listening. '
                  'Notifications briefly lower the music, then restore it. '
                  'Unplugging headphones always pauses. Long calls do not auto-resume.',
                ),
                isThreeLine: true,
              ),
            ),
            const SizedBox(height: 10),
            _section(context, 'Playback', Icons.play_circle_outline, [
              _item(context, 'Queue', 'View and manage upcoming songs', Icons.queue_music_rounded, const QueueScreen()),
              _item(context, 'Crossfade', 'Transitions + seamless Repeat one loop', Icons.compare_arrows_rounded, const CrossfadeScreen()),
              _item(context, 'DJ Mode', 'Optional beat, tempo and harmonic blending', Icons.headphones_rounded, const DjModeSettingsScreen()),
              _item(context, 'Effects', 'Loudness and audio processing', Icons.tune_rounded, const AudioEffectsScreen()),
            ], initiallyExpanded: true),""",
        'settings_interruptions_policy',
    )

    print('play focus + policy copy done')


if __name__ == '__main__':
    main()
