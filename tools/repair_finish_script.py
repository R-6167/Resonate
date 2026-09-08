from pathlib import Path

p = Path('tools/finish_playback_companion.py')
s = p.read_text()
start_marker = 'needle = """      _recommendations = ranked.take(limit).toList();'
start = s.index(start_marker)
end_marker = 's = s.replace(needle, repl, 1)'
end = s.index(end_marker, start) + len(end_marker)
replacement = '''needle = """      ranked.sort((a, b) => b.score.compareTo(a.score)); _recommendations = ranked.take(limit).toList(growable: false); await _evaluateAutopilotGraduation(); if (notify) notifyListeners();"""
repl = """      ranked.sort((a, b) => b.score.compareTo(a.score)); _recommendations = ranked.take(limit).toList(growable: false);
      await ResonateDiagnostics.recordIntelligence(
        'recommendations_generated',
        data: {
          'mode': autonomyLabel,
          'sessionMode': _sessionMode,
          'count': _recommendations.length,
          'topSongId': _recommendations.isEmpty ? null : _recommendations.first.song.id,
          'topConfidence': _recommendations.isEmpty ? 0 : _recommendations.first.confidence,
          'exploration': exploration,
        },
      );
      await _evaluateAutopilotGraduation(); if (notify) notifyListeners();"""
'''
s = s[:start] + replacement + s[end:]
p.write_text(s)
