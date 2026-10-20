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
    if (t.isEmpty) {
      return const CompanionIntent(action: CompanionAction.unknown);
    }

    if (_any(t, const [
      'avoid',
      'skip this artist',
      'do not play',
      'dont play',
      'not this artist',
    ])) {
      return CompanionIntent(action: CompanionAction.avoidArtist, raw: input);
    }
    if (_any(t, const [
      'like this',
      'more like',
      'similar',
      'same vibe',
      'songs like',
    ])) {
      return CompanionIntent(action: CompanionAction.similarToCurrent, raw: input);
    }
    if (_any(t, const [
      'more adventurous',
      'more explore',
      'discover',
      'surprise me',
      'less familiar',
    ])) {
      return CompanionIntent(action: CompanionAction.increaseExploration, raw: input);
    }
    if (_any(t, const [
      'more familiar',
      'less adventurous',
      'safer',
      'stay familiar',
    ])) {
      return CompanionIntent(action: CompanionAction.decreaseExploration, raw: input);
    }
    if (_any(t, const ['evolve', 'refine mix', 'improve mix'])) {
      return CompanionIntent(action: CompanionAction.evolveMix, raw: input);
    }
    if (_any(t, const ['explain', 'why', 'session', 'what are you doing'])) {
      return CompanionIntent(action: CompanionAction.explainSession, raw: input);
    }
    if (_any(t, const [
      'play something',
      'create mix',
      'make a mix',
      'mix for me',
      'playlist',
    ])) {
      String? mood;
      if (_any(t, const ['relax', 'calm', 'chill', 'soft', 'slow'])) {
        mood = 'relaxing';
      }
      if (_any(t, const ['energy', 'energetic', 'upbeat', 'workout'])) {
        mood = 'energetic';
      }
      if (_any(t, const ['familiar', 'known', 'favorite'])) {
        mood = 'familiar';
      }
      if (_any(t, const ['explore', 'new', 'fresh'])) {
        mood = 'explore';
      }
      return CompanionIntent(
        action: CompanionAction.createMix,
        mood: mood,
        raw: input,
      );
    }
    if (_any(t, const ['play', 'start', 'go'])) {
      return CompanionIntent(
        action: CompanionAction.playTopRecommendation,
        raw: input,
      );
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
