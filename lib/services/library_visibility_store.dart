import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single visibility authority shared by Library, Intelligence and playback.
/// The database intentionally retains songs outside the selected folders so
/// listening history and learned evidence are not destroyed.
class LibraryVisibilityStore extends ChangeNotifier {
  static const String restrictedSongIdsKey = 'library_restricted_song_ids';
  static final LibraryVisibilityStore instance = LibraryVisibilityStore._();

  Set<String>? _restrictedSongIds;
  bool _loaded = false;

  LibraryVisibilityStore._();

  Set<String>? get restrictedSongIds => _restrictedSongIds == null ? null : Set.unmodifiable(_restrictedSongIds!);
  bool get isRestricted => _restrictedSongIds != null;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(restrictedSongIdsKey);
    _restrictedSongIds = ids == null ? null : ids.toSet();
    _loaded = true;
    notifyListeners();
  }

  Future<void> setRestrictedSongIds(Set<String>? ids) async {
    final prefs = await SharedPreferences.getInstance();
    _restrictedSongIds = ids == null ? null : Set<String>.from(ids);
    _loaded = true;
    if (_restrictedSongIds == null) {
      await prefs.remove(restrictedSongIdsKey);
    } else {
      await prefs.setStringList(restrictedSongIdsKey, _restrictedSongIds!.toList());
    }
    notifyListeners();
  }

  bool isVisible(String songId) => _restrictedSongIds == null || _restrictedSongIds!.contains(songId);

  List<T> filter<T>(Iterable<T> items, String Function(T item) idOf) {
    if (_restrictedSongIds == null) return List<T>.from(items);
    return items.where((item) => _restrictedSongIds!.contains(idOf(item))).toList();
  }
}
