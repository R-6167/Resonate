import '../models/media_type.dart';

/// Resolves optional user-selected content folders.
///
/// A selected folder is a strong user signal, but it does not make folder
/// selection mandatory. With no matching folder, callers can fall back to the
/// normal MediaClassifier/user-file override pipeline.
class MediaFolderRouter {
  final Map<MediaType, List<String>> _folders;

  MediaFolderRouter(Map<MediaType, List<String>> folders)
      : _folders = {
          for (final entry in folders.entries)
            entry.key: entry.value
                .map(_normalize)
                .where((path) => path.isNotEmpty)
                .toSet()
                .toList(),
        };

  bool hasFolder(MediaType type, String folderPath) =>
      _folders[type]?.contains(_normalize(folderPath)) ?? false;

  MediaType? typeForPath(String filePath) {
    final normalizedFile = _normalize(filePath);
    if (normalizedFile.isEmpty) return null;

    MediaType? bestType;
    var bestLength = -1;

    for (final entry in _folders.entries) {
      for (final folder in entry.value) {
        if (_isInside(normalizedFile, folder) && folder.length > bestLength) {
          bestType = entry.key;
          bestLength = folder.length;
        }
      }
    }
    return bestType;
  }

  List<String> foldersFor(MediaType type) =>
      List.unmodifiable(_folders[type] ?? const <String>[]);

  static bool _isInside(String filePath, String folder) {
    if (filePath == folder) return true;
    return filePath.startsWith('$folder/');
  }

  static String _normalize(String path) {
    var value = path.trim().replaceAll('\\', '/');
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
