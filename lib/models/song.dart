class Song {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final Duration duration;
  final DateTime dateAdded;
  final String? albumArt;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.filePath,
    required this.duration,
    required this.dateAdded,
    this.albumArt,
  });

  factory Song.fromMap(Map<String, dynamic> map) {
    return Song(
      id: map['id'] as String,
      title: map['title'] as String,
      artist: (map['artist'] as String?) ?? 'Unknown Artist',
      album: (map['album'] as String?) ?? 'Unknown Album',
      filePath: map['file_path'] as String,
      duration: Duration(milliseconds: (map['duration'] as int?) ?? 0),
      dateAdded: map['date_added'] != null
          ? DateTime.parse(map['date_added'] as String)
          : DateTime.now(),
      albumArt: map['album_art'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'file_path': filePath,
      'duration': duration.inMilliseconds,
      'date_added': dateAdded.toIso8601String(),
      'album_art': albumArt,
    };
  }
}
