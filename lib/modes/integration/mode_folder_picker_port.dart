/// Lets Modes request a folder pick without depending on Flutter UI plugins.
abstract class ModeFolderPickerPort {
  /// Returns a filesystem path the user selected, or null if cancelled.
  Future<String?> pickFolder({String? title});
}
