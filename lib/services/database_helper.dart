import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/song.dart';
import '../models/playlist.dart';

class DatabaseHelper {
  static const _databaseName = 'resonate.db';
  static const _databaseVersion = 1;

  // Table names
  static const String tableSongs = 'songs';
  static const String tablePlaylists = 'playlists';
  static const String tablePlaylistSongs = 'playlist_songs';
  static const String tableFavorites = 'favorites';

  // Song columns
  static const String columnSongId = 'id';
  static const String columnSongTitle = 'title';
  static const String columnSongArtist = 'artist';
  static const String columnSongAlbum = 'album';
  static const String columnSongFilePath = 'file_path';
  static const String columnSongDuration = 'duration';
  static const String columnSongDateAdded = 'date_added';
  static const String columnSongAlbumArt = 'album_art';
  static const String columnSongPlayCount = 'play_count';
  static const String columnSongLastPlayed = 'last_played';

  // Playlist columns
  static const String columnPlaylistId = 'id';
  static const String columnPlaylistName = 'name';
  static const String columnPlaylistCreatedAt = 'created_at';
  static const String columnPlaylistDescription = 'description';

  // Playlist songs columns
  static const String columnPlaylistSongPlaylistId = 'playlist_id';
  static const String columnPlaylistSongSongId = 'song_id';
  static const String columnPlaylistSongPosition = 'position';

  // Favorites columns
  static const String columnFavoriteSongId = 'song_id';
  static const String columnFavoriteDateAdded = 'date_added';

  static final DatabaseHelper _instance = DatabaseHelper._internal();

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create songs table
    await db.execute('''
      CREATE TABLE $tableSongs (
        $columnSongId TEXT PRIMARY KEY,
        $columnSongTitle TEXT NOT NULL,
        $columnSongArtist TEXT,
        $columnSongAlbum TEXT,
        $columnSongFilePath TEXT NOT NULL UNIQUE,
        $columnSongDuration INTEGER,
        $columnSongDateAdded TEXT,
        $columnSongAlbumArt TEXT,
        $columnSongPlayCount INTEGER DEFAULT 0,
        $columnSongLastPlayed TEXT
      )
    ''');

    // Create playlists table
    await db.execute('''
      CREATE TABLE $tablePlaylists (
        $columnPlaylistId TEXT PRIMARY KEY,
        $columnPlaylistName TEXT NOT NULL,
        $columnPlaylistCreatedAt TEXT NOT NULL,
        $columnPlaylistDescription TEXT
      )
    ''');

    // Create playlist songs junction table
    await db.execute('''
      CREATE TABLE $tablePlaylistSongs (
        $columnPlaylistSongPlaylistId TEXT NOT NULL,
        $columnPlaylistSongSongId TEXT NOT NULL,
        $columnPlaylistSongPosition INTEGER,
        PRIMARY KEY ($columnPlaylistSongPlaylistId, $columnPlaylistSongSongId),
        FOREIGN KEY ($columnPlaylistSongPlaylistId) REFERENCES $tablePlaylists($columnPlaylistId),
        FOREIGN KEY ($columnPlaylistSongSongId) REFERENCES $tableSongs($columnSongId)
      )
    ''');

    // Create favorites table
    await db.execute('''
      CREATE TABLE $tableFavorites (
        $columnFavoriteSongId TEXT PRIMARY KEY,
        $columnFavoriteDateAdded TEXT NOT NULL,
        FOREIGN KEY ($columnFavoriteSongId) REFERENCES $tableSongs($columnSongId)
      )
    ''');

