from pathlib import Path
p = Path('lib/providers/intelligence_provider.dart')
s = p.read_text()
if "import '../services/resonate_diagnostics.dart';" not in s:
    s = s.replace("import '../services/intelligence_settings_store.dart';\n", "import '../services/intelligence_settings_store.dart';\nimport '../services/resonate_diagnostics.dart';\n", 1)
old = """      ranked.sort((a, b) => b.score.compareTo(a.score)); _recommendations = ranked.take(limit).toList(growable: false); await _evaluateAutopilotGraduation(); if (notify) notifyListeners();"""
new = """      ranked.sort((a, b) => b.score.compareTo(a.score)); _recommendations = ranked.take(limit).toList(growable: false);
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
if old not in s:
    raise SystemExit('compact IntelligenceProvider line not found')
s = s.replace(old, new, 1)
p.write_text(s)
