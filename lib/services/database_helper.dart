import 'dart:async';
import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/song.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'resonate.db');
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE songs(
        id TEXT PRIMARY KEY,
        title TEXT,
        artist TEXT,
        album TEXT,
        duration INTEGER,
        path TEXT,
        date_added INTEGER,
        play_count INTEGER DEFAULT 0,
        is_favorite INTEGER DEFAULT 0
      )
    ''');
  }

  Future<List<Song>> getAllSongs() async {
    final dbClient = await database;
    final maps = await dbClient.query('songs');
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  Future<List<Song>> getFavoriteSongs() async {
    final dbClient = await database;
    final maps = await dbClient.query('songs', where: 'is_favorite = ?', whereArgs: [1]);
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  Future<Map<String, dynamic>> getStatistics() async {
    final dbClient = await database;
    final total = Sqflite.firstIntValue(await dbClient.rawQuery('SELECT COUNT(*) FROM songs')) ?? 0;
    final favorites = Sqflite.firstIntValue(await dbClient.rawQuery('SELECT COUNT(*) FROM songs WHERE is_favorite = 1')) ?? 0;
    final mostPlayed = await dbClient.rawQuery('SELECT * FROM songs ORDER BY play_count DESC LIMIT 1');
    return {
      'total_songs': total,
      'favorite_songs': favorites,
      'most_played': mostPlayed.isNotEmpty ? Song.fromMap(mostPlayed.first).toMap() : null,
    };
  }

  Future<int> insertSongs(List<Song> songs) async {
    final dbClient = await database;
    final batch = dbClient.batch();
    for (final s in songs) {
      batch.insert('songs', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    final results = await batch.commit();
    return results.length;
  }

  Future<List<Song>> searchSongs(String query) async {
    final dbClient = await database;
    final q = '%${query.toLowerCase()}%';
    final maps = await dbClient.rawQuery(
      'SELECT * FROM songs WHERE LOWER(title) LIKE ? OR LOWER(artist) LIKE ? OR LOWER(album) LIKE ?',
      [q, q, q],
    );
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  Future<List<Song>> getSongsByArtist(String artist) async {
    final dbClient = await database;
    final maps = await dbClient.query('songs', where: 'artist = ?', whereArgs: [artist]);
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  Future<List<Song>> getSongsByAlbum(String album) async {
    final dbClient = await database;
    final maps = await dbClient.query('songs', where: 'album = ?', whereArgs: [album]);
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  Future<void> addFavorite(String songId) async {
    final dbClient = await database;
    await dbClient.update('songs', {'is_favorite': 1}, where: 'id = ?', whereArgs: [songId]);
  }

  Future<void> removeFavorite(String songId) async {
    final dbClient = await database;
    await dbClient.update('songs', {'is_favorite': 0}, where: 'id = ?', whereArgs: [songId]);
  }

  Future<bool> isFavorite(String songId) async {
    final dbClient = await database;
    final maps = await dbClient.query('songs', where: 'id = ?', whereArgs: [songId]);
    if (maps.isEmpty) return false;
    return (maps.first['is_favorite'] as int) == 1;
  }

  Future<void> updateSongPlayCount(String songId) async {
    final dbClient = await database;
    await dbClient.rawUpdate('UPDATE songs SET play_count = play_count + 1 WHERE id = ?', [songId]);
  }

  Future<void> deleteSong(String songId) async {
    final dbClient = await database;
    await dbClient.delete('songs', where: 'id = ?', whereArgs: [songId]);
  }
}
