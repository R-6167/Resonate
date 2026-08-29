# Resonate

Resonate - A feature-rich offline music player built with Flutter.

This repository now contains a functional skeleton for a Flutter music player with:
- Audio playback via just_audio
- Background playback support (just_audio_background + audio_service)
- Local library persistence (sqflite)
- Basic directory scanning (permission_handler + path walk)
- Provider-based state management

What I added
- pubspec.yaml: dependencies for audio, db, permissions
- Models: lib/models/song.dart
- Services: lib/services/database_helper.dart (sqflite-backed)
- Providers: theme, music, equalizer (stub), audio effects (stub), crossfade, visualization
- UI: lib/screens/home_screen.dart with basic playback controls and a scan action
- main.dart updated to initialize just_audio_background

Important next steps (manual)
1. Run `flutter create .` in the repo root if this is not already a full Flutter project. This generates android/ and ios/ folders required to build on device.
2. Run `flutter pub get` to fetch packages.
3. On Android you may need to add runtime permissions and adjust AndroidManifest for storage/Bluetooth/background playback. For scoped storage on Android 11+ additional handling is required — this project includes a simple scanner and will work best on devices/emulators that grant storage access.
4. Test on a device or emulator. Background playback and media notifications require testing on device.

How to run (shortest path)
```bash
# from repo root
flutter create .        # only if platform folders missing
flutter pub get
flutter run -d <device>
```

Caveats and known limitations
- Equalizer and advanced audio effects are placeholders: platform-specific native plugins are required to implement real equalizer/reverb functionality.
- The scanner is a simple file-walk; it may not find files on devices that use scoped storage.
- Background playback is enabled using just_audio_background and audio_service but may require additional Android/iOS manifest configuration.

If you want, next I'll:
- Wire platform-specific equalizer (Android) and Bluetooth device routing (Android/iOS) with recommended plugins.
- Improve the scanner to use MediaStore on Android for robust scanning and to support scoped storage.
- Add crossfade UI and integrate it into MusicProvider using just_audio crossfade APIs where available.
