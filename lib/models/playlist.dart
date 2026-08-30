class Playlist {
  final String id;
  final String name;
  final List<String> songIds;
  final DateTime createdAt;
  final String? description;

  Playlist({
    required this.id,
    required this.name,
    required this.songIds,
    required this.createdAt,
    this.description,
  });

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map['id'] as String,
      name: map['name'] as String,
      songIds: [],
      createdAt: DateTime.parse(map['created_at'] as String),
      description: map['description'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt.toIso8601String(),
      'description': description,
    };
  }
}
