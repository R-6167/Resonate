import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/intelligence_provider.dart';
import '../services/intelligence_mix_settings_store.dart';
import '../services/intelligence_pattern_store.dart';
import '../services/intelligence_settings_store.dart';

class IntelligenceSettingsScreen extends StatefulWidget {
  const IntelligenceSettingsScreen({super.key});
  @override State<IntelligenceSettingsScreen> createState() => _IntelligenceSettingsScreenState();
}

class _IntelligenceSettingsScreenState extends State<IntelligenceSettingsScreen> {
  bool _loading = true;
  int _exploration = 35;
  double _confidence = .65;
  bool _automaticQueue = true;
  bool _artistRepeat = false;
  bool _sessionIntelligence = true;
  bool _explanations = true;
  bool _learnedEq = false;
  bool _crossfade = false;
  int _crossfadeMs = 5000;
  int _mixMinutes = 60;
  bool _longMix = true;
  int _minimumLongMix = 20;
  int _replaySensitivity = 2;
  bool _autoEvolution = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final values = await Future.wait([
      IntelligenceSettingsStore.exploration(), IntelligenceSettingsStore.confidenceThreshold(), IntelligenceSettingsStore.automaticQueue(), IntelligenceSettingsStore.artistRepeat(),
      IntelligenceSettingsStore.sessionIntelligence(), IntelligenceSettingsStore.explanations(), IntelligenceSettingsStore.learnedEq(), IntelligenceSettingsStore.autopilotCrossfade(), IntelligenceSettingsStore.autopilotCrossfadeMs(),
      IntelligenceMixSettingsStore.targetMinutes(), IntelligenceMixSettingsStore.longFormEnabled(), IntelligenceMixSettingsStore.minimumLongFormMinutes(), IntelligenceMixSettingsStore.replaySensitivity(), IntelligenceMixSettingsStore.autoEvolutionEnabled(),
    ]);
    if (!mounted) return;
    setState(() { _exploration = values[0] as int; _confidence = values[1] as double; _automaticQueue = values[2] as bool; _artistRepeat = values[3] as bool; _sessionIntelligence = values[4] as bool; _explanations = values[5] as bool; _learnedEq = values[6] as bool; _crossfade = values[7] as bool; _crossfadeMs = values[8] as int; _mixMinutes = values[9] as int; _longMix = values[10] as bool; _minimumLongMix = values[11] as int; _replaySensitivity = values[12] as int; _autoEvolution = values[13] as bool; _loading = false; });
  }

  Future<void> _resetTuning() async { await IntelligenceSettingsStore.reset(); await IntelligenceMixSettingsStore.reset(); await _load(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resonate Intelligence')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : Consumer<IntelligenceProvider>(builder: (context, intelligence, _) => ListView(padding: const EdgeInsets.only(bottom: 36), children: [
        _header(context, 'Core control', 'When Intelligence is active and how much authority it has.'),
        SwitchListTile.adaptive(title: const Text('Intelligence'), subtitle: Text(intelligence.isEnabled ? 'Learning and anticipating locally' : 'Completely inactive; normal player behavior continues'), value: intelligence.isEnabled, onChanged: intelligence.setEnabled),
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('Autonomy', style: Theme.of(context).textTheme.titleMedium)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: SegmentedButton<int>(segments: const [ButtonSegment(value: 0, label: Text('Suggest')), ButtonSegment(value: 1, label: Text('Assist')), ButtonSegment(value: 2, label: Text('Autopilot'))], selected: {intelligence.autonomy}, onSelectionChanged: (value) => intelligence.setAutonomy(value.first))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: Text(intelligence.isAutopilot ? 'Autopilot may prepare and choose the next track when confidence is high enough.' : 'Your normal player remains in control until you allow more autonomy.', style: Theme.of(context).textTheme.bodySmall)),

        _header(context, 'Recommendation behavior', 'Shape how Resonate balances confidence, discovery and repetition.'),
        ListTile(title: const Text('Exploration ↔ familiarity'), subtitle: Text('$_exploration% exploration • higher values discover more new music')),
        Slider(value: _exploration.toDouble(), min: 0, max: 100, divisions: 20, label: '$_exploration%', onChanged: (v) => setState(() => _exploration = v.round()), onChangeEnd: (v) => IntelligenceSettingsStore.setExploration(v.round())),
        ListTile(title: const Text('Confidence threshold'), subtitle: Text('${(_confidence * 100).round()}% • automatic decisions need stronger evidence than suggestions')),
        Slider(value: _confidence, min: .45, max: .90, divisions: 9, label: '${(_confidence * 100).round()}%', onChanged: (v) => setState(() => _confidence = v), onChangeEnd: (v) => IntelligenceSettingsStore.setConfidenceThreshold(v)),
        SwitchListTile.adaptive(title: const Text('Automatic queue'), subtitle: const Text('Keep a small runway of likely next tracks ready.'), value: _automaticQueue, onChanged: (v) async { setState(() => _automaticQueue = v); await IntelligenceSettingsStore.setAutomaticQueue(v); }),
        SwitchListTile.adaptive(title: const Text('Allow artist repetition'), subtitle: const Text('Permit consecutive recommendations from the same artist.'), value: _artistRepeat, onChanged: (v) async { setState(() => _artistRepeat = v); await IntelligenceSettingsStore.setArtistRepeat(v); }),

        _header(context, 'Session awareness', 'Let the current listening session influence what feels right next.'),
        SwitchListTile.adaptive(title: const Text('Use current-session signals'), subtitle: const Text('Recent skips, completions and artists can steer the next decision.'), value: _sessionIntelligence, onChanged: (v) async { setState(() => _sessionIntelligence = v); await IntelligenceSettingsStore.setSessionIntelligence(v); }),
        SwitchListTile.adaptive(title: const Text('Show recommendation explanations'), subtitle: const Text('Display why a track was selected and its confidence.'), value: _explanations, onChanged: (v) async { setState(() => _explanations = v); await IntelligenceSettingsStore.setExplanations(v); }),

        _header(context, 'Companion journeys', 'Controls for longer, evolving listening sessions.'),
        ListTile(title: const Text('Generated mix length'), subtitle: Text('$_mixMinutes minutes • target length for new Companion journeys'), trailing: const Icon(Icons.schedule_rounded), onTap: () => _chooseMixLength(context)),
        SwitchListTile.adaptive(title: const Text('Long-form mix analysis'), subtitle: Text(_longMix ? 'Learn from long tracks, replayed sections and common exits' : 'Long-form analysis is disabled'), value: _longMix, onChanged: (v) async { setState(() => _longMix = v); await IntelligenceMixSettingsStore.setLongFormEnabled(v); }),
        if (_longMix) ...[
          ListTile(title: const Text('Long-form threshold'), subtitle: Text('$_minimumLongMix minutes • tracks at or above this length can be analyzed')),
          Slider(value: _minimumLongMix.toDouble(), min: 10, max: 60, divisions: 10, label: '$_minimumLongMix min', onChanged: (v) => setState(() => _minimumLongMix = v.round()), onChangeEnd: (v) => IntelligenceMixSettingsStore.setMinimumLongFormMinutes(v.round())),
          ListTile(title: const Text('Replay sensitivity'), subtitle: Text('$_replaySensitivity/5 • how much repeated rewinding should strengthen a long-mix section')),
          Slider(value: _replaySensitivity.toDouble(), min: 1, max: 5, divisions: 4, label: '$_replaySensitivity/5', onChanged: (v) => setState(() => _replaySensitivity = v.round()), onChangeEnd: (v) => IntelligenceMixSettingsStore.setReplaySensitivity(v.round())),
        ],
        SwitchListTile.adaptive(title: const Text('Evolve Companion mixes'), subtitle: const Text('Allow saved mix journeys to become new editions from actual listening behavior.'), value: _autoEvolution, onChanged: (v) async { setState(() => _autoEvolution = v); await IntelligenceMixSettingsStore.setAutoEvolutionEnabled(v); }),

        _header(context, 'Audio intelligence', 'Allow Resonate to remember sound preferences and coordinate transitions.'),
        SwitchListTile.adaptive(title: const Text('Learned per-song EQ'), subtitle: const Text('Allow Intelligence to remember sound preferences per song.'), value: _learnedEq, onChanged: (v) async { setState(() => _learnedEq = v); await IntelligenceSettingsStore.setLearnedEq(v); }),
        SwitchListTile.adaptive(title: const Text('Autopilot crossfade'), subtitle: Text(_crossfade ? '${(_crossfadeMs / 1000).toStringAsFixed(1)} second transition' : 'Disabled'), value: _crossfade, onChanged: (v) async { setState(() => _crossfade = v); await IntelligenceSettingsStore.setAutopilotCrossfade(v); }),
        if (_crossfade) Slider(value: _crossfadeMs.toDouble(), min: 1000, max: 12000, divisions: 11, label: '${(_crossfadeMs / 1000).toStringAsFixed(1)}s', onChanged: (v) => setState(() => _crossfadeMs = v.round()), onChangeEnd: (v) => IntelligenceSettingsStore.setAutopilotCrossfadeMs(v.round())),

        _header(context, 'Companion memory & insight', 'See what Resonate currently believes and reset tuning without deleting learned history.'),
        FutureBuilder<List<Map<String, dynamic>>>(future: Future.wait([IntelligencePatternStore.readBucket(DateTime.now()), IntelligencePatternStore.readStateProfile()]), builder: (context, snapshot) {
          final bucket = snapshot.data != null && snapshot.data!.isNotEmpty ? snapshot.data![0] : const <String, dynamic>{};
          final profile = snapshot.data != null && snapshot.data!.length > 1 ? snapshot.data![1] : const <String, dynamic>{};
          final state = IntelligencePatternStore.stateFor(bucket); final global = IntelligencePatternStore.globalState(profile); final confidence = IntelligencePatternStore.stateConfidence(profile); final momentum = IntelligencePatternStore.stateMomentum(profile);
          return Column(children: [
            ListTile(leading: const Icon(Icons.psychology_rounded), title: Text('This window: $state'), subtitle: Text(IntelligencePatternStore.explanationFor(state, bucket))),
            ListTile(leading: const Icon(Icons.history_rounded), title: Text('Across sessions: $global'), subtitle: Text(confidence == 0 ? 'Still learning your recurring listening pattern.' : '${(confidence * 100).round()}% of learned states point here${momentum >= .5 ? ' • pattern is holding' : ''}.')),
            ListTile(leading: const Icon(Icons.auto_awesome_rounded), title: Text(intelligence.anticipatedNext?.song.title ?? 'No prediction yet'), subtitle: Text(intelligence.anticipatedNext == null ? 'Keep listening and Resonate will build local evidence.' : '${(intelligence.anticipatedNext!.confidence * 100).round()}% confidence • ${intelligence.anticipatedNext!.reason}')),
            ListTile(leading: const Icon(Icons.restart_alt_rounded), title: const Text('Reset advanced tuning'), subtitle: const Text('Return decision and mix controls to conservative defaults; learned memory stays intact.'), onTap: () => _confirmReset(context)),
          ]);
        }),
      ])),
    );
  }

  Widget _header(BuildContext context, String title, String subtitle) => Padding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)), const SizedBox(height: 3), Text(subtitle, style: Theme.of(context).textTheme.bodySmall)]));

  Future<void> _chooseMixLength(BuildContext context) async {
    final value = await showDialog<int>(context: context, builder: (_) => SimpleDialog(title: const Text('Generated mix length'), children: [for (final minutes in [30, 45, 60, 90, 120]) SimpleDialogOption(onPressed: () => Navigator.pop(context, minutes), child: Text('$minutes minutes'))]));
    if (value == null) return;
    setState(() => _mixMinutes = value);
    await IntelligenceMixSettingsStore.setTargetMinutes(value);
  }

  Future<void> _confirmReset(BuildContext context) async {
    final yes = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Reset advanced tuning?'), content: const Text('This resets decision and mix controls, but keeps listening history, learned song feedback and Companion memory.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset'))]));
    if (yes == true) await _resetTuning();
  }
}
