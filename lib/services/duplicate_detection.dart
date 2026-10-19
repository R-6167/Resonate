import '../models/song.dart';

/// Groups tracks that look like duplicates (same title+artist, optional duration).
class DuplicateGroup {
  final String key;
  final List<Song> songs;

  const DuplicateGroup({required this.key, required this.songs});

  String get title => songs.first.title;
  String get artist => songs.first.artist;
}

class DuplicateDetection {
  /// Normalize for comparison: lowercase, collapse whitespace, strip features.
  static String _norm(String s) {
    var t = s.toLowerCase().trim();
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    t = t.replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]\s*'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  static String _key(Song s) {
    return '${_norm(s.title)}|${_norm(s.artist)}';
  }

  /// Returns groups with 2+ songs sharing title+artist.
  static List<DuplicateGroup> findGroups(
    List<Song> songs, {
    bool matchDuration = false,
    Duration durationTolerance = const Duration(seconds: 3),
  }) {
    final byKey = <String, List<Song>>{};
    for (final s in songs) {
      byKey.putIfAbsent(_key(s), () => []).add(s);
    }

    final groups = <DuplicateGroup>[];
    for (final entry in byKey.entries) {
      var list = entry.value;
      if (list.length < 2) continue;

      if (matchDuration) {
        final used = <int>{};
        for (var i = 0; i < list.length; i++) {
          if (used.contains(i)) continue;
          final cluster = <Song>[list[i]];
          used.add(i);
          for (var j = i + 1; j < list.length; j++) {
            if (used.contains(j)) continue;
            final d = (list[i].duration - list[j].duration).abs();
            if (d <= durationTolerance) {
              cluster.add(list[j]);
              used.add(j);
            }
          }
          if (cluster.length >= 2) {
            groups.add(DuplicateGroup(key: entry.key, songs: cluster));
          }
        }
      } else {
        groups.add(DuplicateGroup(key: entry.key, songs: list));
      }
    }

    groups.sort((a, b) => b.songs.length.compareTo(a.songs.length));
    return groups;
  }
}
