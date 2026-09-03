import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../services/database_helper.dart';
import '../services/audio_file_service.dart';

class LibraryProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();
  List<Song> _allSongs = [];
  List<Song> _filteredSongs = [];
  List<Song> _favoriteSongs = [];
  String _sortBy = 'title';
  String _filterBy = 'all';
  String _searchQuery = '';
  Map<String, dynamic> _statistics = {};
  bool _isInitialized = false;
  bool _isScanning = false;

  List<Song> get allSongs => _allSongs;
  List<Song> get filteredSongs => _filteredSongs;
  List<Song> get favoriteSongs => _favoriteSongs;
  String get sortBy => _sortBy;
  String get filterBy => _filterBy;
  String get searchQuery => _searchQuery;
  Map<String, dynamic> get statistics => _statistics;
  bool get isInitialized => _isInitialized;
  bool get isScanning => _isScanning;

  LibraryProvider() { _initializeLibraryAsync(); }

  Future<void> _initializeLibraryAsync() async {
    try {
      await _loadPreferences();
      await loadAllSongs();
      await loadFavoriteSongs();
      await loadStatistics();
      _isInitialized = true;
      notifyListeners();
      await _autoScanOnStartup();
    } catch (e) {
      debugPrint('LibraryProvider initialization error: $e');
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> _autoScanOnStartup() async {
    try {
      final granted = await AudioFileService.requestAudioPermission();
      if (!granted) return;
      // First run: no folder restriction means discover all audio already
      // exposed by Android MediaStore. If the user later chooses folders,
      // scans are narrowed to those folders.
      await scanDeviceAudio();
    } catch (e) {
      debugPrint('Startup audio scan failed: $e');
    }
  }

  Future<void> scanDeviceAudio() async {
    if (_isScanning) return;
    _isScanning = true;
    notifyListeners();
    try {
      final folders = await AudioFileService.getSelectedFolders();
      final songs = await AudioFileService.scanAudioFiles(
        folderUris: folders.isEmpty ? null : folders.map((folder) => folder['uri']!).toList(),
      );
      if (songs.isNotEmpty) {
        await _db.insertSongs(songs);
        await loadAllSongs();
        await loadFavoriteSongs();
        await loadStatistics();
      }
    } catch (e) {
      debugPrint('LibraryProvider device scan failed: $e');
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<void> loadAllSongs() async { try { _allSongs = await _db.getAllSongs(); _applyFiltersAndSort(); notifyListeners(); } catch (e) { debugPrint('Error loading all songs: $e'); } }
  Future<void> loadFavoriteSongs() async { try { _favoriteSongs = await _db.getFavoriteSongs(); _applyFiltersAndSort(); notifyListeners(); } catch (e) { debugPrint('Error loading favorite songs: $e'); } }
  Future<void> loadStatistics() async { try { _statistics = await _db.getStatistics(); notifyListeners(); } catch (e) { debugPrint('Error loading statistics: $e'); } }
  Future<void> addSongs(List<Song> songs) async { try { await _db.insertSongs(songs); await loadAllSongs(); await loadStatistics(); } catch (e) { debugPrint('Error adding songs: $e'); } }

  Future<void> searchSongs(String query) async {
    _searchQuery = query;
    try { if (query.isEmpty) await loadAllSongs(); else { _filteredSongs = await _db.searchSongs(query); _applySorting(); } notifyListeners(); } catch (e) { debugPrint('Error searching songs: $e'); }
  }
  Future<void> setSortBy(String sortBy) async { _sortBy = sortBy; await _saveSortPreference(); _applySorting(); notifyListeners(); }
  Future<void> setFilterBy(String filterBy) async { _filterBy = filterBy; await _saveFilterPreference(); _applyFiltersAndSort(); notifyListeners(); }
  Future<List<Song>> getSongsByArtist(String artist) async => await _db.getSongsByArtist(artist);
  Future<List<Song>> getSongsByAlbum(String album) async => await _db.getSongsByAlbum(album);
  Future<void> addFavorite(Song song) async { try { await _db.addFavorite(song.id); await loadFavoriteSongs(); } catch (e) { debugPrint('Error adding favorite: $e'); } }
  Future<void> removeFavorite(String songId) async { try { await _db.removeFavorite(songId); await loadFavoriteSongs(); } catch (e) { debugPrint('Error removing favorite: $e'); } }
  Future<bool> isFavorite(String songId) async => await _db.isFavorite(songId);
  Future<void> updatePlayCount(String songId) async { try { await _db.updateSongPlayCount(songId); await loadStatistics(); } catch (e) { debugPrint('Error updating play count: $e'); } }
  Future<void> deleteSong(String songId) async { try { await _db.deleteSong(songId); await loadAllSongs(); await loadStatistics(); } catch (e) { debugPrint('Error deleting song: $e'); } }

  void _applyFiltersAndSort() {
    _filteredSongs = List.from(_allSongs);
    switch (_filterBy) {
      case 'favorites': _filteredSongs = _filteredSongs.where((song) => _favoriteSongs.any((fav) => fav.id == song.id)).toList(); break;
      case 'recent': _filteredSongs.sort((a, b) => b.dateAdded.compareTo(a.dateAdded)); break;
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      _filteredSongs = _filteredSongs.where((song) => song.title.toLowerCase().contains(query) || song.artist.toLowerCase().contains(query) || song.album.toLowerCase().contains(query)).toList();
    }
    _applySorting();
  }
  void _applySorting() {
    switch (_sortBy) {
      case 'title': _filteredSongs.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase())); break;
      case 'artist': _filteredSongs.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase())); break;
      case 'album': _filteredSongs.sort((a, b) => a.album.toLowerCase().compareTo(b.album.toLowerCase())); break;
      case 'date_added': _filteredSongs.sort((a, b) => b.dateAdded.compareTo(a.dateAdded)); break;
    }
  }
  Future<void> _saveSortPreference() async { final prefs = await SharedPreferences.getInstance(); await prefs.setString('library_sort_by', _sortBy); }
  Future<void> _saveFilterPreference() async { final prefs = await SharedPreferences.getInstance(); await prefs.setString('library_filter_by', _filterBy); }
  Future<void> _loadPreferences() async { final prefs = await SharedPreferences.getInstance(); _sortBy = prefs.getString('library_sort_by') ?? 'title'; _filterBy = prefs.getString('library_filter_by') ?? 'all'; }
}