#!/usr/bin/env python3
"""Wire DjPolicy through brain, execution, autopilot, provider, settings UI, music."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch_brain() -> None:
    path = ROOT / "lib/dj_engine/intelligence/dj_transition_brain.dart"
    t = path.read_text()
    if "DjPolicy" in t and "policy.kindBias" in t:
        print("brain already patched")
        return

    if "import '../core/dj_policy.dart';" not in t:
        t = t.replace(
            "import '../core/dj_types.dart';\n",
            "import '../core/dj_types.dart';\nimport '../core/dj_policy.dart';\n",
            1,
        )

    old_choose = """  DjTransitionCandidate choose({
    required DjTrackProfile outgoing,
    required DjTrackProfile incoming,
    required int outgoingPositionMs,
    int preferredDurationMs = 8000,
    int maxDurationMs = 16000,
  }) {
    // Do not invent an "intelligent" transition when both profiles are
    // effectively unknown. Playback must still continue through the safe path.
    if (outgoing.analysisConfidence < 0.25 && incoming.analysisConfidence < 0.25) {
      return _fallback(incoming, preferredDurationMs);
    }

    final candidates = generate(
      outgoing: outgoing,
      incoming: incoming,
      outgoingPositionMs: outgoingPositionMs,
      preferredDurationMs: preferredDurationMs,
      maxDurationMs: maxDurationMs,
    );
    if (candidates.isEmpty) return _fallback(incoming, preferredDurationMs);
    final sorted = [...candidates]..sort((a, b) => b.score.compareTo(a.score));
    return sorted.first;
  }
"""
    new_choose = """  DjTransitionCandidate choose({
    required DjTrackProfile outgoing,
    required DjTrackProfile incoming,
    required int outgoingPositionMs,
    int preferredDurationMs = 8000,
    int maxDurationMs = 16000,
    DjPolicy policy = DjPolicy.balanced,
  }) {
    // Do not invent an "intelligent" transition when profiles are too weak
    // for the active policy floor. Playback continues through the safe path.
    final floor = policy.analysisFloor;
    if (outgoing.analysisConfidence < floor && incoming.analysisConfidence < floor) {
      return _fallback(incoming, preferredDurationMs);
    }

    final candidates = generate(
      outgoing: outgoing,
      incoming: incoming,
      outgoingPositionMs: outgoingPositionMs,
      preferredDurationMs: preferredDurationMs,
      maxDurationMs: maxDurationMs,
      policy: policy,
    );
    if (candidates.isEmpty) return _fallback(incoming, preferredDurationMs);
    final sorted = [...candidates]..sort((a, b) => b.score.compareTo(a.score));
    final best = sorted.first;
    if (!policy.acceptsCandidate(best)) {
      return _fallback(incoming, preferredDurationMs);
    }
    return best;
  }
