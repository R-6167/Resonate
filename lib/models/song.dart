import 'package:path/path.dart';

class Song {
  final String id;
  final String title;
  final String artist;
  final String album;
  final int duration; // milliseconds
  final String path;
  final DateTime dateAdded;
  final int playCount;
  final bool isFavorite;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.path,
    required this.dateAdded,
    required this.playCount,
    required this.isFavorite,
  });

  factory Song.fromMap(Map<String, dynamic> m) {
    return Song(
      id: m['id'] as String,
      title: m['title'] as String? ?? '',
      artist: m['artist'] as String? ?? '',
      album: m['album'] as String? ?? '',
      duration: m['duration'] as int? ?? 0,
      path: m['path'] as String? ?? '',
      dateAdded: DateTime.fromMillisecondsSinceEpoch(m['date_added'] as int? ?? 0),
      playCount: m['play_count'] as int? ?? 0,
      isFavorite: (m['is_favorite'] as int? ?? 0) == 1,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'duration': duration,
        'path': path,
        'date_added': dateAdded.millisecondsSinceEpoch,
        'play_count': playCount,
        'is_favorite': isFavorite ? 1 : 0,
      };
}
