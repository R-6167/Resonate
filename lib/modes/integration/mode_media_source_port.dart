import '../../models/song.dart';

/// Host boundary for reading media inside a user-selected Modes folder.
/// These tracks stay separate from the canonical Library's folder scope.
abstract class ModeMediaSourcePort {
  Future<List<Song>> scanFolder(String folderUri);
}