"""
    if old_choose not in t:
        raise SystemExit("brain choose miss")
    t = t.replace(old_choose, new_choose, 1)

    # generate signature — add policy param
    old_gen = """  List<DjTransitionCandidate> generate({
    required DjTrackProfile outgoing,
    required DjTrackProfile incoming,
"""
    # Read what follows - need full generate start
    if "DjPolicy policy = DjPolicy.balanced" not in t.split("List<DjTransitionCandidate> generate")[1][:400]:
        t = t.replace(
            "  List<DjTransitionCandidate> generate({\n    required DjTrackProfile outgoing,\n    required DjTrackProfile incoming,\n",
            "  List<DjTransitionCandidate> generate({\n    required DjTrackProfile outgoing,\n    required DjTrackProfile incoming,\n    DjPolicy policy = DjPolicy.balanced,\n",
            1,
        )

    # Patch add() inside generate to apply policy scoring — look for score line
    old_add_score = """      final risk = _risks(outgoing, incoming, outgoingPositionMs, inMs);
      final confidence = _confidence(outgoing, incoming, scores);
      final score = _weightedScore(scores) - _riskPenalty(risk);
"""
    new_add_score = """      final risk = _risks(outgoing, incoming, outgoingPositionMs, inMs);
      final confidence = _confidence(outgoing, incoming, scores);
      final score = (_weightedScore(scores, policy: policy)
              - _riskPenalty(risk) * policy.riskPenaltyScale
              + policy.kindBias(kind))
          .clamp(0.0, 1.0)
          .toDouble();
"""
    if old_add_score in t:
        t = t.replace(old_add_score, new_add_score, 1)
        # remove duplicate clamp on score if present next line
        t = t.replace(
            """        score: score.clamp(0.0, 1.0).toDouble(),
""",
            """        score: score,
""",
            1,
        )
        print("brain add() scoring patched")
    else:
        print("WARNING brain add score miss")

    # weightedScore with phrase boost
    old_ws = """  double _weightedScore(Map<String, double> s) {
"""
    if "_weightedScore(Map<String, double> s, {DjPolicy policy" not in t:
        # find full method
        import re
        m = re.search(
            r"  double _weightedScore\(Map<String, double> s\) \{.*?return .*?;\n  \}",
            t,
            re.S,
        )
        if not m:
            print("WARNING weightedScore miss")
        else:
            new_ws = """  double _weightedScore(Map<String, double> s, {DjPolicy policy = DjPolicy.balanced}) {
    final phraseBoost = policy.phraseWeightBoost;
    return (s['tempo'] ?? 0.5) * 0.22 +
        (s['harmony'] ?? 0.5) * 0.18 +
        (s['energy'] ?? 0.5) * 0.16 +
        (s['spectrum'] ?? 0.5) * 0.10 +
        (s['phrase'] ?? 0.5) * (0.14 + phraseBoost) +
        (s['structure'] ?? 0.5) * 0.12 +
        (s['confidence'] ?? 0.5) * 0.08;
  }
"""
            t = t[: m.start()] + new_ws + t[m.end() :]
            print("weightedScore patched")

    path.write_text(t)
    print("brain done")


def patch_exec() -> None:
    path = ROOT / "lib/dj_engine/execution/dj_execution_planner.dart"
    t = path.read_text()
    if "DjPolicy policy" in t:
        print("exec already patched")
        return
    t = t.replace(
        "import '../core/dj_types.dart';\n",
        "import '../core/dj_types.dart';\nimport '../core/dj_policy.dart';\n",
        1,
    )
    t = t.replace(
        """  DjExecutionPlan plan({
    required DjTrackProfile outgoing,
    required DjTrackProfile incoming,
    required DjTransitionCandidate candidate,
  }) {
    final risks = riskEngine.evaluate(
      outgoing: outgoing,
      incoming: incoming,
      candidate: candidate,
    );
    final severity = riskEngine.severity(risks);

    if (severity >= 0.92) {
""",
        """  DjExecutionPlan plan({
    required DjTrackProfile outgoing,
    required DjTrackProfile incoming,
    required DjTransitionCandidate candidate,
    DjPolicy policy = DjPolicy.balanced,
  }) {
    final risks = riskEngine.evaluate(
      outgoing: outgoing,
      incoming: incoming,
      candidate: candidate,
    );
    final severity = riskEngine.severity(risks);

    if (severity >= policy.riskSeverityLimit) {
""",
        1,
    )
    path.write_text(t)
    print("exec done")


def patch_auto() -> None:
    path = ROOT / "lib/dj_engine/intelligence/dj_autopilot_planner.dart"
    t = path.read_text()
    if "DjPolicy policy" in t:
        print("auto already patched")
        return
    t = t.replace(
        "import '../core/dj_types.dart';\n",
        "import '../core/dj_types.dart';\nimport '../core/dj_policy.dart';\n",
        1,
    )
    t = t.replace(
        """  Future<DjTransitionCandidate> choose({
    required DjTrackProfile outgoing,
    required DjTrackProfile incoming,
    required int outgoingPositionMs,
    int preferredDurationMs = 8000,
    int maxDurationMs = 16000,
  }) async {
    final candidates = brain.generate(
      outgoing: outgoing,
      incoming: incoming,
      outgoingPositionMs: outgoingPositionMs,
      preferredDurationMs: preferredDurationMs,
      maxDurationMs: maxDurationMs,
    );
""",
        """  Future<DjTransitionCandidate> choose({
    required DjTrackProfile outgoing,
    required DjTrackProfile incoming,
    required int outgoingPositionMs,
    int preferredDurationMs = 8000,
    int maxDurationMs = 16000,
    DjPolicy policy = DjPolicy.balanced,
  }) async {
    final candidates = brain.generate(
      outgoing: outgoing,
      incoming: incoming,
      outgoingPositionMs: outgoingPositionMs,
      preferredDurationMs: preferredDurationMs,
      maxDurationMs: maxDurationMs,
      policy: policy,
    );
""",
        1,
    )
    t = t.replace(
        """      return brain.choose(
        outgoing: outgoing,
        incoming: incoming,
        outgoingPositionMs: outgoingPositionMs,
        preferredDurationMs: preferredDurationMs,
        maxDurationMs: maxDurationMs,
      );
""",
        """      return brain.choose(
        outgoing: outgoing,
        incoming: incoming,
        outgoingPositionMs: outgoingPositionMs,
        preferredDurationMs: preferredDurationMs,
        maxDurationMs: maxDurationMs,
        policy: policy,
      );
""",
        1,
    )
    t = t.replace(
        "final adjusted = candidate.score + learning.clamp(-0.24, 0.24);",
        "final adjusted = candidate.score +\n"
        "          policy.kindBias(candidate.kind) +\n"
        "          learning.clamp(-policy.learningClamp, policy.learningClamp);",
        1,
    )
    # After loop, gate on policy accepts
    if "policy.acceptsCandidate" not in t:
        t = t.replace(
            "    return best;\n  }\n}",
            "    if (!policy.acceptsCandidate(best)) {\n"
            "      return brain.choose(\n"
            "        outgoing: outgoing,\n"
            "        incoming: incoming,\n"
            "        outgoingPositionMs: outgoingPositionMs,\n"
            "        preferredDurationMs: preferredDurationMs,\n"
            "        maxDurationMs: maxDurationMs,\n"
            "        policy: policy,\n"
            "      );\n"
            "    }\n"
            "    return best;\n  }\n}\n",
            1,
        )
    path.write_text(t)
    print("auto done")


def patch_engine_facade() -> None:
    path = ROOT / "lib/dj_engine/dj_engine.dart"
    t = path.read_text()
    if "DjPolicy" in t:
        print("facade already")
        return
    t = t.replace(
        "import 'core/dj_types.dart';\n",
        "import 'core/dj_types.dart';\nimport 'core/dj_policy.dart';\n",
        1,
    )
    t = t.replace(
        """  DjExecutionPlan planTransition({
    required DjTrackProfile outgoing,
    required DjTrackProfile incoming,
    required int outgoingPositionMs,
    int preferredDurationMs = 8000,
    int maxDurationMs = 16000,
  }) {
    final candidate = brain.choose(
      outgoing: outgoing,
      incoming: incoming,
      outgoingPositionMs: outgoingPositionMs,
      preferredDurationMs: preferredDurationMs,
      maxDurationMs: maxDurationMs,
    );
    return execution.plan(
      outgoing: outgoing,
      incoming: incoming,
      candidate: candidate,
    );
  }
""",
        """  DjExecutionPlan planTransition({
    required DjTrackProfile outgoing,
    required DjTrackProfile incoming,
    required int outgoingPositionMs,
    int preferredDurationMs = 8000,
    int maxDurationMs = 16000,
    DjPolicy policy = DjPolicy.balanced,
  }) {
    final candidate = brain.choose(
      outgoing: outgoing,
      incoming: incoming,
      outgoingPositionMs: outgoingPositionMs,
      preferredDurationMs: preferredDurationMs,
      maxDurationMs: maxDurationMs,
      policy: policy,
    );
    return execution.plan(
      outgoing: outgoing,
      incoming: incoming,
      candidate: candidate,
      policy: policy,
    );
  }
""",
        1,
    )
    path.write_text(t)
    print("facade done")


def patch_provider() -> None:
    path = ROOT / "lib/providers/dj_mode_provider.dart"
    t = path.read_text()
    if "_aggressiveness" in t and "minConfidence" in t:
        print("provider already")
        return
    if "dj_policy.dart" not in t:
        # add import after existing imports
        t = t.replace(
            "import '../services/dj_mode_settings_store.dart';\n",
            "import '../services/dj_mode_settings_store.dart';\n"
            "import '../dj_engine/core/dj_policy.dart';\n",
            1,
        )

    # Fields after existing bools
    if "_aggressiveness" not in t:
        t = t.replace(
            "  bool _transitionSfx = true;\n",
            "  bool _transitionSfx = true;\n"
            "  DjAggressiveness _aggressiveness = DjAggressiveness.balanced;\n"
            "  double _minConfidence = 0.40;\n",
            1,
        )

    # Getters
    if "DjAggressiveness get aggressiveness" not in t:
        t = t.replace(
            "  bool get transitionSfx => _transitionSfx;\n",
            "  bool get transitionSfx => _transitionSfx;\n"
            "  DjAggressiveness get aggressiveness => _aggressiveness;\n"
            "  double get minConfidence => _minConfidence;\n"
            "  DjPolicy get policy => DjPolicy(\n"
            "        aggressiveness: _aggressiveness,\n"
            "        minConfidence: _minConfidence,\n"
            "      );\n",
            1,
        )

    # Load
    if "aggressiveness()" not in t:
        t = t.replace(
            "      _transitionSfx = await DjModeSettingsStore.transitionSfx();\n",
            "      _transitionSfx = await DjModeSettingsStore.transitionSfx();\n"
            "      _aggressiveness = await DjModeSettingsStore.aggressiveness();\n"
            "      _minConfidence = await DjModeSettingsStore.minConfidence();\n",
            1,
        )

    # Sync policy to music
    old_sync = """      music.configureDjMode(
        beatAlignActive: beatAlignActive,
        tempoMatchActive: tempoMatchActive,
        maxStretchPercent: _maxStretchPercent,
        sfxActive: _enabled && _transitionSfx,
        analysis: _analysis,
      );
"""
    new_sync = """      music.configureDjMode(
        beatAlignActive: beatAlignActive,
        tempoMatchActive: tempoMatchActive,
        maxStretchPercent: _maxStretchPercent,
        sfxActive: _enabled && _transitionSfx,
        analysis: _analysis,
        policy: policy,
      );
"""
    if old_sync in t:
        t = t.replace(old_sync, new_sync, 1)

    # Setters before runIdleScanNow or end of class setters
    if "setAggressiveness" not in t:
        insert = """
  Future<void> setAggressiveness(DjAggressiveness value) async {
    _aggressiveness = value;
    _syncToMusic();
    notifyListeners();
    await DjModeSettingsStore.setAggressiveness(value);
  }

  Future<void> setMinConfidence(double value) async {
    _minConfidence = value.clamp(0.20, 0.80);
    _syncToMusic();
    notifyListeners();
    await DjModeSettingsStore.setMinConfidence(_minConfidence);
  }

"""
        t = t.replace(
            "  Future<void> setAnalyzeIdle(bool value) async {",
            insert + "  Future<void> setAnalyzeIdle(bool value) async {",
            1,
        )

    path.write_text(t)
    print("provider done")


def patch_music() -> None:
    path = ROOT / "lib/providers/music_provider.dart"
    t = path.read_text()
    if "_djPolicy" in t and "policy: _djPolicy" in t:
        print("music already")
        return

    if "dj_policy.dart" not in t:
        t = t.replace(
            "import '../dj_engine/dj_engine.dart';\n",
            "import '../dj_engine/dj_engine.dart';\n"
            "import '../dj_engine/core/dj_policy.dart';\n",
            1,
        )

    if "_djPolicy" not in t:
        t = t.replace(
            "  bool _djSfxActive = false;\n",
            "  bool _djSfxActive = false;\n"
            "  DjPolicy _djPolicy = DjPolicy.balanced;\n",
            1,
        )

    old_cfg = """  void configureDjMode({
    required bool beatAlignActive,
    bool tempoMatchActive = false,
    int maxStretchPercent = 12,
    bool sfxActive = false,
    DjAnalysisService? analysis,
  }) {
"""
    new_cfg = """  void configureDjMode({
    required bool beatAlignActive,
    bool tempoMatchActive = false,
    int maxStretchPercent = 12,
    bool sfxActive = false,
    DjAnalysisService? analysis,
    DjPolicy policy = DjPolicy.balanced,
  }) {
    _djPolicy = policy;
"""
    if old_cfg not in t:
        raise SystemExit("configureDjMode miss")
    t = t.replace(old_cfg, new_cfg, 1)

    # Pass policy to autopilot choose and execution.plan
    old_choose = """        final learnedCandidate = await _djAutopilotPlanner.choose(
          outgoing: profileA,
          incoming: profileB,
          outgoingPositionMs: outgoing.position.inMilliseconds,
          preferredDurationMs: _crossfadeDurationMs,
          maxDurationMs: 6500,
        );
        final v2 = _djEngine.execution.plan(
          outgoing: profileA,
          incoming: profileB,
          candidate: learnedCandidate,
        );
"""
    new_choose = """        final learnedCandidate = await _djAutopilotPlanner.choose(
          outgoing: profileA,
          incoming: profileB,
          outgoingPositionMs: outgoing.position.inMilliseconds,
          preferredDurationMs: _crossfadeDurationMs,
          maxDurationMs: 6500,
          policy: _djPolicy,
        );
        final v2 = _djEngine.execution.plan(
          outgoing: profileA,
          incoming: profileB,
          candidate: learnedCandidate,
          policy: _djPolicy,
        );
"""
    if old_choose in t:
        t = t.replace(old_choose, new_choose, 1)
        print("music plan policy wired")
    else:
        print("WARNING music choose block miss")

    path.write_text(t)
    print("music done")


def patch_settings_ui() -> None:
    path = ROOT / "lib/screens/dj_mode_settings_screen.dart"
    t = path.read_text()
    if "Aggressiveness" in t and "Min confidence" in t:
        print("settings UI already")
        return

    if "dj_policy.dart" not in t:
        t = t.replace(
            "import '../providers/dj_mode_provider.dart';\n",
            "import '../providers/dj_mode_provider.dart';\n"
            "import '../dj_engine/core/dj_policy.dart';\n",
            1,
        )

    # Insert high-priority section after Features header / first tiles
    # Find "Features" section and inject after master card area
    marker = "              Text(\n                'Features',\n                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),\n              ),\n              const SizedBox(height: 8),\n"
    policy_ui = """              Text(
                'Features',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              _aggressivenessCard(context, dj, on),
              const SizedBox(height: 12),
              _minConfidenceCard(context, dj, on),
              const SizedBox(height: 16),
"""
    if marker not in t:
        raise SystemExit("features marker miss")
    t = t.replace(marker, policy_ui, 1)

    # Append helper methods before last closing of class — before final }
    helpers = '''
  Widget _aggressivenessCard(BuildContext context, DjModeProvider dj, bool on) {
    final scheme = Theme.of(context).colorScheme;
    return ResonateGlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aggressiveness',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            dj.aggressiveness.subtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          SegmentedButton<DjAggressiveness>(
            segments: [
              for (final a in DjAggressiveness.values)
                ButtonSegment(
                  value: a,
                  label: Text(a.label),
                  enabled: on,
                ),
            ],
            selected: {dj.aggressiveness},
            onSelectionChanged: on
                ? (s) {
                    if (s.isNotEmpty) dj.setAggressiveness(s.first);
                  }
                : null,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return scheme.onPrimary;
                return null;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _minConfidenceCard(BuildContext context, DjModeProvider dj, bool on) {
    final pct = (dj.minConfidence * 100).round();
    return ResonateGlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Min confidence',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'Skip fancy transitions below $pct%. Safe crossfade still works.',
            ),
            trailing: Text(
              '$pct%',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Slider(
            value: dj.minConfidence.clamp(0.20, 0.80),
            min: 0.20,
            max: 0.80,
            divisions: 12,
            label: '$pct%',
            onChanged: on ? (v) => dj.setMinConfidence(v) : null,
          ),
        ],
      ),
    );
  }
'''
    # Insert before last closing braces of the class
    # StatelessWidget ends with methods at class level after build
    if "_aggressivenessCard" not in t:
        # Find _prefTile method and insert before it
        if "  Widget _prefTile" in t:
            t = t.replace("  Widget _prefTile", helpers + "  Widget _prefTile", 1)
        else:
            # append before final class end
            idx = t.rfind("}")
            t = t[:idx] + helpers + t[idx:]

    path.write_text(t)
    print("settings UI done")


def main() -> None:
    patch_brain()
    patch_exec()
    patch_auto()
    patch_engine_facade()
    patch_provider()
    patch_music()
    patch_settings_ui()
    print("dj policy apply complete")


if __name__ == "__main__":
    main()
