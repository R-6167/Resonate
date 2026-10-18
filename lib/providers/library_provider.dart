import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../services/database_helper.dart';
import '../services/audio_file_service.dart';
import '../services/library_visibility_store.dart';

class LibraryProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();
  final LibraryVisibilityStore _visibility = LibraryVisibilityStore.instance;
  List<Song> _allSongs = [];
  List<Song> _filteredSongs = [];
  List<Song> _favoriteSongs = [];
  String _sortBy = 'title';
  String _filterBy = 'all';
  String _searchQuery = '';
  Map<String, dynamic> _statistics = {};
  bool _isInitialized = false;
  bool _isScanning = false;
  bool _autoScanEnabled = true;
  int _minimumScanDurationMs = 30000;
  Set<String>? _restrictedSongIds;
  List<Song> get allSongs => _allSongs;
  List<Song> get filteredSongs => _filteredSongs;
  List<Song> get favoriteSongs => _favoriteSongs;
  String get sortBy => _sortBy;
  String get filterBy => _filterBy;
  String get searchQuery => _searchQuery;
  Map<String, dynamic> get statistics => _statistics;
  bool get isInitialized => _isInitialized;
  bool get isScanning => _isScanning;
  bool get autoScanEnabled => _autoScanEnabled;
  int get minimumScanDurationMs => _minimumScanDurationMs;
  bool isFavoriteSync(String songId) => _favoriteSongs.any((song) => song.id == songId);

  LibraryProvider() {
    _visibility.addListener(_onVisibilityChanged);
    _initializeLibraryAsync();
  }

  void _onVisibilityChanged() {
    final next = _visibility.restrictedSongIds;
    final changed = !_sameSet(_restrictedSongIds, next);
    if (!changed) return;
    _restrictedSongIds = next;
    unawaitedRefresh();
  }

  Future<void> unawaitedRefresh() async {
    try {
      await loadAllSongs();
      await loadFavoriteSongs();
      await loadStatistics();
      notifyListeners();
    } catch (e) {
      debugPrint('Library visibility refresh failed: $e');
    }
  }

  bool _sameSet(Set<String>? a, Set<String>? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.length == b.length && a.containsAll(b);
  }

  Future<void> _initializeLibraryAsync() async { try { await _loadPreferences(); await loadAllSongs(); await loadFavoriteSongs(); await loadStatistics(); _isInitialized = true; notifyListeners(); await _autoScanOnStartup(); } catch (e) { debugPrint('LibraryProvider initialization error: $e'); _isInitialized = true; notifyListeners(); } }
  Future<void> _autoScanOnStartup() async { if (!_autoScanEnabled) return; try { final folders = await AudioFileService.getSelectedFolders(); if (folders.isEmpty) return; await scanAndImportMusic(); } catch (e) { debugPrint('Auto-scan failed: $e'); } }
  Future<void> loadAllSongs() async { try { await _visibility.load(); final songs = await _db.getAllSongs(); _allSongs = songs.where((s) => _visibility.isVisible(s.id)).toList(); _applyFiltersAndSort(); notifyListeners(); } catch (e) { debugPrint('Error loading songs: $e'); } }
  Future<void> loadFavoriteSongs() async { try { await _visibility.load(); final favorites = await _db.getFavoriteSongs(); _favoriteSongs = favorites.where((s) => _visibility.isVisible(s.id)).toList(); notifyListeners(); } catch (e) { debugPrint('Error loading favorites: $e'); } }
  Future<void> loadStatistics() async { try { _statistics = await _db.getStatistics(); notifyListeners(); } catch (e) { debugPrint('Error loading statistics: $e'); } }
  Future<void> searchSongs(String query) async { _searchQuery = query; try { await _visibility.load(); if (query.isEmpty) { _applyFiltersAndSort(); } else { final results = await _db.searchSongs(query); _filteredSongs = results.where((s) => _visibility.isVisible(s.id)).toList(); _applySorting(); } notifyListeners(); } catch (e) { debugPrint('Error searching songs: $e'); } }
  Future<void> setSortBy(String sortBy) async { _sortBy = sortBy; await _saveSortPreference(); _applySorting(); notifyListeners(); }
  Future<void> setFilterBy(String filterBy) async { _filterBy = filterBy; await _saveFilterPreference(); _applyFiltersAndSort(); notifyListeners(); }
  Future<void> toggleFavorite(Song song) async { try { final isFav = isFavoriteSync(song.id); if (isFav) { await _db.removeFavorite(song.id); } else { await _db.addFavorite(song.id); } await loadFavoriteSongs(); await loadStatistics(); } catch (e) { debugPrint('Error toggling favorite: $e'); } }
  Future<void> removeFavorite(String songId) async { try { await _db.removeFavorite(songId); await loadFavoriteSongs(); await loadStatistics(); } catch (e) { debugPrint('Error removing favorite: $e'); } }
  Future<void> updatePlayCount(String songId) async { try { await _db.incrementPlayCount(songId); } catch (e) { debugPrint('Error updating play count: $e'); } }
  Future<void> scanAndImportMusic() async { if (_isScanning) return; _isScanning = true; notifyListeners(); try { final imported = await AudioFileService.scanAndImport(minimumDurationMs: _minimumScanDurationMs); await loadAllSongs(); await loadFavoriteSongs(); await loadStatistics(); debugPrint('Imported ${imported.length} tracks'); } catch (e) { debugPrint('Scan error: $e'); } finally { _isScanning = false; notifyListeners(); } }
  Future<void> deleteSong(String songId) async { try { await _db.deleteSong(songId); await loadAllSongs(); await loadFavoriteSongs(); await loadStatistics(); } catch (e) { debugPrint('Error deleting song: $e'); } }
  void _applyFiltersAndSort() { _filteredSongs = List.from(_allSongs); if (_filterBy == 'favorites') _filteredSongs = _filteredSongs.where((song) => isFavoriteSync(song.id)).toList(); if (_filterBy == 'recent') _filteredSongs.sort((a, b) => b.dateAdded.compareTo(a.dateAdded)); if (_searchQuery.isNotEmpty) { final query = _searchQuery.toLowerCase(); _filteredSongs = _filteredSongs.where((song) => song.title.toLowerCase().contains(query) || song.artist.toLowerCase().contains(query) || song.album.toLowerCase().contains(query)).toList(); } _applySorting(); }
  void _applySorting() { switch (_sortBy) { case 'title': _filteredSongs.sort((a,b)=>a.title.toLowerCase().compareTo(b.title.toLowerCase())); break; case 'artist': _filteredSongs.sort((a,b)=>a.artist.toLowerCase().compareTo(b.artist.toLowerCase())); break; case 'album': _filteredSongs.sort((a,b)=>a.album.toLowerCase().compareTo(b.album.toLowerCase())); break; case 'date_added': _filteredSongs.sort((a,b)=>b.dateAdded.compareTo(a.dateAdded)); break; case 'duration': _filteredSongs.sort((a,b)=>b.duration.compareTo(a.duration)); break; } }
  Future<void> _saveSortPreference() async { final prefs = await SharedPreferences.getInstance(); await prefs.setString('library_sort_by', _sortBy); }
  Future<void> _saveFilterPreference() async { final prefs = await SharedPreferences.getInstance(); await prefs.setString('library_filter_by', _filterBy); }
  Future<void> setAutoScanEnabled(bool enabled) async { _autoScanEnabled = enabled; final prefs = await SharedPreferences.getInstance(); await prefs.setBool('library_auto_scan', enabled); notifyListeners(); }
  Future<void> setMinimumScanDuration(int milliseconds) async { _minimumScanDurationMs = milliseconds.clamp(0, 3600000).toInt(); final prefs = await SharedPreferences.getInstance(); await prefs.setInt('library_min_duration_ms', _minimumScanDurationMs); notifyListeners(); }
  Future<void> _loadPreferences() async { await _visibility.load(); final prefs = await SharedPreferences.getInstance(); _sortBy = prefs.getString('library_sort_by') ?? 'title'; _filterBy = prefs.getString('library_filter_by') ?? 'all'; _autoScanEnabled = prefs.getBool('library_auto_scan') ?? true; _minimumScanDurationMs = prefs.getInt('library_min_duration_ms') ?? 30000; _restrictedSongIds = _visibility.restrictedSongIds; }

  @override
  void dispose() {
    _visibility.removeListener(_onVisibilityChanged);
    super.dispose();
  }
}
