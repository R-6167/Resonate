/// Structured command produced by the offline rule-based parser.
enum CompanionAction {
  createMix,
  similarToCurrent,
  avoidArtist,
  increaseExploration,
  decreaseExploration,
  explainSession,
  evolveMix,
  playTopRecommendation,
  unknown,
}

class CompanionIntent {
  final CompanionAction action;
  final String? mood; // relaxing | energetic | familiar | explore
  final String raw;

  const CompanionIntent({
    required this.action,
    this.mood,
    this.raw = '',
  });
}

/// Keyword / rule parser — no cloud model.
class LocalIntentParser {
  CompanionIntent parse(String input) {
    final t = input.trim().toLowerCase();
    if (t.isEmpty) return const CompanionIntent(action: CompanionAction.unknown);

    if (_any(t, ['avoid', 'skip this artist', 'don't play', 'dont play', 'not this artist'])) {
      return CompanionIntent(action: CompanionAction.avoidArtist, raw: input);
    }
    if (_any(t, ['like this', 'more like', 'similar', 'same vibe', 'songs like'])) {
      return CompanionIntent(action: CompanionAction.similarToCurrent, raw: input);
    }
    if (_any(t, ['more adventurous', 'more explore', 'discover', 'surprise me', 'less familiar'])) {
      return CompanionIntent(action: CompanionAction.increaseExploration, raw: input);
    }
    if (_any(t, ['more familiar', 'less adventurous', 'safer', 'stay familiar'])) {
      return CompanionIntent(action: CompanionAction.decreaseExploration, raw: input);
    }
    if (_any(t, ['evolve', 'refine mix', 'improve mix'])) {
      return CompanionIntent(action: CompanionAction.evolveMix, raw: input);
    }
    if (_any(t, ['explain', 'why', 'session', 'what are you doing'])) {
      return CompanionIntent(action: CompanionAction.explainSession, raw: input);
    }
    if (_any(t, ['play something', 'create mix', 'make a mix', 'mix for me', 'playlist'])) {
      String? mood;
      if (_any(t, ['relax', 'calm', 'chill', 'soft', 'slow'])) mood = 'relaxing';
      if (_any(t, ['energy', 'energetic', 'upbeat', 'workout'])) mood = 'energetic';
      if (_any(t, ['familiar', 'known', 'favorite'])) mood = 'familiar';
      if (_any(t, ['explore', 'new', 'fresh'])) mood = 'explore';
      return CompanionIntent(action: CompanionAction.createMix, mood: mood, raw: input);
    }
    if (_any(t, ['play', 'start', 'go'])) {
      return CompanionIntent(action: CompanionAction.playTopRecommendation, raw: input);
    }
    return CompanionIntent(action: CompanionAction.unknown, raw: input);
  }

  bool _any(String text, List<String> keys) {
    for (final k in keys) {
      if (text.contains(k)) return true;
    }
    return false;
  }
}
