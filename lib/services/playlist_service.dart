import '../models/playlist.dart';
import '../models/song.dart';
import 'database_helper.dart';

class PlaylistService {
  final DatabaseHelper _db = DatabaseHelper();

  Future<List<Playlist>> getAllPlaylists() async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseHelper.tablePlaylists,
      orderBy: '${DatabaseHelper.columnPlaylistName} COLLATE NOCASE ASC',
    );
    final playlists = <Playlist>[];
    for (final row in rows) {
      playlists.add(await _withSongIds(row));
    }
    return playlists;
  }

  Future<Playlist?> getPlaylist(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseHelper.tablePlaylists,
      where: '${DatabaseHelper.columnPlaylistId} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _withSongIds(rows.first);
  }

  Future<Playlist?> findByName(String name) async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseHelper.tablePlaylists,
      where: 'LOWER(${DatabaseHelper.columnPlaylistName}) = LOWER(?)',
      whereArgs: [name.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _withSongIds(rows.first);
  }

  Future<Playlist> createPlaylist(String name, {String? description}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Playlist name cannot be empty.');
    final now = DateTime.now();
    final playlist = Playlist(
      id: 'playlist_${now.microsecondsSinceEpoch}',
      name: trimmed,
      songIds: const [],
      createdAt: now,
      description: description?.trim().isEmpty == true ? null : description?.trim(),
    );
    final db = await _db.database;
    await db.insert(DatabaseHelper.tablePlaylists, playlist.toMap());
    return playlist;
  }

  Future<void> renamePlaylist(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Playlist name cannot be empty.');
    final db = await _db.database;
    await db.update(
      DatabaseHelper.tablePlaylists,
      {DatabaseHelper.columnPlaylistName: trimmed},
      where: '${DatabaseHelper.columnPlaylistId} = ?',
      whereArgs: [id],
    );
  }

  Future<void> deletePlaylist(String id) async {
    final db = await _db.database;
    await db.delete(
      DatabaseHelper.tablePlaylistSongs,
      where: '${DatabaseHelper.columnPlaylistSongPlaylistId} = ?',
      whereArgs: [id],
    );
    await db.delete(
      DatabaseHelper.tablePlaylists,
      where: '${DatabaseHelper.columnPlaylistId} = ?',
      whereArgs: [id],
    );
  }

  Future<void> addSong(String playlistId, Song song) async {
    final db = await _db.database;
    final existing = await db.query(
      DatabaseHelper.tablePlaylistSongs,
      where:
          '${DatabaseHelper.columnPlaylistSongPlaylistId} = ? AND ${DatabaseHelper.columnPlaylistSongSongId} = ?',
      whereArgs: [playlistId, song.id],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    final positionRows = await db.rawQuery(
      'SELECT MAX(${DatabaseHelper.columnPlaylistSongPosition}) AS max_position '
      'FROM ${DatabaseHelper.tablePlaylistSongs} WHERE ${DatabaseHelper.columnPlaylistSongPlaylistId} = ?',
      [playlistId],
    );
    final maxPosition = (positionRows.first['max_position'] as int?) ?? -1;
    await db.insert(DatabaseHelper.tablePlaylistSongs, {
      DatabaseHelper.columnPlaylistSongPlaylistId: playlistId,
      DatabaseHelper.columnPlaylistSongSongId: song.id,
      DatabaseHelper.columnPlaylistSongPosition: maxPosition + 1,
    });
  }

  Future<void> addSongs(String playlistId, List<Song> songs) async {
    for (final song in songs) {
      await addSong(playlistId, song);
    }
  }

  Future<Playlist> replaceSongsByName(
    String name,
    List<Song> songs, {
    String? description,
  }) async {
    var playlist = await findByName(name);
    playlist ??= await createPlaylist(name, description: description);
    final playlistId = playlist.id;
    final db = await _db.database;

    await db.transaction((txn) async {
      await txn.delete(
        DatabaseHelper.tablePlaylistSongs,
        where: '${DatabaseHelper.columnPlaylistSongPlaylistId} = ?',
        whereArgs: [playlistId],
      );
      for (var i = 0; i < songs.length; i++) {
        if (songs[i].filePath.trim().isEmpty) continue;
        await txn.insert(DatabaseHelper.tablePlaylistSongs, {
          DatabaseHelper.columnPlaylistSongPlaylistId: playlistId,
          DatabaseHelper.columnPlaylistSongSongId: songs[i].id,
          DatabaseHelper.columnPlaylistSongPosition: i,
        });
      }
    });

    final refreshed = await getPlaylist(playlistId);
    if (refreshed == null) {
      throw StateError('Playlist disappeared while updating.');
    }
    return refreshed;
  }

  Future<void> removeSong(String playlistId, String songId) async {
    final db = await _db.database;
    await db.delete(
      DatabaseHelper.tablePlaylistSongs,
      where:
          '${DatabaseHelper.columnPlaylistSongPlaylistId} = ? AND ${DatabaseHelper.columnPlaylistSongSongId} = ?',
      whereArgs: [playlistId, songId],
    );
    await _normalizePositions(playlistId);
  }

  Future<void> reorderSong(String playlistId, String songId, int newPosition) async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseHelper.tablePlaylistSongs,
      where: '${DatabaseHelper.columnPlaylistSongPlaylistId} = ?',
      whereArgs: [playlistId],
      orderBy: '${DatabaseHelper.columnPlaylistSongPosition} ASC',
    );
    final ids = rows
        .map((row) => row[DatabaseHelper.columnPlaylistSongSongId] as String)
        .toList();
    final oldPosition = ids.indexOf(songId);
    if (oldPosition < 0) return;
    final clamped = newPosition.clamp(0, ids.length - 1);
    final moved = ids.removeAt(oldPosition);
    ids.insert(clamped, moved);

    await db.transaction((txn) async {
      for (var i = 0; i < ids.length; i++) {
        await txn.update(
          DatabaseHelper.tablePlaylistSongs,
          {DatabaseHelper.columnPlaylistSongPosition: i},
          where:
              '${DatabaseHelper.columnPlaylistSongPlaylistId} = ? AND ${DatabaseHelper.columnPlaylistSongSongId} = ?',
          whereArgs: [playlistId, ids[i]],
        );
      }
    });
  }

  Future<List<Song>> getSongs(String playlistId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT s.* FROM ${DatabaseHelper.tableSongs} s '
      'INNER JOIN ${DatabaseHelper.tablePlaylistSongs} ps '
      'ON ps.${DatabaseHelper.columnPlaylistSongSongId} = s.${DatabaseHelper.columnSongId} '
      'WHERE ps.${DatabaseHelper.columnPlaylistSongPlaylistId} = ? '
      'ORDER BY ps.${DatabaseHelper.columnPlaylistSongPosition} ASC',
      [playlistId],
    );
    return rows.map(_songFromMap).toList();
  }

  Future<Playlist> _withSongIds(Map<String, dynamic> row) async {
    final db = await _db.database;
    final playlistId = row[DatabaseHelper.columnPlaylistId] as String;
    final songs = await db.query(
      DatabaseHelper.tablePlaylistSongs,
      columns: [DatabaseHelper.columnPlaylistSongSongId],
      where: '${DatabaseHelper.columnPlaylistSongPlaylistId} = ?',
      whereArgs: [playlistId],
      orderBy: '${DatabaseHelper.columnPlaylistSongPosition} ASC',
    );
    return Playlist(
      id: playlistId,
      name: row[DatabaseHelper.columnPlaylistName] as String,
      songIds: songs
          .map((s) => s[DatabaseHelper.columnPlaylistSongSongId] as String)
          .toList(),
      createdAt: DateTime.parse(row[DatabaseHelper.columnPlaylistCreatedAt] as String),
      description: row[DatabaseHelper.columnPlaylistDescription] as String?,
    );
  }

  Future<void> _normalizePositions(String playlistId) async {
    final db = await _db.database;
    final rows = await db.query(
      DatabaseHelper.tablePlaylistSongs,
      where: '${DatabaseHelper.columnPlaylistSongPlaylistId} = ?',
      whereArgs: [playlistId],
      orderBy: '${DatabaseHelper.columnPlaylistSongPosition} ASC',
    );
    await db.transaction((txn) async {
      for (var i = 0; i < rows.length; i++) {
        await txn.update(
          DatabaseHelper.tablePlaylistSongs,
          {DatabaseHelper.columnPlaylistSongPosition: i},
          where:
              '${DatabaseHelper.columnPlaylistSongPlaylistId} = ? AND ${DatabaseHelper.columnPlaylistSongSongId} = ?',
          whereArgs: [playlistId, rows[i][DatabaseHelper.columnPlaylistSongSongId]],
        );
      }
    });
  }

  Song _songFromMap(Map<String, dynamic> map) => Song(
        id: map[DatabaseHelper.columnSongId] as String,
        title: map[DatabaseHelper.columnSongTitle] as String,
        artist: (map[DatabaseHelper.columnSongArtist] as String?) ?? 'Unknown Artist',
        album: (map[DatabaseHelper.columnSongAlbum] as String?) ?? 'Unknown Album',
        filePath: map[DatabaseHelper.columnSongFilePath] as String,
        duration: Duration(
          milliseconds: (map[DatabaseHelper.columnSongDuration] as int?) ?? 0,
        ),
        dateAdded: DateTime.tryParse(
              (map[DatabaseHelper.columnSongDateAdded] as String?) ?? '',
            ) ??
            DateTime.now(),
        albumArt: map[DatabaseHelper.columnSongAlbumArt] as String?,
      );
}
