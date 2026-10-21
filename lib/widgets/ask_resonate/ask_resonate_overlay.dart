import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/audio_visualization_provider.dart';
import '../../providers/intelligence_mix_controller.dart';
import '../../providers/intelligence_provider.dart';
import '../../providers/music_provider.dart';
import '../../services/companion_command_executor.dart';
import 'ask_resonate_controller.dart';
import 'shape_clippers.dart';

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
    );

    _progress = CurvedAnimation(
      parent: _openCtrl,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduce =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduce) {
        _openCtrl.value = 1;
      } else {
        _openCtrl.forward();
        _breatheCtrl.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _openCtrl.dispose();
    _breatheCtrl.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      if (mounted) context.read<AskResonateController>().close();
      return;
    }
    await _openCtrl.reverse();
    if (mounted) context.read<AskResonateController>().close();
  }

  double _audioEnergy(AudioVisualizationProvider viz) {
    if (!viz.enabled || viz.frequencies.isEmpty) return 0;
    final n = math.min(8, viz.frequencies.length);
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      sum += viz.frequencies[i];
    }
    if (!viz.orbAudioReactive) return 0;
    return (sum / n * viz.sensitivity).clamp(0.0, 1.0);
  }

  Size _panelSize(Size screen, AskResonateShape shape) {
    switch (shape) {
      case AskResonateShape.blob:
        return Size(screen.width * 0.94, screen.height * 0.64);
      case AskResonateShape.semicircle:
        return Size(screen.width * 0.72, screen.height * 0.78);
      case AskResonateShape.capsule:
        return Size(screen.width * 0.92, screen.height * 0.48);
      case AskResonateShape.orbital:
        final side = math.min(screen.width, screen.height) * 0.78;
        return Size(side, side);
    }
  }

  Alignment _panelAlignment(AskResonateShape shape) {
    switch (shape) {
      case AskResonateShape.semicircle:
        return Alignment.centerRight;
      case AskResonateShape.capsule:
        return const Alignment(0, 0.15);
      case AskResonateShape.blob:
      case AskResonateShape.orbital:
        return Alignment.center;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AskResonateController>();
    final viz = context.watch<AudioVisualizationProvider>();
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final energy = reduceMotion ? 0.0 : _audioEnergy(viz);

    final panel = _panelSize(size, ctrl.shape);
    final align = _panelAlignment(ctrl.shape);

    final orb = ctrl.orbGlobalPosition;
    final screenCenter = Offset(size.width / 2, size.height / 2);
    Offset originOffset(double p) {
      if (orb == null || reduceMotion) return Offset.zero;
      final target = Offset(
        screenCenter.dx + (align.x) * (size.width - panel.width) / 2,
        screenCenter.dy + (align.y) * (size.height - panel.height) / 2,
      );
      final delta = orb - target;
      return Offset(delta.dx * (1 - p), delta.dy * (1 - p));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_progress, _breatheCtrl]),
        builder: (context, _) {
          final p = reduceMotion ? 1.0 : _progress.value.clamp(0.0, 1.0);
          final breathe = reduceMotion ? 0.0 : _breatheCtrl.value;
          final offset = originOffset(p);

          return Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onTap: _close,
                behavior: HitTestBehavior.opaque,
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: (reduceMotion ? 6 : 10) * p,
                    sigmaY: (reduceMotion ? 6 : 10) * p,
                  ),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.38 * p),
                  ),
                ),
              ),
              Align(
                alignment: align,
                child: Transform.translate(
                  offset: offset,
                  child: Opacity(
                    opacity: p,
                    child: Transform.scale(
                      scale: reduceMotion ? 1.0 : (0.72 + 0.28 * p),
                      child: SizedBox(
                        width: panel.width,
                        height: panel.height,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipPath(
                              clipper: clipperForShape(
                                shape: ctrl.shape,
                                progress: p,
                                breathe: breathe,
                                audioEnergy: energy,
                              ),
                              child: DecoratedBox(
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
                                      color: scheme.primary.withValues(alpha: (0.22 + energy * 0.18) * p),
                                      blurRadius: 24 + energy * 12,
                                      spreadRadius: 2 + energy * 3,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(ctrl.shape == AskResonateShape.semicircle ? 26 : 14),
                              child: _AskResonateContent(
                                contextLabel: ctrl.contextLabel,
                                shape: ctrl.shape,
                                onClose: _close,
                                onShapeChanged: (s) => context.read<AskResonateController>().setShape(s),
                                reduceMotion: reduceMotion,
                              ),
                            ),
                          ],
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
  final AskResonateShape shape;
  final VoidCallback onClose;
  final ValueChanged<AskResonateShape> onShapeChanged;
  final bool reduceMotion;

  const _AskResonateContent({
    required this.contextLabel,
    required this.shape,
    required this.onClose,
    required this.onShapeChanged,
    required this.reduceMotion,
  });

  @override
  State<_AskResonateContent> createState() => _AskResonateContentState();
}

class _AskResonateContentState extends State<_AskResonateContent> {
  String? _result;
  bool _busy = false;

  static const _commands = <(String, String, CompanionIntent)>[
    ('More like this', 'Similar to what is playing', CompanionIntent(action: CompanionAction.similarToCurrent)),
    ('Calmer mix', 'Local mix with a softer lean', CompanionIntent(action: CompanionAction.createMix, mood: 'relaxing')),
    ('More adventurous', 'Raise exploration for this session', CompanionIntent(action: CompanionAction.increaseExploration)),
    ('More familiar', 'Lower exploration', CompanionIntent(action: CompanionAction.decreaseExploration)),
    ('Avoid this artist', 'Downrank the current artist', CompanionIntent(action: CompanionAction.avoidArtist)),
    ('Explain session', 'What the companion sees right now', CompanionIntent(action: CompanionAction.explainSession)),
    ('Evolve mix', 'Refine the current automatic mix', CompanionIntent(action: CompanionAction.evolveMix)),
    ('Play top pick', 'Start the strongest local recommendation', CompanionIntent(action: CompanionAction.playTopRecommendation)),
  ];

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

  Widget _shapeChip(AskResonateShape s, String label, IconData icon) {
    final selected = widget.shape == s;
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      selected: selected,
      label: Text(label),
      avatar: Icon(icon, size: 16),
      onSelected: (_) => widget.onShapeChanged(s),
      selectedColor: scheme.primaryContainer,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final intelligence = context.watch<IntelligenceProvider>();
    final theme = Theme.of(context);


    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ask Resonate',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(widget.contextLabel,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          )),
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
                  : 'Intelligence is off. Enable it in Settings for actions.',
              style: theme.textTheme.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _shapeChip(AskResonateShape.blob, 'Blob', Icons.bubble_chart),
                  const SizedBox(width: 6),
                  _shapeChip(AskResonateShape.capsule, 'Capsule', Icons.smart_button),
                  const SizedBox(width: 6),
                  _shapeChip(AskResonateShape.semicircle, 'Edge', Icons.vertical_split),
                  const SizedBox(width: 6),
                  _shapeChip(AskResonateShape.orbital, 'Orbital', Icons.radio_button_checked),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.55,
                    children: [
                      for (final (title, _, intent) in _commands)
                        Material(
                          color: theme.colorScheme.surface.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: _busy ? null : () => _run(intent),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_busy)
                                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  else
                                    Icon(_iconFor(intent.action), size: 22, color: theme.colorScheme.primary),
                                  const SizedBox(height: 5),
                                  Flexible(
                                    child: Text(
                                      title,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_result != null) ...[
                    const SizedBox(height: 12),
                    Material(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_result!, style: theme.textTheme.bodyMedium),
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
