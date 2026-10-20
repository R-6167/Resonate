import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../providers/intelligence_mix_controller.dart';
import '../../providers/intelligence_provider.dart';
import '../../providers/music_provider.dart';
import '../../services/companion_command_executor.dart';
import '../../services/local_intent_parser.dart';
import 'ask_resonate_controller.dart';
import 'organic_blob_clipper.dart';

/// Full-screen living overlay driven by [AskResonateController].
class AskResonateOverlay extends StatefulWidget {
  const AskResonateOverlay({super.key});

  @override
  State<AskResonateOverlay> createState() => _AskResonateOverlayState();
}

class _AskResonateOverlayState extends State<AskResonateOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _openCtrl;
  late final AnimationController _breatheCtrl;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _openCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..repeat(reverse: true);

    _progress = CurvedAnimation(
      parent: _openCtrl,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openCtrl.forward();
    });
  }

  @override
  void dispose() {
    _openCtrl.dispose();
    _breatheCtrl.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _openCtrl.reverse();
    if (mounted) context.read<AskResonateController>().close();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AskResonateController>();
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_progress, _breatheCtrl]),
        builder: (context, _) {
          final p = _progress.value.clamp(0.0, 1.0);
          final breathe = _breatheCtrl.value;

          return Stack(
            fit: StackFit.expand,
            children: [
              // Dim + blur barrier
              GestureDetector(
                onTap: _close,
                behavior: HitTestBehavior.opaque,
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 10 * p,
                    sigmaY: 10 * p,
                  ),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.38 * p),
                  ),
                ),
              ),

              // Living blob panel
              Center(
                child: Opacity(
                  opacity: p,
                  child: Transform.scale(
                    scale: 0.72 + 0.28 * p,
                    child: ClipPath(
                      clipper: OrganicBlobClipper(
                        progress: p,
                        breathe: breathe,
                      ),
                      child: Container(
                        width: size.width * 0.94,
                        height: size.height * 0.64,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              scheme.surfaceContainerHigh.withValues(alpha: 0.96),
                              scheme.primaryContainer.withValues(alpha: 0.88),
                              scheme.secondaryContainer.withValues(alpha: 0.75),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.28 * p),
                              blurRadius: 48,
                              spreadRadius: 6,
                            ),
                          ],
                        ),
                        child: _AskResonateContent(
                          contextLabel: ctrl.contextLabel,
                          onClose: _close,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AskResonateContent extends StatefulWidget {
  final String contextLabel;
  final VoidCallback onClose;

  const _AskResonateContent({
    required this.contextLabel,
    required this.onClose,
  });

  @override
  State<_AskResonateContent> createState() => _AskResonateContentState();
}

class _AskResonateContentState extends State<_AskResonateContent> {
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

  @override
  Widget build(BuildContext context) {
    final intelligence = context.watch<IntelligenceProvider>();
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ask Resonate',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.contextLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              intelligence.isEnabled
                  ? (intelligence.sessionSummary.isNotEmpty
                      ? intelligence.sessionSummary
                      : 'Local companion — pick a command or type a short request.')
                  : 'Intelligence is off. You can still read tips, but actions need it enabled in Settings.',
              style: theme.textTheme.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final (title, subtitle, intent) in _commands)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        _iconFor(intent.action),
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(subtitle),
                      trailing: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right, size: 20),
                      onTap: _busy ? null : () => _run(intent),
                    )
                        .animate()
                        .fadeIn(duration: 280.ms, curve: Curves.easeOut)
                        .slideY(
                          begin: 0.12,
                          end: 0,
                          duration: 320.ms,
                          curve: Curves.easeOutCubic,
                        ),
                  const Divider(height: 20),
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (v) {
                      if (_busy) return;
                      _run(_parser.parse(v));
                    },
                  ),
                  if (_result != null) ...[
                    const SizedBox(height: 12),
                    Material(
                      color: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _result!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
