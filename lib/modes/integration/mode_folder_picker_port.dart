import '../models/media_type.dart';

/// Host-provided folder picker boundary.
///
/// Modes does not depend on Android/iOS file-picker APIs. The main Resonate
/// app supplies the picker and returns the selected folder path.
abstract class ModeFolderPickerPort {
  Future<String?> pickFolder(MediaType type);
}
