# Resonate

Resonate is a local-first Android music player built with Flutter. It plays compatible audio files available on your device and provides playback, library management, sound controls, and optional recommendation and DJ features.

## Features

- Local library scanning, folder selection, song search, playlists, favorites, sorting, filters, and possible-duplicate discovery.
- Queue, shuffle/repeat, per-track resume, sleep timer, Bluetooth/media controls, and guarded dual-engine crossfade.
- Equalizer, preamp, bass/width/reverb controls, audio interruption automation, and track-level loudness recommendations.
- Optional DJ Mode with offline analysis and transition planning.
- Local recommendations and Ask Resonate quick actions; Autopilot requires explicit consent before it can mutate playback or queue state.
- Shared audio-reactive spectrum settings for the main visualizer and Ask Resonate orb. Android spectrum capture is optional and may vary by device or audio route; it does not alter the audio signal path.

## Getting started

1. Install and open Resonate on Android.
2. Open **Settings → Scan & folders** and grant media access, then choose folders and scan.
3. Tap a song in Library to play it. Use the search icon in the Library toolbar to search without reserving permanent space for a search field.
4. Open **Settings** to configure Crossfade, Audio automation, Audio leveling, Equalizer, DJ Mode, listening modes, device behavior, and Visualization & Orb.
5. Use **About & How to use** in Settings for an in-app guide and privacy/licensing notes.

## Reliability notes

- Normal playback must remain usable when optional analysis, DJ planning, or spectrum capture is unavailable.
- Listening modes may intentionally restrict crossfade for speech or chapter-based playback.
- Android device manufacturers and audio routes can affect media access, audio focus, Bluetooth recovery, and spectrum availability. Validate these behaviors on target hardware before release.

## License

Original Resonate application code, documentation, branding, and bundled assets are covered by the **Resonate Restricted Use License** in [LICENSE](LICENSE). Third-party dependencies and assets remain under their own licenses. Do not assume that the license for Resonate overrides a dependency's license.
