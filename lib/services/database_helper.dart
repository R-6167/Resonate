import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/song.dart';
import '../models/playlist.dart';

class DatabaseHelper {
  static const _databaseName = 'resonate.db';
  static const _databaseVersion = 2;
  static const String tableListeningEvents = 'listening_events';
  static const String columnEventId = 'id';
static const String columnEventSongId = 'song_id';
static const String columnEventPreviousSongId = 'previous_song_id';
static const String columnEventStartedAt = 'started_at';
static const String columnEventEndedAt = 'ended_at';
static const String columnEventDurationPlayedMs =
    'duration_played_ms';
static const String columnEventSongDurationMs =
    'song_duration_ms';
static const String columnEventCompletionRatio =
    'completion_ratio';
static const String columnEventCompleted = 'completed';
static const String columnEventSkipped = 'skipped';
static const String columnEventSkipPositionMs =
    'skip_position_ms';
  import '../models/listening_event.dart';

  // ---------------------------------------------------------------------------
  // TABLE NAMES
  // ---------------------------------------------------------------------------

  static const String tableSongs = 'songs';
  static const String tablePlaylists = 'playlists';
  static const String tablePlaylistSongs = 'playlist_songs';
  static const String tableFavorites = 'favorites';

  // ---------------------------------------------------------------------------
  // SONG COLUMNS
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // PLAYLIST COLUMNS
  // ---------------------------------------------------------------------------

  static const String columnPlaylistId = 'id';
  static const String columnPlaylistName = 'name';
  static const String columnPlaylistCreatedAt = 'created_at';
  static const String columnPlaylistDescription = 'description';

  // ---------------------------------------------------------------------------
  // PLAYLIST SONG COLUMNS
  // ---------------------------------------------------------------------------

  static const String columnPlaylistSongPlaylistId = 'playlist_id';
  static const String columnPlaylistSongSongId = 'song_id';
  static const String columnPlaylistSongPosition = 'position';

  // ---------------------------------------------------------------------------
  // FAVORITE COLUMNS
  // ---------------------------------------------------------------------------

  static const String columnFavoriteSongId = 'song_id';
  static const String columnFavoriteDateAdded = 'date_added';

  // ---------------------------------------------------------------------------
  // SINGLETON
  // ---------------------------------------------------------------------------

  static final DatabaseHelper _instance = DatabaseHelper._internal();

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  static Database? _database;

  // ---------------------------------------------------------------------------
  // DATABASE
  // ---------------------------------------------------------------------------

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final dbPath = join(databasesPath, _databaseName);

