import '../models/song.dart';

/// Groups tracks that look like duplicates (same title + artist).
class DuplicateGroup {
  final String key;
  final List<Song> songs;

  const DuplicateGroup({required this.key, required this.songs});

  String get title => songs.first.title;
  String get artist => songs.first.artist;
}

class DuplicateDetection {
  static String _norm(String s) {
    var t = s.toLowerCase().trim();
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    t = t.replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]\s*'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  static String _key(Song s) => '${_norm(s.title)}|${_norm(s.artist)}';

  /// Returns groups with 2+ songs sharing title and artist.
  static List<DuplicateGroup> findGroups(List<Song> songs) {
    final byKey = <String, List<Song>>{};
    for (final s in songs) {
      byKey.putIfAbsent(_key(s), () => []).add(s);
    }
    final groups = <DuplicateGroup>[
      for (final e in byKey.entries)
        if (e.value.length >= 2) DuplicateGroup(key: e.key, songs: e.value),
    ];
    groups.sort((a, b) => b.songs.length.compareTo(a.songs.length));
    return groups;
  }
}
