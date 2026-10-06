import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_type.dart';

/// Persists optional user-selected folders for speech/content modes.
///
/// Folder selection is opt-in. An empty assignment means the normal
/// MediaClassifier remains responsible for automatic classification.
class MediaFolderStore {
  static const _key = 'resonate_modes_media_folders_v1';

  static const supportedTypes = <MediaType>[
    MediaType.podcast,
    MediaType.motivation,
    MediaType.audiobook,
  ];

  Future<Map<MediaType, List<String>>> loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return _empty();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _empty();

      final result = _empty();
      for (final type in supportedTypes) {
        final value = decoded[type.storageKey];
        if (value is List) {
          result[type] = value
              .whereType<String>()
              .map(_normalize)
              .where((path) => path.isNotEmpty)
              .toSet()
              .toList();
        }
      }
      return result;
    } catch (_) {
      return _empty();
    }
  }

  Future<void> saveAll(Map<MediaType, List<String>> folders) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = <String, dynamic>{};
      for (final type in supportedTypes) {
        encoded[type.storageKey] = (folders[type] ?? [])
            .map(_normalize)
            .where((path) => path.isNotEmpty)
            .toSet()
            .toList();
      }
      await prefs.setString(_key, jsonEncode(encoded));
    } catch (_) {}
  }

  Future<void> addFolder(MediaType type, String path) async {
    if (!supportedTypes.contains(type)) return;
    final all = await loadAll();
    final normalized = _normalize(path);
    if (normalized.isEmpty) return;
    final folders = all[type] ?? <String>[];
    if (!folders.contains(normalized)) folders.add(normalized);
    all[type] = folders;
    await saveAll(all);
  }

  Future<void> removeFolder(MediaType type, String path) async {
    if (!supportedTypes.contains(type)) return;
    final all = await loadAll();
    final normalized = _normalize(path);
    all[type]?.remove(normalized);
    await saveAll(all);
  }

  Future<void> clearFolders(MediaType type) async {
    if (!supportedTypes.contains(type)) return;
    final all = await loadAll();
    all[type] = <String>[];
    await saveAll(all);
  }

  Map<MediaType, List<String>> _empty() => {
        for (final type in MediaType.values) type: <String>[],
      };

  static String _normalize(String path) {
    var value = path.trim().replaceAll('\\', '/');
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
