/// Camelot-wheel harmonic compatibility for DJ Mode Step 4.
///
/// Scores are soft bias only — never a hard filter. Missing key → neutral (0).
library;

/// Pitch class 0–11 (C=0 … B=11) + major/minor → Camelot number 1–12 and letter A/B.
class CamelotKey {
  final int number; // 1–12
  final String letter; // 'A' minor, 'B' major
  final int keyRoot;
  final String keyMode;

  const CamelotKey({
    required this.number,
    required this.letter,
    required this.keyRoot,
    required this.keyMode,
  });

  String get code => '$number$letter';

  @override
  String toString() => code;
}

const List<int> _majorCamelotByRoot = [
  8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6, 1,
];

const List<int> _minorCamelotByRoot = [
  5, 12, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10,
];

CamelotKey? camelotFromRootMode(int keyRoot, String keyMode) {
  if (keyRoot < 0 || keyRoot > 11) return null;
  final mode = keyMode.trim().toLowerCase();
  final isMinor = mode == 'minor' || mode == 'min' || mode == 'm';
  final isMajor = mode == 'major' || mode == 'maj' || mode == '';
  if (!isMinor && !isMajor) return null;
  final number = isMinor ? _minorCamelotByRoot[keyRoot] : _majorCamelotByRoot[keyRoot];
  return CamelotKey(
    number: number,
    letter: isMinor ? 'A' : 'B',
    keyRoot: keyRoot,
    keyMode: isMinor ? 'minor' : 'major',
  );
}

/// Parse free-text key tags: "Am", "C major", "8A", "F#m", "Bb", etc.
({int root, String mode})? parseKeyText(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return null;
  final camelot = RegExp(r'^(\d{1,2})\s*([ABab])$').firstMatch(t);
  if (camelot != null) {
    final n = int.tryParse(camelot.group(1)!);
    final letter = camelot.group(2)!.toUpperCase();
    if (n != null && n >= 1 && n <= 12 && (letter == 'A' || letter == 'B')) {
      return _rootModeFromCamelot(n, letter);
    }
  }
  t = t.replaceAll(RegExp(r'\s+'), ' ');
  t = t.replaceFirst(RegExp(r'^key\s*[:=]\s*', caseSensitive: false), '');
  final lower = t.toLowerCase();
  var mode = 'major';
  if (lower.contains('minor') || lower.endsWith('min') || RegExp(r'(^|[^a-z])m$').hasMatch(lower.replaceAll('major', ''))) {
    mode = 'minor';
  }
  if (lower.contains('major') || lower.endsWith('maj')) {
    mode = 'major';
  }
  final note = RegExp(
    r'([A-Ga-g])\s*([#♯b♭])?\s*(m|min|minor|maj|major)?',
  ).firstMatch(t);
  if (note == null) return null;
  final letter = note.group(1)!.toUpperCase();
  final acc = note.group(2) ?? '';
  final modeHint = note.group(3)?.toLowerCase();
  if (modeHint == 'm' || modeHint == 'min' || modeHint == 'minor') mode = 'minor';
  if (modeHint == 'maj' || modeHint == 'major') mode = 'major';
  if (RegExp(r'[A-Ga-g][#♯b♭]?m$', caseSensitive: false).hasMatch(t.replaceAll(' ', '')) &&
      !lower.contains('major')) {
    mode = 'minor';
  }
  const natural = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
  var root = natural[letter];
  if (root == null) return null;
  if (acc == '#' || acc == '♯') root = (root + 1) % 12;
  if (acc == 'b' || acc == '♭') root = (root + 11) % 12;
  return (root: root, mode: mode);
}

({int root, String mode})? _rootModeFromCamelot(int number, String letter) {
  if (letter == 'B') {
    for (var r = 0; r < 12; r++) {
      if (_majorCamelotByRoot[r] == number) return (root: r, mode: 'major');
    }
  } else {
    for (var r = 0; r < 12; r++) {
      if (_minorCamelotByRoot[r] == number) return (root: r, mode: 'minor');
    }
  }
  return null;
}

/// Soft compatibility in \[0, 1\]. Neutral when either key is missing.
double harmonicCompatibility({
  required int? rootA,
  required String? modeA,
  required int? rootB,
  required String? modeB,
}) {
  if (rootA == null || modeA == null || rootB == null || modeB == null) {
    return 0.0;
  }
  final a = camelotFromRootMode(rootA, modeA);
  final b = camelotFromRootMode(rootB, modeB);
  if (a == null || b == null) return 0.0;
  if (a.number == b.number && a.letter == b.letter) return 1.0;
  if (a.number == b.number && a.letter != b.letter) return 0.88;
  final dist = _ringDistance(a.number, b.number);
  if (dist == 1 && a.letter == b.letter) return 0.72;
  if (dist == 1) return 0.45;
  if (dist == 2 && a.letter == b.letter) return 0.35;
  return 0.0;
}

int _ringDistance(int a, int b) {
  final d = (a - b).abs();
  return d > 6 ? 12 - d : d;
}

/// Bounded boost for Intelligence decision utility (points, not a filter).
double harmonicDecisionBoost(double compatibility) {
  if (compatibility <= 0) return 0.0;
  return (compatibility * 1.35).clamp(0.0, 1.35);
}
