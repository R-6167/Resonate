import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/intelligence_mix_controller.dart';
import '../providers/intelligence_provider.dart';
import '../providers/music_provider.dart';
import '../services/companion_command_executor.dart';
import '../services/local_intent_parser.dart';
import 'blur_sheet.dart';

/// Floating “Ask Resonate” entry — show only on For You / Library / Player.
class AskResonateFab extends StatelessWidget {
  const AskResonateFab({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: 'ask_resonate_fab',
      onPressed: () => openAskResonate(context),
      icon: const Icon(Icons.auto_awesome),
      label: const Text('Ask Resonate'),
    );
  }
}

Future<void> openAskResonate(BuildContext context) {
  return showBlurredModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => const _AskResonateBody(),
  );
}

class _AskResonateBody extends StatefulWidget {
  const _AskResonateBody();
  @override
  State<_AskResonateBody> createState() => _AskResonateBodyState();
}

class _AskResonateBodyState extends State<_AskResonateBody> {
  final _parser = LocalIntentParser();
  final _text = TextEditingController();
  String? _result;
  bool _busy = false;

  static const _commands = <(String, String, CompanionIntent)>[
    (
      'More like this',
      'Similar to what’s playing',
      CompanionIntent(action: CompanionAction.similarToCurrent),
    ),
    (
      'Calmer mix',
      'Local mix with a softer lean',
      CompanionIntent(action: CompanionAction.createMix, mood: 'relaxing'),
    ),
    (
      'More adventurous',
      'Raise exploration for this session',
      CompanionIntent(action: CompanionAction.increaseExploration),
    ),
    (
      'More familiar',
      'Lower exploration — stick closer to patterns',
      CompanionIntent(action: CompanionAction.decreaseExploration),
    ),
    (
      'Avoid this artist',
      'Downrank the current artist',
      CompanionIntent(action: CompanionAction.avoidArtist),
    ),
    (
      'Explain session',
      'What the companion sees right now',
      CompanionIntent(action: CompanionAction.explainSession),
    ),
    (
      'Evolve mix',
      'Refine the current automatic mix',
      CompanionIntent(action: CompanionAction.evolveMix),
    ),
    (
      'Play top pick',
      'Start the strongest local recommendation',
      CompanionIntent(action: CompanionAction.playTopRecommendation),
    ),
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(CompanionIntent intent) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    final executor = CompanionCommandExecutor(
      music: context.read<MusicProvider>(),
      intelligence: context.read<IntelligenceProvider>(),
      mixes: context.read<IntelligenceMixController>(),
    );
    final result = await executor.execute(intent);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final intelligence = context.watch<IntelligenceProvider>();
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ask Resonate',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                intelligence.isEnabled
                    ? (intelligence.sessionSummary.isNotEmpty
                        ? intelligence.sessionSummary
                        : 'Local companion — pick a command or type a short request.')
                    : 'Intelligence is off. You can still read tips, but actions need it enabled in Settings.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              for (final (title, subtitle, intent) in _commands)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _iconFor(intent.action),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(subtitle),
                  trailing: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right),
                  onTap: _busy ? null : () => _run(intent),
                ),
              const Divider(height: 24),
              TextField(
                controller: _text,
                enabled: !_busy,
                textInputAction: TextInputAction.go,
                decoration: InputDecoration(
                  hintText: 'e.g. play something relaxing',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send_rounded),
                    onPressed: _busy
                        ? null
                        : () {
                            final intent = _parser.parse(_text.text);
                            _run(intent);
                          },
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (v) {
                  if (_busy) return;
                  _run(_parser.parse(v));
                },
              ),
              if (_result != null) ...[
                const SizedBox(height: 14),
                Material(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_result!, style: Theme.of(context).textTheme.bodyMedium),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(CompanionAction action) {
    return switch (action) {
      CompanionAction.similarToCurrent => Icons.handshake_outlined,
      CompanionAction.createMix => Icons.queue_music_rounded,
      CompanionAction.increaseExploration => Icons.explore_outlined,
      CompanionAction.decreaseExploration => Icons.home_outlined,
      CompanionAction.avoidArtist => Icons.block_rounded,
      CompanionAction.explainSession => Icons.info_outline_rounded,
      CompanionAction.evolveMix => Icons.alt_route_rounded,
      CompanionAction.playTopRecommendation => Icons.play_arrow_rounded,
      CompanionAction.unknown => Icons.help_outline_rounded,
    };
  }
}
