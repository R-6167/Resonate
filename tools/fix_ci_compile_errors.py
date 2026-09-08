from pathlib import Path

# Serialize diagnostics logging without requiring the named recordIntelligence API shape.
p = Path('lib/providers/intelligence_provider.dart')
s = p.read_text()
start = s.index("      await ResonateDiagnostics.recordIntelligence(")
end = s.index("      await _evaluateAutopilotGraduation();", start)
replacement = """      await ResonateDiagnostics.record('intelligence_recommendations_generated', {
        'stage': 'recommendations_generated',
        'mode': autonomyLabel,
        'sessionMode': _sessionMode,
        'count': _recommendations.length,
        'topSongId': _recommendations.isEmpty ? null : _recommendations.first.song.id,
        'topConfidence': _recommendations.isEmpty ? 0 : _recommendations.first.confidence,
        'exploration': exploration,
      });
"""
s = s[:start] + replacement + s[end:]
p.write_text(s)

# _serializePlayback now awaits diagnostics, so the function itself must be async.
p = Path('lib/providers/music_provider.dart')
s = p.read_text()
old = "Future<T> _serializePlayback<T>(Future<T> Function() operation, {required String command, required String source, bool userInitiated = false, int? intentToken}) {"
new = "Future<T> _serializePlayback<T>(Future<T> Function() operation, {required String command, required String source, bool userInitiated = false, int? intentToken}) async {"
if old not in s:
    raise SystemExit('serializePlayback signature not found')
p.write_text(s.replace(old, new, 1))
