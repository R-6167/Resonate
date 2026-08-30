---
name: 'PR: restore models + providers and audio service'
---

This PR adds core application models and implements more complete provider implementations, a working audio service handler, and fixes a database play-count bug.

What changed

- Added models:
  - lib/models/song.dart
  - lib/models/playlist.dart
- Implemented providers:
  - lib/providers/music_provider.dart (just_audio integration, play/seek/queue/position streams)
  - lib/providers/theme_provider.dart
  - lib/providers/equalizer_provider.dart
  - lib/providers/audio_effects_provider.dart
  - lib/providers/crossfade_provider.dart
  - lib/providers/audio_visualization_provider.dart
- Implemented AudioServiceHandler as a bridge between just_audio and audio_service:
  - lib/services/audio_service_handler.dart
- Fixed database helper play-count update to use sqflite rawUpdate (COALESCE) instead of Firestore FieldValue.increment:
  - lib/services/database_helper.dart
- Fixed LibraryProvider getters (allSongs vs filteredSongs)

Notes and follow-ups

- Provider implementations are functional but minimal; they should be extended to match the full app expectations (background playback, notification control, advanced equalizer processing).
- AudioServiceHandler needs to be registered in app bootstrap (just_audio_background/audio_service init) for background playback and notification support.
- Run `flutter analyze` and `flutter run` locally to verify all screens compile and runtime flows work.

Checklist

- [ ] Verify screens compile with new providers (flutter analyze)
- [ ] Register audio handler at app startup for background playback
- [ ] Manual QA: scan library, play/pause/seek, skip, update favorites, playlists
- [ ] Add unit tests for LibraryProvider/database interactions
