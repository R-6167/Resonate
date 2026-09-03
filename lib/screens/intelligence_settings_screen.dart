import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/intelligence_provider.dart';

class IntelligenceSettingsScreen extends StatelessWidget {
  const IntelligenceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resonate Intelligence')),
      body: Consumer<IntelligenceProvider>(
        builder: (context, intelligence, _) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _section(context, 'Control'),
            SwitchListTile.adaptive(
              title: const Text('Intelligence'),
              subtitle: Text(intelligence.isEnabled ? 'Learning and anticipating locally' : 'Completely inactive; normal player behavior continues'),
              value: intelligence.isEnabled,
              onChanged: intelligence.setEnabled,
            ),
            const Divider(),
            _section(context, 'How much control should Intelligence have?'),
            RadioListTile<int>(value: 0, groupValue: intelligence.autonomy, onChanged: (v) => intelligence.setAutonomy(v!), title: const Text('Suggestions only'), subtitle: const Text('Intelligence observes and recommends. It never changes your queue.')),
            RadioListTile<int>(value: 1, groupValue: intelligence.autonomy, onChanged: (v) => intelligence.setAutonomy(v!), title: const Text('Assist me'), subtitle: const Text('Resonate highlights its strongest next-track prediction while you keep control.')),
            RadioListTile<int>(value: 2, groupValue: intelligence.autonomy, onChanged: (v) => intelligence.setAutonomy(v!), title: const Text('Autopilot'), subtitle: const Text('When confidence is high enough, Intelligence may prepare or choose the next track automatically.')),
            const Divider(),
            _section(context, 'What Intelligence knows'),
            const ListTile(leading: Icon(Icons.history_rounded), title: Text('Listening memory'), subtitle: Text('Finishes, skips, partial listens and song-to-song transitions are stored locally.')),
            const ListTile(leading: Icon(Icons.insights_rounded), title: Text('Confidence'), subtitle: Text('Predictions become stronger when repeated behavior supports the same next song.')),
            const ListTile(leading: Icon(Icons.lightbulb_outline_rounded), title: Text('Always explainable'), subtitle: Text('The player shows the evidence behind its strongest prediction instead of an unexplained score.')),
            const ListTile(leading: Icon(Icons.lock_outline_rounded), title: Text('Local-first'), subtitle: Text('The recommendation system learns from your library without requiring a cloud recommendation profile.')),
            if (intelligence.anticipatedNext != null) ...[
              const Divider(),
              _section(context, 'Current prediction'),
              ListTile(
                leading: const Icon(Icons.auto_awesome),
                title: Text(intelligence.anticipatedNext!.song.title),
                subtitle: Text('${intelligence.anticipatedNext!.confidenceLabel} • ${(intelligence.anticipatedNext!.confidence * 100).round()}% confidence\n${intelligence.anticipatedNext!.reason}'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
  );
}
