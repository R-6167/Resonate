import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/song.dart';
import '../models/playlist.dart';
import '../models/listening_event.dart';

class DatabaseHelper {
  static const _databaseName = 'resonate.db';
  static const _databaseVersion = 2;
  static const String tableSongs = 'songs';
  static const String tablePlaylists = 'playlists';
  static const String tablePlaylistSongs = 'playlist_songs';
  static const String tableFavorites = 'favorites';
  static const String tableListeningEvents = 'listening_events';
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
  static const String columnPlaylistId = 'id';
  static const String columnPlaylistName = 'name';
  static const String columnPlaylistCreatedAt = 'created_at';
  static const String columnPlaylistDescription = 'description';
  static const String columnPlaylistSongPlaylistId = 'playlist_id';
  static const String columnPlaylistSongSongId = 'song_id';
  static const String columnPlaylistSongPosition = 'position';
  static const String columnFavoriteSongId = 'song_id';
  static const String columnFavoriteDateAdded = 'date_added';
  static const String columnEventId = 'id';
  static const String columnEventSongId = 'song_id';
  static const String columnEventPreviousSongId = 'previous_song_id';
  static const String columnEventStartedAt = 'started_at';
  static const String columnEventEndedAt = 'ended_at';
  static const String columnEventDurationPlayedMs = 'duration_played_ms';
  static const String columnEventSongDurationMs = 'song_duration_ms';
  static const String columnEventCompletionRatio = 'completion_ratio';
  static const String columnEventCompleted = 'completed';
  static const String columnEventSkipped = 'skipped';
  static const String columnEventSkipPositionMs = 'skip_position_ms';
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();
  static Database? _database;
  Future<Database> get database async => _database ??= await _initDatabase();
  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    return openDatabase(join(databasesPath, _databaseName), version: _databaseVersion, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('CREATE TABLE $tableSongs ($columnSongId TEXT PRIMARY KEY, $columnSongTitle TEXT NOT NULL, $columnSongArtist TEXT, $columnSongAlbum TEXT, $columnSongFilePath TEXT NOT NULL UNIQUE, $columnSongDuration INTEGER, $columnSongDateAdded TEXT, $columnSongAlbumArt TEXT, $columnSongPlayCount INTEGER DEFAULT 0, $columnSongLastPlayed TEXT)');
    await db.execute('CREATE TABLE $tablePlaylists ($columnPlaylistId TEXT PRIMARY KEY, $columnPlaylistName TEXT NOT NULL, $columnPlaylistCreatedAt TEXT NOT NULL, $columnPlaylistDescription TEXT)');
    await db.execute('CREATE TABLE $tablePlaylistSongs ($columnPlaylistSongPlaylistId TEXT NOT NULL, $columnPlaylistSongSongId TEXT NOT NULL, $columnPlaylistSongPosition INTEGER, PRIMARY KEY ($columnPlaylistSongPlaylistId, $columnPlaylistSongSongId), FOREIGN KEY ($columnPlaylistSongPlaylistId) REFERENCES $tablePlaylists($columnPlaylistId), FOREIGN KEY ($columnPlaylistSongSongId) REFERENCES $tableSongs($columnSongId))');
    await db.execute('CREATE TABLE $tableFavorites ($columnFavoriteSongId TEXT PRIMARY KEY, $columnFavoriteDateAdded TEXT NOT NULL, FOREIGN KEY ($columnFavoriteSongId) REFERENCES $tableSongs($columnSongId))');
    await db.execute('CREATE TABLE $tableListeningEvents ($columnEventId TEXT PRIMARY KEY, $columnEventSongId TEXT NOT NULL, $columnEventPreviousSongId TEXT, $columnEventStartedAt TEXT NOT NULL, $columnEventEndedAt TEXT, $columnEventDurationPlayedMs INTEGER NOT NULL DEFAULT 0, $columnEventSongDurationMs INTEGER NOT NULL DEFAULT 0, $columnEventCompletionRatio REAL NOT NULL DEFAULT 0, $columnEventCompleted INTEGER NOT NULL DEFAULT 0, $columnEventSkipped INTEGER NOT NULL DEFAULT 0, $columnEventSkipPositionMs INTEGER, FOREIGN KEY ($columnEventSongId) REFERENCES $tableSongs($columnSongId))');
    for (final sql in ['CREATE INDEX idx_songs_title ON $tableSongs($columnSongTitle)', 'CREATE INDEX idx_songs_artist ON $tableSongs($columnSongArtist)', 'CREATE INDEX idx_playlists_name ON $tablePlaylists($columnPlaylistName)', 'CREATE INDEX idx_events_song ON $tableListeningEvents($columnEventSongId)', 'CREATE INDEX idx_events_previous_song ON $tableListeningEvents($columnEventPreviousSongId)', 'CREATE INDEX idx_events_started_at ON $tableListeningEvents($columnEventStartedAt)']) { await db.execute(sql); }
  }
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('CREATE TABLE $tableListeningEvents ($columnEventId TEXT PRIMARY KEY, $columnEventSongId TEXT NOT NULL, $columnEventPreviousSongId TEXT, $columnEventStartedAt TEXT NOT NULL, $columnEventEndedAt TEXT, $columnEventDurationPlayedMs INTEGER NOT NULL DEFAULT 0, $columnEventSongDurationMs INTEGER NOT NULL DEFAULT 0, $columnEventCompletionRatio REAL NOT NULL DEFAULT 0, $columnEventCompleted INTEGER NOT NULL DEFAULT 0, $columnEventSkipped INTEGER NOT NULL DEFAULT 0, $columnEventSkipPositionMs INTEGER, FOREIGN KEY ($columnEventSongId) REFERENCES $tableSongs($columnSongId))');
      for (final sql in ['CREATE INDEX idx_events_song ON $tableListeningEvents($columnEventSongId)', 'CREATE INDEX idx_events_previous_song ON $tableListeningEvents($columnEventPreviousSongId)', 'CREATE INDEX idx_events_started_at ON $tableListeningEvents($columnEventStartedAt)']) { await db.execute(sql); }
    }
  }
  Future<int> insertListeningEvent(ListeningEvent event) async { try { return await (await database).insert(tableListeningEvents, event.toMap(), conflictAlgorithm: ConflictAlgorithm.replace); } catch (e) { print('Error inserting listening event: $e'); return -1; } }
  Future<int> updateListeningEvent(ListeningEvent event) async { try { return await (await database).update(tableListeningEvents, event.toMap(), where: '$columnEventId = ?', whereArgs: [event.id]); } catch (e) { print('Error updating listening event: $e'); return -1; } }
  Future<List<ListeningEvent>> getRecentListeningEvents({int limit = 100}) async { try { final maps = await (await database).query(tableListeningEvents, orderBy: '$columnEventStartedAt DESC', limit: limit); return maps.map(ListeningEvent.fromMap).toList(); } catch (e) { print('Error fetching listening events: $e'); return []; } }
  Future<List<ListeningEvent>> getListeningHistory({int limit = 200, int offset = 0}) async { try { final maps = await (await database).query(tableListeningEvents, orderBy: '$columnEventStartedAt DESC', limit: limit, offset: offset); return maps.map(ListeningEvent.fromMap).toList(); } catch (e) { print('Error fetching listening history: $e'); return []; } }
  Future<Map<String, dynamic>> getListeningHistoryStatistics() async { try { final db = await database; final rows = await db.rawQuery('SELECT COUNT(*) AS events, COALESCE(SUM($columnEventDurationPlayedMs),0) AS played_ms, COALESCE(SUM(CASE WHEN $columnEventCompleted = 1 THEN 1 ELSE 0 END),0) AS completed, COALESCE(SUM(CASE WHEN $columnEventSkipped = 1 THEN 1 ELSE 0 END),0) AS skipped FROM $tableListeningEvents'); final r = rows.first; return {'events': (r['events'] as num?)?.toInt() ?? 0, 'playedMs': (r['played_ms'] as num?)?.toInt() ?? 0, 'completed': (r['completed'] as num?)?.toInt() ?? 0, 'skipped': (r['skipped'] as num?)?.toInt() ?? 0}; } catch (e) { return {'events': 0, 'playedMs': 0, 'completed': 0, 'skipped': 0}; } }
  Future<int> clearListeningHistory() async { try { return await (await database).delete(tableListeningEvents); } catch (e) { print('Error clearing listening history: $e'); return -1; } }
  Future<List<Map<String, dynamic>>> getTransitionCounts(String songId) async { try { return await (await database).rawQuery('SELECT $columnEventSongId AS next_song_id, COUNT(*) AS transition_count FROM $tableListeningEvents WHERE $columnEventPreviousSongId = ? GROUP BY $columnEventSongId ORDER BY transition_count DESC', [songId]); } catch (e) { return []; } }
  Future<int> insertSong(Song song) async { try { return await (await database).insert(tableSongs, {columnSongId:song.id,columnSongTitle:song.title,columnSongArtist:song.artist,columnSongAlbum:song.album,columnSongFilePath:song.filePath,columnSongDuration:song.duration.inMilliseconds,columnSongDateAdded:song.dateAdded.toIso8601String(),columnSongAlbumArt:song.albumArt,columnSongPlayCount:0,columnSongLastPlayed:null}, conflictAlgorithm: ConflictAlgorithm.ignore); } catch (e) { print('Error inserting song: $e'); return -1; } }
  Future<int> insertSongs(List<Song> songs) async { final db=await database; var count=0; for(final song in songs){try{await db.insert(tableSongs,{columnSongId:song.id,columnSongTitle:song.title,columnSongArtist:song.artist,columnSongAlbum:song.album,columnSongFilePath:song.filePath,columnSongDuration:song.duration.inMilliseconds,columnSongDateAdded:song.dateAdded.toIso8601String(),columnSongAlbumArt:song.albumArt,columnSongPlayCount:0,columnSongLastPlayed:null},conflictAlgorithm:ConflictAlgorithm.ignore);count++;}catch(e){print('Error inserting song ${song.title}: $e');}} return count; }
  Future<List<Song>> getAllSongs() async { try { return (await (await database).query(tableSongs,orderBy:'$columnSongTitle ASC')).map(_songFromMap).toList(); } catch(e){print('Error fetching all songs: $e');return [];} }
  Future<List<Song>> searchSongs(String query) async { try { final q='%$query%'; return (await (await database).query(tableSongs,where:'$columnSongTitle LIKE ? OR $columnSongArtist LIKE ? OR $columnSongAlbum LIKE ?',whereArgs:[q,q,q],orderBy:'$columnSongTitle ASC')).map(_songFromMap).toList(); }catch(e){return [];} }
  Future<List<Song>> getSongsByArtist(String artist) async { try{return (await (await database).query(tableSongs,where:'$columnSongArtist = ?',whereArgs:[artist],orderBy:'$columnSongTitle ASC')).map(_songFromMap).toList();}catch(e){return [];} }
  Future<List<Song>> getSongsByAlbum(String album) async { try{return (await (await database).query(tableSongs,where:'$columnSongAlbum = ?',whereArgs:[album],orderBy:'$columnSongTitle ASC')).map(_songFromMap).toList();}catch(e){return [];} }
  Future<int> updateSongPlayCount(String songId) async { try{return await (await database).rawUpdate('UPDATE $tableSongs SET $columnSongPlayCount=COALESCE($columnSongPlayCount,0)+1,$columnSongLastPlayed=? WHERE $columnSongId=?',[DateTime.now().toIso8601String(),songId]);}catch(e){return -1;} }
  Future<int> deleteSong(String songId) async { try{final db=await database;await db.delete(tableListeningEvents,where:'$columnEventSongId = ? OR $columnEventPreviousSongId = ?',whereArgs:[songId,songId]);await db.delete(tablePlaylistSongs,where:'$columnPlaylistSongSongId = ?',whereArgs:[songId]);await db.delete(tableFavorites,where:'$columnFavoriteSongId = ?',whereArgs:[songId]);return await db.delete(tableSongs,where:'$columnSongId = ?',whereArgs:[songId]);}catch(e){return -1;} }
  Future<int> insertPlaylist(Playlist playlist) async { try{return await (await database).insert(tablePlaylists,{columnPlaylistId:playlist.id,columnPlaylistName:playlist.name,columnPlaylistCreatedAt:playlist.createdAt.toIso8601String(),columnPlaylistDescription:playlist.description},conflictAlgorithm:ConflictAlgorithm.replace);}catch(e){return -1;} }
  Future<List<Playlist>> getAllPlaylists() async { try{return (await (await database).query(tablePlaylists,orderBy:'$columnPlaylistName ASC')).map(_playlistFromMap).toList();}catch(e){return [];} }
  Future<int> addSongToPlaylist(String playlistId,String songId,int position) async { try{return await (await database).insert(tablePlaylistSongs,{columnPlaylistSongPlaylistId:playlistId,columnPlaylistSongSongId:songId,columnPlaylistSongPosition:position},conflictAlgorithm:ConflictAlgorithm.ignore);}catch(e){return -1;} }
  Future<List<Song>> getPlaylistSongs(String playlistId) async { try{return (await (await database).rawQuery('SELECT s.* FROM $tableSongs s INNER JOIN $tablePlaylistSongs ps ON s.$columnSongId=ps.$columnPlaylistSongSongId WHERE ps.$columnPlaylistSongPlaylistId=? ORDER BY ps.$columnPlaylistSongPosition ASC',[playlistId])).map(_songFromMap).toList();}catch(e){return [];} }
  Future<int> removeSongFromPlaylist(String playlistId,String songId) async { try{return await (await database).delete(tablePlaylistSongs,where:'$columnPlaylistSongPlaylistId = ? AND $columnPlaylistSongSongId = ?',whereArgs:[playlistId,songId]);}catch(e){return -1;} }
  Future<int> deletePlaylist(String playlistId) async { try{final db=await database;await db.delete(tablePlaylistSongs,where:'$columnPlaylistSongPlaylistId = ?',whereArgs:[playlistId]);return await db.delete(tablePlaylists,where:'$columnPlaylistId = ?',whereArgs:[playlistId]);}catch(e){return -1;} }
  Future<int> addFavorite(String songId) async { try{return await (await database).insert(tableFavorites,{columnFavoriteSongId:songId,columnFavoriteDateAdded:DateTime.now().toIso8601String()},conflictAlgorithm:ConflictAlgorithm.ignore);}catch(e){return -1;} }
  Future<List<Song>> getFavoriteSongs() async { try{return (await (await database).rawQuery('SELECT s.* FROM $tableSongs s INNER JOIN $tableFavorites f ON s.$columnSongId=f.$columnFavoriteSongId ORDER BY s.$columnSongTitle ASC')).map(_songFromMap).toList();}catch(e){return [];} }
  Future<bool> isFavorite(String songId) async { try{return (await (await database).query(tableFavorites,where:'$columnFavoriteSongId = ?',whereArgs:[songId],limit:1)).isNotEmpty;}catch(e){return false;} }
  Future<int> removeFavorite(String songId) async { try{return await (await database).delete(tableFavorites,where:'$columnFavoriteSongId = ?',whereArgs:[songId]);}catch(e){return -1;} }
  Future<Map<String,dynamic>> getStatistics() async { try{final db=await database;final totalSongs=Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $tableSongs'))??0;final totalPlaylists=Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $tablePlaylists'))??0;final favoriteCount=Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $tableFavorites'))??0;final totalPlayCount=Sqflite.firstIntValue(await db.rawQuery('SELECT COALESCE(SUM($columnSongPlayCount),0) FROM $tableSongs'))??0;return {'totalSongs':totalSongs,'totalPlaylists':totalPlaylists,'favoriteCount':favoriteCount,'totalPlayCount':totalPlayCount};}catch(e){return {'totalSongs':0,'totalPlaylists':0,'favoriteCount':0,'totalPlayCount':0};} }
  Song _songFromMap(Map<String,dynamic> map){final d=map[columnSongDateAdded]?.toString();return Song(id:map[columnSongId]?.toString()??'',title:map[columnSongTitle]?.toString()??'Unknown Title',artist:map[columnSongArtist]?.toString()??'Unknown Artist',album:map[columnSongAlbum]?.toString()??'Unknown Album',filePath:map[columnSongFilePath]?.toString()??'',duration:Duration(milliseconds:(map[columnSongDuration] as num?)?.toInt()??0),dateAdded:DateTime.tryParse(d??'')??DateTime.now(),albumArt:map[columnSongAlbumArt]?.toString());}
  Playlist _playlistFromMap(Map<String,dynamic> map){return Playlist(id:map[columnPlaylistId]?.toString()??'',name:map[columnPlaylistName]?.toString()??'Untitled Playlist',songIds:const [],createdAt:DateTime.tryParse(map[columnPlaylistCreatedAt]?.toString()??'')??DateTime.now(),description:map[columnPlaylistDescription]?.toString());}
  Future<void> clearAllData() async { try{final db=await database;await db.delete(tableListeningEvents);await db.delete(tablePlaylistSongs);await db.delete(tableFavorites);await db.delete(tablePlaylists);await db.delete(tableSongs);}catch(e){print('Error clearing database: $e');} }
  Future<void> closeDatabase() async {if(_database!=null){await _database!.close();_database=null;}}
}
