import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/song.dart';
import '../services/database_helper.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart';
import 'package:android_intent_plus/android_intent_plus.dart';

class LibraryProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();
  final Uuid _uuid = const Uuid();

  List<Song> _allSongs = [];
  List<Song> _filteredSongs = [];
  List<Song> _favoriteSongs = [];
  String _sortBy = 'title';
  String _filterBy = 'all';
  String _searchQuery = '';
  Map<String, dynamic> _statistics = {};
  bool _scannedOnFirstRun = false;

  List<Song> get allSongs => _filteredSongs;
  List<Song> get favoriteSongs => _favoriteSongs;
  String get sortBy => _sortBy;
  String get filterBy => _filterBy;
  String get searchQuery => _searchQuery;
  Map<String, dynamic> get statistics => _statistics;

  LibraryProvider() {
    _initializeLibrary();
  }

  Future<void> _initializeLibrary() async {
    await loadAllSongs();
    await loadFavoriteSongs();
    await loadStatistics();
    // Auto scan on first run - guard to avoid repeated scans in a single session
    if (!_scannedOnFirstRun) {
      await _autoScan();
      _scannedOnFirstRun = true;
    }
  }

  Future<void> _autoScan() async {
    try {
      // Request permission for media on Android 13+ it's READ_MEDIA_AUDIO
      final status = await Permission.storage.request();
      if (!status.isGranted) return;

      // Try MediaStore-based scanning via Android intent as fallback for simplicity
      // In-depth MediaStore queries require platform channel; for now use common roots
      final commonRoots = [
        Directory('/storage/emulated/0/Music'),
        Directory('/storage/emulated/0/Download'),
      ];

      for (final root in commonRoots) {
        if (await root.exists()) {
          await scanDirectory(root);
        }
      }
    } catch (e) {
      debugPrint('Auto scan error: $e');
    }
  }

  Future<void> loadAllSongs() async {
    try {
      _allSongs = await _db.getAllSongs();
      _applyFiltersAndSort();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading all songs: $e');
    }
  }

  Future<void> loadFavoriteSongs() async {
    try {
      _favoriteSongs = await _db.getFavoriteSongs();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading favorite songs: $e');
    }
  }

  Future<void> loadStatistics() async {
    try {
      _statistics = await _db.getStatistics();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading statistics: $e');
    }
  }

  Future<void> addSongs(List<Song> songs) async {
    try {
      final count = await _db.insertSongs(songs);
      debugPrint('Added $count songs to library');
      await loadAllSongs();
      await loadStatistics();
      notifyListeners();
    } catch (e) {
      debugPrint('Error adding songs: $e');
    }
  }

  // Simple scanner that walks a directory and finds audio files by extension.
  Future<void> scanDirectory(Directory startDir) async {
    final status = await Permission.storage.request();
    if (!status.isGranted) return;

    final audioExtensions = ['.mp3', '.m4a', '.flac', '.wav', '.aac', '.ogg'];
    final List<Song> found = [];

    await for (final entity in startDir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = extension(entity.path).toLowerCase();
        if (audioExtensions.contains(ext)) {
          final stat = await entity.stat();
          final song = Song(
            id: _uuid.v4(),
            title: basenameWithoutExtension(entity.path),
            artist: 'Unknown',
            album: 'Unknown',
            duration: 0,
            path: entity.path,
            dateAdded: stat.modified,
            playCount: 0,
            isFavorite: false,
          );
          found.add(song);
        }
      }
    }

    if (found.isNotEmpty) {
      await addSongs(found);
    }
  }

  Future<void> searchSongs(String query) async {
    _searchQuery = query;
    try {
      if (query.isEmpty) {
        await loadAllSongs();
      } else {
        _filteredSongs = await _db.searchSongs(query);
        _applySorting();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error searching songs: $e');
    }
  }

  Future<void> setSortBy(String sortBy) async {
    _sortBy = sortBy;
    _applySorting();
    notifyListeners();
  }

  Future<void> setFilterBy(String filterBy) async {
    _filterBy = filterBy;
    _applyFiltersAndSort();
    notifyListeners();
  }

  Future<List<Song>> getSongsByArtist(String artist) async {
    try {
      return await _db.getSongsByArtist(artist);
    } catch (e) {
      debugPrint('Error getting songs by artist: $e');
      return [];
    }
  }

  Future<List<Song>> getSongsByAlbum(String album) async {
    try {
      return await _db.getSongsByAlbum(album);
    } catch (e) {
      debugPrint('Error getting songs by album: $e');
      return [];
    }
  }

  Future<void> addFavorite(Song song) async {
    try {
      await _db.addFavorite(song.id);
      await loadFavoriteSongs();
      notifyListeners();
    } catch (e) {
      debugPrint('Error adding favorite: $e');
    }
  }

  Future<void> removeFavorite(String songId) async {
    try {
      await _db.removeFavorite(songId);
      await loadFavoriteSongs();
      notifyListeners();
    } catch (e) {
      debugPrint('Error removing favorite: $e');
    }
  }

  Future<bool> isFavorite(String songId) async {
    try {
      return await _db.isFavorite(songId);
    } catch (e) {
      debugPrint('Error checking if favorite: $e');
      return false;
    }
  }

  Future<void> updatePlayCount(String songId) async {
    try {
      await _db.updateSongPlayCount(songId);
      await loadStatistics();
    } catch (e) {
      debugPrint('Error updating play count: $e');
    }
  }

  Future<void> deleteSong(String songId) async {
    try {
      await _db.deleteSong(songId);
      await loadAllSongs();
      await loadStatistics();
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting song: $e');
    }
  }

  void _applyFiltersAndSort() {
    _filteredSongs = List.from(_allSongs);

    switch (_filterBy) {
      case 'favorites':
        _filteredSongs = _filteredSongs
            .where((song) => _favoriteSongs.any((fav) => fav.id == song.id))
            .toList();
        break;
      case 'recent':
        _filteredSongs.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
        break;
      case 'all':
      default:
        break;
    }

    if (_searchQuery.isNotEmpty) {
      _filteredSongs = _filteredSongs
          .where((song) =>
              song.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              song.artist.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              song.album.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    _applySorting();
  }

  void _applySorting() {
    switch (_sortBy) {
      case 'title':
        _filteredSongs.sort((a, b) => a.title.compareTo(b.title));
        break;
      case 'artist':
        _filteredSongs.sort((a, b) => a.artist.compareTo(b.artist));
        break;
      case 'album':
        _filteredSongs.sort((a, b) => a.album.compareTo(b.album));
        break;
      case 'date_added':
        _filteredSongs.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
        break;
      default:
        break;
    }
  }
}
