import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/intelligence_provider.dart';
import '../services/intelligence_settings_store.dart';

class IntelligenceSettingsScreen extends StatefulWidget {
  const IntelligenceSettingsScreen({super.key});

  @override
  State<IntelligenceSettingsScreen> createState() => _IntelligenceSettingsScreenState();
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
  bool _crossfade = true;
  int _crossfadeMs = 5000;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      IntelligenceSettingsStore.exploration(),
      IntelligenceSettingsStore.confidenceThreshold(),
      IntelligenceSettingsStore.automaticQueue(),
      IntelligenceSettingsStore.artistRepeat(),
      IntelligenceSettingsStore.sessionIntelligence(),
      IntelligenceSettingsStore.explanations(),
      IntelligenceSettingsStore.learnedEq(),
      IntelligenceSettingsStore.autopilotCrossfade(),
      IntelligenceSettingsStore.autopilotCrossfadeMs(),
    ]);
    if (!mounted) return;
    setState(() {
      _exploration = values[0] as int;
      _confidence = values[1] as double;
      _automaticQueue = values[2] as bool;
      _artistRepeat = values[3] as bool;
      _sessionIntelligence = values[4] as bool;
      _explanations = values[5] as bool;
      _learnedEq = values[6] as bool;
      _crossfade = values[7] as bool;
      _crossfadeMs = values[8] as int;
      _loading = false;
    });
  }

  Future<void> _resetTuning() async {
    await IntelligenceSettingsStore.reset();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resonate Intelligence')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Consumer<IntelligenceProvider>(
              builder: (context, intelligence, _) => ListView(
                padding: const EdgeInsets.only(bottom: 36),
                children: [
                  _header(context, 'Control'),
                  SwitchListTile.adaptive(
                    title: const Text('Intelligence'),
                    subtitle: Text(intelligence.isEnabled
                        ? 'Learning and anticipating locally'
                        : 'Completely inactive; normal player behavior continues'),
                    value: intelligence.isEnabled,
                    onChanged: intelligence.setEnabled,
                  ),
                  const Divider(),
                  _header(context, 'Authority'),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Suggest')),
                      ButtonSegment(value: 1, label: Text('Assist')),
                      ButtonSegment(value: 2, label: Text('Autopilot')),
                    ],
                    selected: {intelligence.autonomy},
                    onSelectionChanged: (value) => intelligence.setAutonomy(value.first),
                    multiSelectionEnabled: false,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      intelligence.isAutopilot
                          ? 'Autopilot may prepare and choose the next track when confidence is high enough.'
                          : 'Your normal player remains in control until you allow more autonomy.',
                    ),
                  ),
                  _header(context, 'Decision tuning'),
                  ListTile(
                    title: const Text('Exploration ↔ familiarity'),
                    subtitle: Text('${_exploration}% exploration • higher values discover more new music'),
                  ),
                  Slider(
                    value: _exploration.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '$_exploration%',
                    onChanged: (value) => setState(() => _exploration = value.round()),
                    onChangeEnd: (value) => IntelligenceSettingsStore.setExploration(value.round()),
                  ),
                  ListTile(
                    title: const Text('Autopilot confidence threshold'),
                    subtitle: Text('${(_confidence * 100).round()}% • only stronger predictions can take over automatically'),
                  ),
                  Slider(
                    value: _confidence,
                    min: .45,
                    max: .90,
                    divisions: 9,
                    label: '${(_confidence * 100).round()}%',
                    onChanged: (value) => setState(() => _confidence = value),
                    onChangeEnd: IntelligenceSettingsStore.setConfidenceThreshold,
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('Automatic queue'),
                    subtitle: const Text('Keep a small runway of likely next tracks ready.'),
                    value: _automaticQueue,
                    onChanged: (value) async {
                      setState(() => _automaticQueue = value);
                      await IntelligenceSettingsStore.setAutomaticQueue(value);
                    },
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('Allow artist repetition'),
                    subtitle: const Text('Permit consecutive recommendations from the same artist.'),
                    value: _artistRepeat,
                    onChanged: (value) async {
                      setState(() => _artistRepeat = value);
                      await IntelligenceSettingsStore.setArtistRepeat(value);
                    },
                  ),
                  _header(context, 'Session Intelligence'),
                  SwitchListTile.adaptive(
                    title: const Text('Use current-session signals'),
                    subtitle: const Text('Let recent skips, completions and artists steer the next decision.'),
                    value: _sessionIntelligence,
                    onChanged: (value) async {
                      setState(() => _sessionIntelligence = value);
                      await IntelligenceSettingsStore.setSessionIntelligence(value);
                    },
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('Show recommendation explanations'),
                    subtitle: const Text('Display why a track was selected.'),
                    value: _explanations,
                    onChanged: (value) async {
                      setState(() => _explanations = value);
                      await IntelligenceSettingsStore.setExplanations(value);
                    },
                  ),
                  _header(context, 'Audio Intelligence'),
                  SwitchListTile.adaptive(
                    title: const Text('Learned per-song EQ'),
                    subtitle: const Text('Allow Intelligence to remember sound preferences per song.'),
                    value: _learnedEq,
                    onChanged: (value) async {
                      setState(() => _learnedEq = value);
                      await IntelligenceSettingsStore.setLearnedEq(value);
                    },
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('Autopilot crossfade'),
                    subtitle: Text(_crossfade ? '${(_crossfadeMs / 1000).toStringAsFixed(1)} second transition' : 'Disabled'),
                    value: _crossfade,
                    onChanged: (value) async {
                      setState(() => _crossfade = value);
                      await IntelligenceSettingsStore.setAutopilotCrossfade(value);
                    },
                  ),
                  if (_crossfade)
                    Slider(
                      value: _crossfadeMs.toDouble(),
                      min: 1000,
                      max: 12000,
                      divisions: 11,
                      label: '${(_crossfadeMs / 1000).toStringAsFixed(1)}s',
                      onChanged: (value) => setState(() => _crossfadeMs = value.round()),
                      onChangeEnd: IntelligenceSettingsStore.setAutopilotCrossfadeMs,
                    ),
                  _header(context, 'Learning'),
                  ListTile(
                    leading: const Icon(Icons.insights_rounded),
                    title: Text('Session: ${intelligence.sessionMode}'),
                    subtitle: Text(intelligence.sessionSummary),
                  ),
                  ListTile(
                    leading: const Icon(Icons.auto_awesome),
                    title: Text(intelligence.anticipatedNext?.song.title ?? 'No prediction yet'),
                    subtitle: Text(intelligence.anticipatedNext == null
                        ? 'Keep listening and Resonate will build local evidence.'
                        : '${(intelligence.anticipatedNext!.confidence * 100).round()}% confidence • ${intelligence.anticipatedNext!.reason}'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.restart_alt_rounded),
                    title: const Text('Reset advanced tuning'),
                    subtitle: const Text('Return all Intelligence controls to conservative defaults.'),
                    onTap: () => _confirmReset(context),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _header(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
      );

  Future<void> _confirmReset(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset advanced tuning?'),
        content: const Text('This resets the decision controls, but keeps listening history and learned song feedback.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
        ],
      ),
    );
    if (yes == true) await _resetTuning();
  }
}
