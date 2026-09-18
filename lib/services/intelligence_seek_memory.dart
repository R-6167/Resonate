import 'package:shared_preferences/shared_preferences.dart';

/// Aggregated local seek/replay signal for ranking (no audio content).
class SeekEvidence {
  final int seekCount;
  final int replayCount; // backward seeks of meaningful size
  final int preferredMsSum;

  const SeekEvidence({
    this.seekCount = 0,
    this.replayCount = 0,
    this.preferredMsSum = 0,
  });

  /// 0..1 soft strength used as ranking bonus.
  double get strength {
    if (seekCount <= 0 && replayCount <= 0) return 0;
    final raw = (replayCount * 0.12) + (seekCount * 0.03);
    return raw.clamp(0.0, 0.35);
  }

  bool get hasReplay => replayCount >= 2;
}

/// Local-only memory of seek/replay positions. Bounded events only.
class IntelligenceSeekMemory {
  static const String _key = 'intelligence_seek_memory_v1';
  static const int _maxEntries = 400;

  Future<void> record({required String songId, required int fromMs, required int toMs}) async {
    if (songId.isEmpty || fromMs < 0 || toMs < 0) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? <String>[];
      raw.add('$songId|$fromMs|$toMs');
      final start = raw.length > _maxEntries ? raw.length - _maxEntries : 0;
      await prefs.setStringList(_key, raw.sublist(start));
    } catch (_) {}
  }

  Future<List<Map<String, int>>> forSong(String songId) async {
    final result = <Map<String, int>>[];
    if (songId.isEmpty) return result;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final value in prefs.getStringList(_key) ?? const <String>[]) {
        final parts = value.split('|');
        if (parts.length != 3 || parts[0] != songId) continue;
        final fromMs = int.tryParse(parts[1]);
        final toMs = int.tryParse(parts[2]);
        if (fromMs == null || toMs == null) continue;
        result.add(<String, int>{'fromMs': fromMs, 'toMs': toMs});
      }
    } catch (_) {}
    return result;
  }

  /// One pass over storage for ranking — avoid N×forSong.
  Future<Map<String, SeekEvidence>> summarizeAll() async {
    final counts = <String, List<int>>{}; // songId -> [seeks, replays, preferredMs]
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final value in prefs.getStringList(_key) ?? const <String>[]) {
        final parts = value.split('|');
        if (parts.length != 3) continue;
        final id = parts[0];
        final fromMs = int.tryParse(parts[1]);
        final toMs = int.tryParse(parts[2]);
        if (id.isEmpty || fromMs == null || toMs == null) continue;
        final row = counts.putIfAbsent(id, () => <int>[0, 0, 0]);
        row[0] += 1;
        // Backward jump of more than 3s counts as a replay lean.
        if (toMs + 3000 < fromMs) {
          row[1] += 1;
          row[2] += toMs;
        }
      }
    } catch (_) {}
    return {
      for (final e in counts.entries)
        e.key: SeekEvidence(
          seekCount: e.value[0],
          replayCount: e.value[1],
          preferredMsSum: e.value[2],
        ),
    };
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
