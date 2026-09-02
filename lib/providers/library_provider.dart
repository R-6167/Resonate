import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../services/database_helper.dart';

class LibraryProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();
  
  List<Song> _allSongs = [];
  List<Song> _filteredSongs = [];
  List<Song> _favoriteSongs = [];
  String _sortBy = 'title'; // title, artist, album, date_added, play_count
  String _filterBy = 'all'; // all, favorites, recent
  String _searchQuery = '';
  Map<String, dynamic> _statistics = {};
  bool _isInitialized = false;

  // Getters
  List<Song> get allSongs => _allSongs;
  List<Song> get filteredSongs => _filteredSongs;
  List<Song> get favoriteSongs => _favoriteSongs;
  String get sortBy => _sortBy;
  String get filterBy => _filterBy;
  String get searchQuery => _searchQuery;
  Map<String, dynamic> get statistics => _statistics;
  bool get isInitialized => _isInitialized;

  LibraryProvider() {
    print('📚 LibraryProvider: Initializing...');
    _loadPreferences();
    // Don't await initialization - let it run in background
    _initializeLibraryAsync();
  }

  /// Runs library initialization in the background without blocking the UI
  Future<void> _initializeLibraryAsync() async {
    try {
      print('📚 LibraryProvider: Starting background initialization');
      await loadAllSongs();
      await loadFavoriteSongs();
      await loadStatistics();
      _isInitialized = true;
      print('✅ LibraryProvider: Background initialization complete');
      notifyListeners();
    } catch (e) {
      print('❌ LibraryProvider: Initialization error: $e');
    }
  }

  Future<void> _initializeLibrary() async {
    await loadAllSongs();
    await loadFavoriteSongs();
    await loadStatistics();
  }

  // Load all songs from database
  Future<void> loadAllSongs() async {
    try {
      print('📚 LibraryProvider: Loading all songs...');
      _allSongs = await _db.getAllSongs();
      _applyFiltersAndSort();
      notifyListeners();
      print('📚 LibraryProvider: Loaded ${_allSongs.length} songs');
    } catch (e) {
      print('❌ Error loading all songs: $e');
    }
  }

  // Load favorite songs
  Future<void> loadFavoriteSongs() async {
    try {
      print('📚 LibraryProvider: Loading favorite songs...');
      _favoriteSongs = await _db.getFavoriteSongs();
      notifyListeners();
      print('📚 LibraryProvider: Loaded ${_favoriteSongs.length} favorites');
    } catch (e) {
      print('❌ Error loading favorite songs: $e');
    }
  }

  // Load statistics
  Future<void> loadStatistics() async {
    try {
      print('📚 LibraryProvider: Loading statistics...');
      _statistics = await _db.getStatistics();
      notifyListeners();
      print('📚 LibraryProvider: Statistics loaded');
    } catch (e) {
      print('❌ Error loading statistics: $e');
    }
  }

  // Add songs to library
  Future<void> addSongs(List<Song> songs) async {
    try {
      final count = await _db.insertSongs(songs);
      print('Added $count songs to library');
      await loadAllSongs();
      await loadStatistics();
      notifyListeners();
    } catch (e) {
      print('Error adding songs: $e');
    }
  }

  // Search songs
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
      print('Error searching songs: $e');
    }
  }

  // Set sort method
  Future<void> setSortBy(String sortBy) async {
    _sortBy = sortBy;
    await _saveSortPreference();
    _applySorting();
    notifyListeners();
  }

  // Set filter method
  Future<void> setFilterBy(String filterBy) async {
    _filterBy = filterBy;
    await _saveFilterPreference();
    _applyFiltersAndSort();
    notifyListeners();
  }

  // Get songs by artist
  Future<List<Song>> getSongsByArtist(String artist) async {
    try {
      return await _db.getSongsByArtist(artist);
    } catch (e) {
      print('Error getting songs by artist: $e');
      return [];
    }
  }

  // Get songs by album
  Future<List<Song>> getSongsByAlbum(String album) async {
    try {
      return await _db.getSongsByAlbum(album);
    } catch (e) {
      print('Error getting songs by album: $e');
      return [];
    }
  }

  // Add favorite
  Future<void> addFavorite(Song song) async {
    try {
      await _db.addFavorite(song.id);
      await loadFavoriteSongs();
      notifyListeners();
    } catch (e) {
      print('Error adding favorite: $e');
    }
  }

  // Remove favorite
  Future<void> removeFavorite(String songId) async {
    try {
      await _db.removeFavorite(songId);
      await loadFavoriteSongs();
      notifyListeners();
    } catch (e) {
      print('Error removing favorite: $e');
    }
  }

  // Check if song is favorite
  Future<bool> isFavorite(String songId) async {
    try {
      return await _db.isFavorite(songId);
    } catch (e) {
      print('Error checking if favorite: $e');
      return false;
    }
  }

  // Update play count
  Future<void> updatePlayCount(String songId) async {
    try {
      await _db.updateSongPlayCount(songId);
      await loadStatistics();
    } catch (e) {
      print('Error updating play count: $e');
    }
  }

  // Delete song
  Future<void> deleteSong(String songId) async {
    try {
      await _db.deleteSong(songId);
      await loadAllSongs();
      await loadStatistics();
      notifyListeners();
    } catch (e) {
      print('Error deleting song: $e');
    }
  }

  // Private helper methods
  void _applyFiltersAndSort() {
    _filteredSongs = List.from(_allSongs);

    // Apply filter
    switch (_filterBy) {
      case 'favorites':
        _filteredSongs = _filteredSongs
            .where((song) => _favoriteSongs.any((fav) => fav.id == song.id))
            .toList();
        break;
      case 'recent':
        _filteredSongs.sort(
          (a, b) => b.dateAdded.compareTo(a.dateAdded),
        );
        break;
      case 'all':
      default:
        break;
    }

    // Apply search if query is not empty
    if (_searchQuery.isNotEmpty) {
      _filteredSongs = _filteredSongs
          .where((song) =>
              song.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              song.artist.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              song.album.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    // Apply sorting
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

  Future<void> _saveSortPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('library_sort_by', _sortBy);
    } catch (e) {
      print('Error saving sort preference: $e');
    }
  }

  Future<void> _saveFilterPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('library_filter_by', _filterBy);
    } catch (e) {
      print('Error saving filter preference: $e');
    }
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _sortBy = prefs.getString('library_sort_by') ?? 'title';
      _filterBy = prefs.getString('library_filter_by') ?? 'all';
    } catch (e) {
      print('Error loading preferences: $e');
    }
  }
}