    return openDatabase(
      dbPath,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }
  await db.execute('''
  CREATE TABLE $tableListeningEvents (
    $columnEventId TEXT PRIMARY KEY,
    $columnEventSongId TEXT NOT NULL,
    $columnEventPreviousSongId TEXT,
    $columnEventStartedAt TEXT NOT NULL,
    $columnEventEndedAt TEXT,
    $columnEventDurationPlayedMs INTEGER NOT NULL DEFAULT 0,
    $columnEventSongDurationMs INTEGER NOT NULL DEFAULT 0,
    $columnEventCompletionRatio REAL NOT NULL DEFAULT 0,
    $columnEventCompleted INTEGER NOT NULL DEFAULT 0,
    $columnEventSkipped INTEGER NOT NULL DEFAULT 0,
    $columnEventSkipPositionMs INTEGER,
    FOREIGN KEY ($columnEventSongId)
      REFERENCES $tableSongs($columnSongId)
  )
''');
  await db.execute(
  'CREATE INDEX idx_events_song '
  'ON $tableListeningEvents($columnEventSongId)',
);

await db.execute(
  'CREATE INDEX idx_events_previous_song '
  'ON $tableListeningEvents($columnEventPreviousSongId)',
);

await db.execute(
  'CREATE INDEX idx_events_started_at '
  'ON $tableListeningEvents($columnEventStartedAt)',
);
  return openDatabase(
  dbPath,
  version: _databaseVersion,
  onCreate: _onCreate,
  onUpgrade: _onUpgrade,
);
  Future<void> _onUpgrade(
  Database db,
  int oldVersion,
  int newVersion,
) async {
  if (oldVersion < 2) {
    await db.execute('''
      CREATE TABLE $tableListeningEvents (
        $columnEventId TEXT PRIMARY KEY,
        $columnEventSongId TEXT NOT NULL,
        $columnEventPreviousSongId TEXT,
        $columnEventStartedAt TEXT NOT NULL,
        $columnEventEndedAt TEXT,
        $columnEventDurationPlayedMs INTEGER NOT NULL DEFAULT 0,
        $columnEventSongDurationMs INTEGER NOT NULL DEFAULT 0,
        $columnEventCompletionRatio REAL NOT NULL DEFAULT 0,
        $columnEventCompleted INTEGER NOT NULL DEFAULT 0,
        $columnEventSkipped INTEGER NOT NULL DEFAULT 0,
        $columnEventSkipPositionMs INTEGER,
        FOREIGN KEY ($columnEventSongId)
          REFERENCES $tableSongs($columnSongId)
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_events_song '
      'ON $tableListeningEvents($columnEventSongId)',
    );

    await db.execute(
      'CREATE INDEX idx_events_previous_song '
      'ON $tableListeningEvents($columnEventPreviousSongId)',
    );

    await db.execute(
      'CREATE INDEX idx_events_started_at '
      'ON $tableListeningEvents($columnEventStartedAt)',
    );
  }
}
  Future<int> insertListeningEvent(
  ListeningEvent event,
) async {
  final db = await database;

  return db.insert(
    tableListeningEvents,
    event.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}
  Future<int> updateListeningEvent(
  ListeningEvent event,
) async {
  final db = await database;

  return db.update(
    tableListeningEvents,
    event.toMap(),
    where: '$columnEventId = ?',
    whereArgs: [event.id],
  );
}
  Future<List<ListeningEvent>> getRecentListeningEvents({
  int limit = 100,
}) async {
  final db = await database;

  final maps = await db.query(
    tableListeningEvents,
    orderBy: '$columnEventStartedAt DESC',
    limit: limit,
  );

  return maps
      .map(ListeningEvent.fromMap)
      .toList();
}
  Future<List<Map<String, dynamic>>> getTransitionCounts(
  String songId,
) async {
  final db = await database;

  return db.rawQuery('''
    SELECT
      $columnEventSongId AS next_song_id,
      COUNT(*) AS transition_count
    FROM $tableListeningEvents
    WHERE $columnEventPreviousSongId = ?
    GROUP BY $columnEventSongId
    ORDER BY transition_count DESC
  ''', [songId]);
}

  // ---------------------------------------------------------------------------
  // CREATE DATABASE
  // ---------------------------------------------------------------------------

  Future<void> _onCreate(Database db, int version) async {
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

    await db.execute('''
      CREATE TABLE $tablePlaylists (
        $columnPlaylistId TEXT PRIMARY KEY,
        $columnPlaylistName TEXT NOT NULL,
        $columnPlaylistCreatedAt TEXT NOT NULL,
        $columnPlaylistDescription TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $tablePlaylistSongs (
        $columnPlaylistSongPlaylistId TEXT NOT NULL,
        $columnPlaylistSongSongId TEXT NOT NULL,
        $columnPlaylistSongPosition INTEGER,
        PRIMARY KEY (
          $columnPlaylistSongPlaylistId,
          $columnPlaylistSongSongId
        ),
        FOREIGN KEY ($columnPlaylistSongPlaylistId)
          REFERENCES $tablePlaylists($columnPlaylistId),
        FOREIGN KEY ($columnPlaylistSongSongId)
          REFERENCES $tableSongs($columnSongId)
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableFavorites (
        $columnFavoriteSongId TEXT PRIMARY KEY,
        $columnFavoriteDateAdded TEXT NOT NULL,
        FOREIGN KEY ($columnFavoriteSongId)
          REFERENCES $tableSongs($columnSongId)
      )
    ''');

    // Indexes
    await db.execute(
      'CREATE INDEX idx_songs_title '
      'ON $tableSongs($columnSongTitle)',
    );

    await db.execute(
      'CREATE INDEX idx_songs_artist '
      'ON $tableSongs($columnSongArtist)',
    );

    await db.execute(
      'CREATE INDEX idx_playlists_name '
      'ON $tablePlaylists($columnPlaylistName)',
    );
  }

  // ---------------------------------------------------------------------------
  // SONG OPERATIONS
  // ---------------------------------------------------------------------------

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
          columnSongLastPlayed: null,
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

    for (final song in songs) {
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
            columnSongLastPlayed: null,
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

      return maps.map(_songFromMap).toList();
    } catch (e) {
      print('Error fetching all songs: $e');
      return [];
    }
  }

  Future<List<Song>> searchSongs(String query) async {
    final db = await database;

    try {
      final searchTerm = '%$query%';

      final maps = await db.query(
        tableSongs,
        where: '''
          $columnSongTitle LIKE ?
          OR $columnSongArtist LIKE ?
          OR $columnSongAlbum LIKE ?
        ''',
        whereArgs: [
          searchTerm,
          searchTerm,
          searchTerm,
        ],
        orderBy: '$columnSongTitle ASC',
      );

      return maps.map(_songFromMap).toList();
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

      return maps.map(_songFromMap).toList();
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

      return maps.map(_songFromMap).toList();
    } catch (e) {
      print('Error fetching songs by album: $e');
      return [];
    }
  }

  Future<int> updateSongPlayCount(String songId) async {
    final db = await database;

    try {
      return await db.rawUpdate(
        '''
        UPDATE $tableSongs
        SET
          $columnSongPlayCount =
            COALESCE($columnSongPlayCount, 0) + 1,
          $columnSongLastPlayed = ?
        WHERE $columnSongId = ?
        ''',
        [
          DateTime.now().toIso8601String(),
          songId,
        ],
      );
    } catch (e) {
      print('Error updating play count: $e');
      return -1;
    }
  }

  Future<int> deleteSong(String songId) async {
    final db = await database;

    try {
      // Remove from playlists first.
      await db.delete(
        tablePlaylistSongs,
        where: '$columnPlaylistSongSongId = ?',
        whereArgs: [songId],
      );

      // Remove from favorites.
      await db.delete(
        tableFavorites,
        where: '$columnFavoriteSongId = ?',
        whereArgs: [songId],
      );

      // Finally remove the song.
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

  // ---------------------------------------------------------------------------
  // PLAYLIST OPERATIONS
  // ---------------------------------------------------------------------------

  Future<int> insertPlaylist(Playlist playlist) async {
    final db = await database;

    try {
      return await db.insert(
        tablePlaylists,
        {
          columnPlaylistId: playlist.id,
          columnPlaylistName: playlist.name,
          columnPlaylistCreatedAt:
              playlist.createdAt.toIso8601String(),
          columnPlaylistDescription: playlist.description,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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

      return maps.map(_playlistFromMap).toList();
    } catch (e) {
      print('Error fetching all playlists: $e');
      return [];
    }
  }

  Future<int> addSongToPlaylist(
    String playlistId,
    String songId,
    int position,
  ) async {
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
        '''
        SELECT s.*
        FROM $tableSongs s
        INNER JOIN $tablePlaylistSongs ps
          ON s.$columnSongId = ps.$columnPlaylistSongSongId
        WHERE ps.$columnPlaylistSongPlaylistId = ?
        ORDER BY ps.$columnPlaylistSongPosition ASC
        ''',
        [playlistId],
      );

      return maps.map(_songFromMap).toList();
    } catch (e) {
      print('Error fetching playlist songs: $e');
      return [];
    }
  }

  Future<int> removeSongFromPlaylist(
    String playlistId,
    String songId,
  ) async {
    final db = await database;

    try {
      return await db.delete(
        tablePlaylistSongs,
        where:
            '$columnPlaylistSongPlaylistId = ? '
            'AND $columnPlaylistSongSongId = ?',
        whereArgs: [
          playlistId,
          songId,
        ],
      );
    } catch (e) {
      print('Error removing song from playlist: $e');
      return -1;
    }
  }

  Future<int> deletePlaylist(String playlistId) async {
    final db = await database;

    try {
      await db.delete(
        tablePlaylistSongs,
        where: '$columnPlaylistSongPlaylistId = ?',
        whereArgs: [playlistId],
      );

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

  // ---------------------------------------------------------------------------
  // FAVORITES
  // ---------------------------------------------------------------------------

  Future<int> addFavorite(String songId) async {
    final db = await database;

    try {
      return await db.insert(
        tableFavorites,
        {
          columnFavoriteSongId: songId,
          columnFavoriteDateAdded:
              DateTime.now().toIso8601String(),
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
        '''
        SELECT s.*
        FROM $tableSongs s
        INNER JOIN $tableFavorites f
          ON s.$columnSongId = f.$columnFavoriteSongId
        ORDER BY s.$columnSongTitle ASC
        ''',
      );

      return maps.map(_songFromMap).toList();
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
        limit: 1,
      );

      return result.isNotEmpty;
    } catch (e) {
      print('Error checking favorite: $e');
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

  // ---------------------------------------------------------------------------
  // STATISTICS
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> getStatistics() async {
    final db = await database;

    try {
      final totalSongs = Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM $tableSongs',
            ),
          ) ??
          0;

      final totalPlaylists = Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM $tablePlaylists',
            ),
          ) ??
          0;

      final favoriteCount = Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM $tableFavorites',
            ),
          ) ??
          0;

      final totalPlayCount = Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COALESCE(SUM($columnSongPlayCount), 0) '
              'FROM $tableSongs',
            ),
          ) ??
          0;

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

  // ---------------------------------------------------------------------------
  // MAP CONVERSIONS
  // ---------------------------------------------------------------------------

  Song _songFromMap(Map<String, dynamic> map) {
    final dateAddedString =
        map[columnSongDateAdded]?.toString();

    DateTime dateAdded;

    if (dateAddedString != null && dateAddedString.isNotEmpty) {
      dateAdded =
          DateTime.tryParse(dateAddedString) ?? DateTime.now();
    } else {
      dateAdded = DateTime.now();
    }

    return Song(
      id: map[columnSongId]?.toString() ?? '',
      title: map[columnSongTitle]?.toString() ?? 'Unknown Title',
      artist:
          map[columnSongArtist]?.toString() ?? 'Unknown Artist',
      album:
          map[columnSongAlbum]?.toString() ?? 'Unknown Album',
      filePath:
          map[columnSongFilePath]?.toString() ?? '',
      duration: Duration(
        milliseconds:
            (map[columnSongDuration] as num?)?.toInt() ?? 0,
      ),
      dateAdded: dateAdded,
      albumArt: map[columnSongAlbumArt]?.toString(),
    );
  }

  Playlist _playlistFromMap(Map<String, dynamic> map) {
    final createdAtString =
        map[columnPlaylistCreatedAt]?.toString();

    return Playlist(
      id: map[columnPlaylistId]?.toString() ?? '',
      name: map[columnPlaylistName]?.toString() ?? 'Untitled Playlist',
      songIds: const [],
      createdAt:
          DateTime.tryParse(createdAtString ?? '') ??
              DateTime.now(),
      description:
          map[columnPlaylistDescription]?.toString(),
    );
  }

  // ---------------------------------------------------------------------------
  // DATABASE UTILITIES
  // ---------------------------------------------------------------------------

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
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
