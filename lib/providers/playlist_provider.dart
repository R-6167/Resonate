import 'package:flutter/foundation.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../services/playlist_service.dart';

class PlaylistProvider extends ChangeNotifier {
  final PlaylistService _service = PlaylistService();
  List<Playlist> _playlists = const [];
  bool _loading = false;
  bool _smartRefreshing = false;

  List<Playlist> get playlists => List.unmodifiable(_playlists);
  bool get isLoading => _loading;
  bool get isSmartRefreshing => _smartRefreshing;

  PlaylistProvider() { loadPlaylists(); }

  Future<void> loadPlaylists() async { _loading = true; notifyListeners(); try { _playlists = await _service.getAllPlaylists(); } finally { _loading = false; notifyListeners(); } }
  Future<Playlist?> createPlaylist(String name, {String? description}) async { try { final playlist = await _service.createPlaylist(name, description: description); await loadPlaylists(); return playlist; } catch (e) { debugPrint('Create playlist failed: $e'); return null; } }
  Future<void> renamePlaylist(String id, String name) async { try { await _service.renamePlaylist(id, name); await loadPlaylists(); } catch (e) { debugPrint('Rename playlist failed: $e'); } }
  Future<void> deletePlaylist(String id) async { try { await _service.deletePlaylist(id); await loadPlaylists(); } catch (e) { debugPrint('Delete playlist failed: $e'); } }
  Future<void> addSong(String playlistId, Song song) async { try { await _service.addSong(playlistId, song); await loadPlaylists(); } catch (e) { debugPrint('Add song to playlist failed: $e'); } }
  Future<void> addSongs(String playlistId, List<Song> songs) async { try { await _service.addSongs(playlistId, songs); await loadPlaylists(); } catch (e) { debugPrint('Add songs to playlist failed: $e'); } }
  Future<void> removeSong(String playlistId, String songId) async { try { await _service.removeSong(playlistId, songId); await loadPlaylists(); } catch (e) { debugPrint('Remove playlist song failed: $e'); } }
  Future<void> reorderSong(String playlistId, String songId, int newPosition) async { try { await _service.reorderSong(playlistId, songId, newPosition); await loadPlaylists(); } catch (e) { debugPrint('Reorder playlist song failed: $e'); } }
  Future<List<Song>> songsFor(String playlistId) => _service.getSongs(playlistId);

  Future<void> refreshSmartPlaylists({required List<Song> recommended, required List<Song> favorites, required List<Song> recent}) async {
    if (_smartRefreshing) return;
    _smartRefreshing = true; notifyListeners();
    try {
      await _service.replaceSongsByName('Resonate Mix', recommended.take(20).toList(), description: 'A local mix built from your listening patterns and Intelligence recommendations.');
      await _service.replaceSongsByName('Most Loved', favorites.take(50).toList(), description: 'Songs you have explicitly favorited.');
      await _service.replaceSongsByName('Recently Added', recent.take(50).toList(), description: 'Your newest music, kept ready for discovery.');
      await loadPlaylists();
    } catch (e) { debugPrint('Smart playlist refresh failed: $e'); } finally { _smartRefreshing = false; notifyListeners(); }
  }
}
