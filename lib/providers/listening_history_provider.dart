import 'package:flutter/foundation.dart';
import '../models/listening_event.dart';
import '../models/song.dart';
import '../services/database_helper.dart';

class ListeningHistoryItem {
  final ListeningEvent event;
  final Song? song;
  const ListeningHistoryItem({required this.event, required this.song});
}

class ListeningHistoryProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();
  List<ListeningHistoryItem> _items = const [];
  Map<String, dynamic> _stats = const {};
  bool _loading = false;

  List<ListeningHistoryItem> get items => List.unmodifiable(_items);
  Map<String, dynamic> get stats => Map.unmodifiable(_stats);
  bool get isLoading => _loading;

  ListeningHistoryProvider() { load(); }

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      final events = await _db.getListeningHistory(limit: 200);
      final songs = await _db.getAllSongs();
      final byId = {for (final song in songs) song.id: song};
      _items = events.map((event) => ListeningHistoryItem(event: event, song: byId[event.songId])).toList();
      _stats = await _db.getListeningHistoryStatistics();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> clearHistory() async {
    await _db.clearListeningHistory();
    _items = const [];
    _stats = await _db.getListeningHistoryStatistics();
    notifyListeners();
  }
}
