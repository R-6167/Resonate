import '../../models/song.dart';
import '../../services/audio_file_service.dart';

import '../../providers/bluetooth_provider.dart';
import '../../providers/music_provider.dart';
import '../models/media_type.dart';
import 'mode_context_port.dart';
import 'mode_folder_picker_port.dart';
import 'mode_media_source_port.dart';
import 'mode_playback_port.dart';

/// Bridges [BluetoothProvider] car detection into Modes without exposing
/// platform audio APIs to the Modes package core.
class ResonateModeContextPort implements ModeContextPort {
  ResonateModeContextPort(this._bluetooth) {
    _bluetooth.addListener(_forward);
  }

  final BluetoothProvider _bluetooth;
  final List<void Function()> _listeners = <void Function()>[];

  void _forward() {
    for (final l in List<void Function()>.of(_listeners)) {
      l();
    }
  }

  @override
  ModeAudioContext get audioContext {
    if (_bluetooth.audioContext == BluetoothAudioContext.car) {
      return ModeAudioContext.car;
    }
    return ModeAudioContext.unknown;
  }

  @override
  void addListener(void Function() listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  @override
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void dispose() {
    _bluetooth.removeListener(_forward);
    _listeners.clear();
  }
}

/// Soft policy surface: Modes may bias engine behavior but must never force
/// play, resume, or reclaim focus.
class ResonateModePlaybackPort implements ModePlaybackPort {
  ResonateModePlaybackPort(this._music);

  final MusicProvider _music;

  @override
  void applyModePlaybackPolicy({
    required bool crossfadeAllowed,
    required bool shuffleAllowed,
    required bool preciseResume,
  }) {
    _music.applyModePlaybackPolicy(
      crossfadeAllowed: crossfadeAllowed,
      shuffleAllowed: shuffleAllowed,
      preciseResume: preciseResume,
    );
  }
}

/// Platform folder picker for Modes content folders (podcasts, audiobooks, …).
class ResonateModeFolderPickerPort implements ModeFolderPickerPort {
  const ResonateModeFolderPickerPort();

  @override
  Future<String?> pickFolder(MediaType type) async {
    final selected = await AudioFileService.pickModeFolder();
    return selected?['uri'];
  }
}

/// Scans mode folders without changing the canonical Library's selected folders.
class ResonateModeMediaSourcePort implements ModeMediaSourcePort {
  const ResonateModeMediaSourcePort();

  @override
  Future<List<Song>> scanFolder(String folderUri) {
    return AudioFileService.scanAudioFiles(
      folderUris: <String>[folderUri],
      minimumDurationMs: 0,
    );
  }
}
