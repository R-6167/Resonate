import '../models/listening_event.dart';
import 'database_helper.dart';

/// Short-lived local evidence cache for Intelligence recomputation.
/// Playback boundaries invalidate it; repeated UI/provider notifications do not
/// repeatedly hit SQLite for the same recent-event window.
///
/// The cache is shared by recommendation refresh and learning/graduation checks.
class IntelligenceEvidenceCache {
  IntelligenceEvidenceCache._();
  static final IntelligenceEvidenceCache instance = IntelligenceEvidenceCache._();

  final DatabaseHelper _database = DatabaseHelper();
  List<ListeningEvent>? _recentEvents;
  DateTime? _loadedAt;
  int _generation = 0;
  int _loadedGeneration = -1;

  Future<List<ListeningEvent>> recentEvents({int limit = 200, bool force = false}) async {
    final now = DateTime.now();
    final fresh = _recentEvents != null &&
        _loadedAt != null &&
        now.difference(_loadedAt!) < const Duration(seconds: 2) &&
        _loadedGeneration == _generation;
    if (!force && fresh && _recentEvents!.length <= limit) {
      return List.unmodifiable(_recentEvents!);
    }
    final events = await _database.getRecentListeningEvents(limit: limit);
    _recentEvents = List<ListeningEvent>.from(events);
    _loadedAt = now;
    _loadedGeneration = _generation;
    return List.unmodifiable(_recentEvents!);
  }

  void invalidate() {
    _generation++;
  }

  void clear() {
    _generation++;
    _recentEvents = null;
    _loadedAt = null;
    _loadedGeneration = -1;
  }
}