    // Create indexes for better query performance
    await db.execute('CREATE INDEX idx_songs_title ON $tableSongs($columnSongTitle)');
    await db.execute('CREATE INDEX idx_songs_artist ON $tableSongs($columnSongArtist)');
    await db.execute('CREATE INDEX idx_playlists_name ON $tablePlaylists($columnPlaylistName)');
  }

  // Song operations
  Future<int> insertSong(Song song) async {
    final db = await database;
    try {
      return await db.insert(
        tableSongs,
        {
          columnSongId: song.id,
          columnSongTitle: song.title,
          columnSongArtist: song.artist,
          columnSongAlbum: song.album,
          columnSongFilePath: song.filePath,
          columnSongDuration: song.duration.inMilliseconds,
          columnSongDateAdded: song.dateAdded.toIso8601String(),
          columnSongAlbumArt: song.albumArt,
          columnSongPlayCount: 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (e) {
      print('Error inserting song: $e');
      return -1;
    }
  }

  Future<int> insertSongs(List<Song> songs) async {
    final db = await database;
    int count = 0;
    for (var song in songs) {
      try {
        await db.insert(
          tableSongs,
          {
            columnSongId: song.id,
            columnSongTitle: song.title,
            columnSongArtist: song.artist,
            columnSongAlbum: song.album,
            columnSongFilePath: song.filePath,
            columnSongDuration: song.duration.inMilliseconds,
            columnSongDateAdded: song.dateAdded.toIso8601String(),
            columnSongAlbumArt: song.albumArt,
            columnSongPlayCount: 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        count++;
      } catch (e) {
        print('Error inserting song ${song.title}: $e');
      }
    }
    return count;
  }

  Future<List<Song>> getAllSongs() async {
    final db = await database;
    try {
      final maps = await db.query(
        tableSongs,
        orderBy: '$columnSongTitle ASC',
      );
      return List.generate(maps.length, (i) => _songFromMap(maps[i]));
    } catch (e) {
      print('Error fetching all songs: $e');
      return [];
    }
  }

  Future<List<Song>> searchSongs(String query) async {
    final db = await database;
    try {
      final maps = await db.query(
        tableSongs,
        where: '$columnSongTitle LIKE ? OR $columnSongArtist LIKE ? OR $columnSongAlbum LIKE ?',
        whereArgs: ['%$query%', '%$query%', '%$query%'],
        orderBy: '$columnSongTitle ASC',
      );
      return List.generate(maps.length, (i) => _songFromMap(maps[i]));
    } catch (e) {
      print('Error searching songs: $e');
      return [];
    }
  }

  Future<List<Song>> getSongsByArtist(String artist) async {
    final db = await database;
    try {
      final maps = await db.query(
        tableSongs,
        where: '$columnSongArtist = ?',
        whereArgs: [artist],
        orderBy: '$columnSongTitle ASC',
      );
      return List.generate(maps.length, (i) => _songFromMap(maps[i]));
    } catch (e) {
      print('Error fetching songs by artist: $e');
      return [];
    }
  }

  Future<List<Song>> getSongsByAlbum(String album) async {
    final db = await database;
    try {
      final maps = await db.query(
        tableSongs,
        where: '$columnSongAlbum = ?',
        whereArgs: [album],
        orderBy: '$columnSongTitle ASC',
      );
      return List.generate(maps.length, (i) => _songFromMap(maps[i]));
    } catch (e) {
      print('Error fetching songs by album: $e');
      return [];
    }
  }

  Future<int> updateSongPlayCount(String songId) async {
    final db = await database;
    try {
      return await db.update(
        tableSongs,
        {
          columnSongPlayCount: FieldValue.increment(1),
          columnSongLastPlayed: DateTime.now().toIso8601String(),
        },
        where: '$columnSongId = ?',
        whereArgs: [songId],
      );
    } catch (e) {
      print('Error updating play count: $e');
      return -1;
    }
  }

  Future<int> deleteSong(String songId) async {
    final db = await database;
    try {
      return await db.delete(
        tableSongs,
        where: '$columnSongId = ?',
        whereArgs: [songId],
      );
    } catch (e) {
      print('Error deleting song: $e');
      return -1;
    }
  }

  // Playlist operations
  Future<int> insertPlaylist(Playlist playlist) async {
    final db = await database;
    try {
      return await db.insert(tablePlaylists, {
        columnPlaylistId: playlist.id,
        columnPlaylistName: playlist.name,
        columnPlaylistCreatedAt: playlist.createdAt.toIso8601String(),
        columnPlaylistDescription: playlist.description,
      });
    } catch (e) {
      print('Error inserting playlist: $e');
      return -1;
    }
  }

  Future<List<Playlist>> getAllPlaylists() async {
    final db = await database;
    try {
      final maps = await db.query(
        tablePlaylists,
        orderBy: '$columnPlaylistName ASC',
      );
      return List.generate(maps.length, (i) => _playlistFromMap(maps[i]));
    } catch (e) {
      print('Error fetching all playlists: $e');
      return [];
    }
  }

  Future<int> addSongToPlaylist(String playlistId, String songId, int position) async {
    final db = await database;
    try {
      return await db.insert(
        tablePlaylistSongs,
        {
          columnPlaylistSongPlaylistId: playlistId,
          columnPlaylistSongSongId: songId,
          columnPlaylistSongPosition: position,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (e) {
      print('Error adding song to playlist: $e');
      return -1;
    }
  }

  Future<List<Song>> getPlaylistSongs(String playlistId) async {
    final db = await database;
    try {
      final maps = await db.rawQuery(
        'SELECT s.* FROM $tableSongs s '
        'INNER JOIN $tablePlaylistSongs ps ON s.$columnSongId = ps.$columnPlaylistSongSongId '
        'WHERE ps.$columnPlaylistSongPlaylistId = ? '
        'ORDER BY ps.$columnPlaylistSongPosition ASC',
        [playlistId],
      );
      return List.generate(maps.length, (i) => _songFromMap(maps[i]));
    } catch (e) {
      print('Error fetching playlist songs: $e');
      return [];
    }
  }

  Future<int> removeSongFromPlaylist(String playlistId, String songId) async {
    final db = await database;
    try {
      return await db.delete(
        tablePlaylistSongs,
        where: '$columnPlaylistSongPlaylistId = ? AND $columnPlaylistSongSongId = ?',
        whereArgs: [playlistId, songId],
      );
    } catch (e) {
      print('Error removing song from playlist: $e');
      return -1;
    }
  }

  Future<int> deletePlaylist(String playlistId) async {
    final db = await database;
    try {
      // Delete playlist songs first
      await db.delete(
        tablePlaylistSongs,
        where: '$columnPlaylistSongPlaylistId = ?',
        whereArgs: [playlistId],
      );
      // Delete playlist
      return await db.delete(
        tablePlaylists,
        where: '$columnPlaylistId = ?',
        whereArgs: [playlistId],
      );
    } catch (e) {
      print('Error deleting playlist: $e');
      return -1;
    }
  }

  // Favorites operations
  Future<int> addFavorite(String songId) async {
    final db = await database;
    try {
      return await db.insert(
        tableFavorites,
        {
          columnFavoriteSongId: songId,
          columnFavoriteDateAdded: DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (e) {
      print('Error adding favorite: $e');
      return -1;
    }
  }

  Future<List<Song>> getFavoriteSongs() async {
    final db = await database;
    try {
      final maps = await db.rawQuery(
        'SELECT s.* FROM $tableSongs s '
        'INNER JOIN $tableFavorites f ON s.$columnSongId = f.$columnFavoriteSongId '
        'ORDER BY s.$columnSongTitle ASC',
      );
      return List.generate(maps.length, (i) => _songFromMap(maps[i]));
    } catch (e) {
      print('Error fetching favorite songs: $e');
      return [];
    }
  }

  Future<bool> isFavorite(String songId) async {
    final db = await database;
    try {
      final result = await db.query(
        tableFavorites,
        where: '$columnFavoriteSongId = ?',
        whereArgs: [songId],
      );
      return result.isNotEmpty;
    } catch (e) {
      print('Error checking if favorite: $e');
      return false;
    }
  }

  Future<int> removeFavorite(String songId) async {
    final db = await database;
    try {
      return await db.delete(
        tableFavorites,
        where: '$columnFavoriteSongId = ?',
        whereArgs: [songId],
      );
    } catch (e) {
      print('Error removing favorite: $e');
      return -1;
    }
  }

  // Statistics
  Future<Map<String, dynamic>> getStatistics() async {
    final db = await database;
    try {
      final totalSongs = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $tableSongs'),
      ) ?? 0;

      final totalPlaylists = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $tablePlaylists'),
      ) ?? 0;

      final favoriteCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $tableFavorites'),
      ) ?? 0;

      final totalPlayCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT SUM($columnSongPlayCount) FROM $tableSongs'),
      ) ?? 0;

      return {
        'totalSongs': totalSongs,
        'totalPlaylists': totalPlaylists,
        'favoriteCount': favoriteCount,
        'totalPlayCount': totalPlayCount,
      };
    } catch (e) {
      print('Error getting statistics: $e');
      return {
        'totalSongs': 0,
        'totalPlaylists': 0,
        'favoriteCount': 0,
        'totalPlayCount': 0,
      };
    }
  }

  // Helper methods
  Song _songFromMap(Map<String, dynamic> map) {
    return Song(
      id: map[columnSongId],
      title: map[columnSongTitle],
      artist: map[columnSongArtist] ?? 'Unknown Artist',
      album: map[columnSongAlbum] ?? 'Unknown Album',
      filePath: map[columnSongFilePath],
      duration: Duration(milliseconds: map[columnSongDuration] ?? 0),
      dateAdded: DateTime.parse(map[columnSongDateAdded]),
      albumArt: map[columnSongAlbumArt],
    );
  }

  Playlist _playlistFromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map[columnPlaylistId],
      name: map[columnPlaylistName],
      songIds: [],
      createdAt: DateTime.parse(map[columnPlaylistCreatedAt]),
      description: map[columnPlaylistDescription],
    );
  }

  // Database utilities
  Future<void> clearAllData() async {
    final db = await database;
    try {
      await db.delete(tablePlaylistSongs);
      await db.delete(tableFavorites);
      await db.delete(tablePlaylists);
      await db.delete(tableSongs);
    } catch (e) {
      print('Error clearing database: $e');
    }
  }

  Future<void> closeDatabase() async {
    final db = await database;
    await db.close();
  }
}
