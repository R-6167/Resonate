#!/usr/bin/env python3
"""Light copy polish on EQ, Crossfade, and DJ Mode screens."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace(path: Path, old: str, new: str) -> None:
    t = path.read_text()
    if old not in t:
        raise SystemExit(f'pattern miss in {path}')
    path.write_text(t.replace(old, new, 1))
    print('ok', path.relative_to(ROOT))


def main() -> None:
    eq = ROOT / 'lib/screens/equalizer_screen.dart'
    replace(
        eq,
        """                  subtitle: Text(
                    eq.hasHardwareEq
                        ? '10-band studio curve → ${eq.hardwareBandCount} hardware bands'
                        : '10-band studio curve (hardware EQ not attached yet)',
                  ),""",
        """                  subtitle: Text(
                    eq.hasHardwareEq
                        ? 'Shape the tone of your library · ${eq.hardwareBandCount} hardware bands active'
                        : 'Shape the tone of your library · hardware EQ attaches after play starts',
                  ),""",
    )
    replace(
        eq,
        """              Text(
                'Zero is centered. Cuts use digital gain (works to -6 dB without '
                'OEM mute). Boosts use a soft loudness path and stay capped.',
                style: Theme.of(context).textTheme.bodySmall,
              ),""",
        """              Text(
                'Zero is neutral. Cuts are safe down to −6 dB. Soft boosts stay '
                'capped so the phone does not hard-clip. Pair with Effects only if you want colour on top.',
                style: Theme.of(context).textTheme.bodySmall,
              ),""",
    )
    replace(
        eq,
        """                subtitle: const Text(
                  'Experimental. Uses Android DynamicsProcessing when available. '
                  'Leave off if the app stops on play; hardware EQ still works.',
                ),""",
        """                subtitle: const Text(
                  'Optional deeper multi-band path when the device supports it. '
                  'Leave off if play is unstable — the standard hardware EQ still works.',
                ),""",
    )
    replace(
        eq,
        """                subtitle: const Text(
                  'When on, remembers preset per song/artist and reapplies on play.',
                ),""",
        """                subtitle: const Text(
                  'Remembers a preset for a song or artist and brings it back next time they play.',
                ),""",
    )

    cf = ROOT / 'lib/screens/crossfade_screen.dart'
    replace(
        cf,
        """              Text(
                'Blend the end of one track into the beginning of the next using dual engines (A → B).',
                style: Theme.of(context).textTheme.bodyMedium,
              ),""",
        """              Text(
                'Blend one track into the next with two players (A → B). '
                'DJ Mode can refine the handoff when it is on; otherwise this is pure crossfade.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),""",
    )
    replace(
        cf,
        """                    subtitle: const Text(
                      'Engine B loads the next track at volume 0, then both engines '
                      'fade over the duration. After the hand-off, B becomes active '
                      'and A is stopped. User next/pause can cancel a transition.',
                    ),""",
        """                    subtitle: const Text(
                      'The next track loads silently, then both sides fade over your duration. '
                      'After the handoff, only the new track stays active. Skip or pause cancels a transition in progress.',
                    ),""",
    )

    dj = ROOT / 'lib/screens/dj_mode_settings_screen.dart'
    replace(
        dj,
        """              Text(
                'Optional beat, tempo, and harmonic blending on top of dual-engine '
                'crossfade. When off, Resonate behaves exactly like a normal player.',
                style: text.bodyMedium,
              ),""",
        """              Text(
                'Optional beat-aware handoffs, harmonic leans, and transition colour '
                'on top of crossfade. When off, Resonate is a normal offline player — nothing blocked.',
                style: text.bodyMedium,
              ),""",
    )
    replace(
        dj,
        """                subtitle:
                    'Soft reverb glue during DJ crossfades (restored after). Never changes normal play.',""",
        """                subtitle:
                    'Light transition colour (reverb and related presets, picked at random). Restored after; never touches normal play.',""",
    )
    replace(
        dj,
        """                subtitle:
                    'Background BPM/key scan — never blocks play or scan (later steps).',""",
        """                subtitle:
                    'Quiet background BPM / energy / structure scan while idle. Never blocks play.',""",
    )
    replace(
        dj,
        """                    'Step 4: with Harmonic mix on, Intelligence can gently prefer the next '
                    'track when its key is Camelot-compatible with the current one. Soft bias only — '
                    'taste and session still win. Missing keys are neutral. DJ Mode stays optional '
                    'and independent of Intelligence. Beat/tempo handoffs still apply when enabled.',""",
        """                    'With Harmonic mix on, Intelligence may gently prefer Camelot-compatible '
                    'keys. Soft bias only — your taste still wins, missing keys stay neutral. '
                    'DJ Mode is optional and independent of Intelligence. Early skips teach the '
                    'planner which transitions to avoid next time.',""",
    )
    print('polish done')


if __name__ == '__main__':
    main()
