from pathlib import Path

home = Path('lib/screens/home_screen.dart')
s = home.read_text(encoding='utf-8')

hero_word_art = """          Positioned(
            right: -8,
            bottom: 4,
            child: IgnorePointer(
              child: Opacity(
                opacity: .11,
                child: Text(
                  'RESONATE',
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
              ),
            ),
          ),
"""
s = s.replace(hero_word_art, '')
spinner = """                SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary))),
                const SizedBox(width: 12),
"""
if spinner in s:
    s = s.replace(spinner, """                const SizedBox(width: 30, height: 22, child: _LearningWaveDots()),
                const SizedBox(width: 10),
""", 1)
    widget = '''
class _LearningWaveDots extends StatefulWidget {
  const _LearningWaveDots();
  @override
  State<_LearningWaveDots> createState() => _LearningWaveDotsState();
}

class _LearningWaveDotsState extends State<_LearningWaveDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(3, (index) {
          final phase = (_controller.value + index * .18) % 1.0;
          final wave = math.sin(phase * math.pi * 2);
          return Transform.translate(
            offset: Offset(0, -wave * 3.2),
            child: Transform.scale(
              scale: .72 + ((wave + 1) * .14),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
'''
    marker = '\nclass _AnticipationCard extends StatefulWidget {'
    if '_LearningWaveDots' not in s:
        s = s.replace(marker, '\n' + widget + marker, 1)
    if "import 'dart:math' as math;" not in s:
        s = s.replace("import 'package:flutter/material.dart';", "import 'dart:math' as math;\n\nimport 'package:flutter/material.dart';", 1)
home.write_text(s, encoding='utf-8')

player = Path('lib/screens/player_screen.dart')
s = player.read_text(encoding='utf-8').replace("import 'dart:ui' as ui;\n", '')
art = """              Container(
                height: 250,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: const Icon(Icons.album_rounded, size: 110),
              ),
"""
replacement = """              ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: SizedBox(
                  height: 250,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                        child: const AudioVisualizationWidget(),
                      ),
                      Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.surface.withOpacity(.82),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(28),
                            child: Icon(Icons.album_rounded, size: 86),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
"""
s = s.replace(art, replacement, 1)
s = s.replace("""              const SizedBox(height: 10),
              const SizedBox(
                height: 100,
                child: AudioVisualizationWidget(),
              ),
              _WaveSeekBar(
""", """              const SizedBox(height: 8),
              _WaveSeekBar(
""", 1)
s = s.replace("""              const SizedBox(height: 14),
              const AutopilotTakeoverCard(),
              const SizedBox(height: 10),
              Consumer<IntelligenceProvider>(
""", """              const SizedBox(height: 14),
              Consumer<IntelligenceProvider>(
""", 1)
s = s.replace("""                  return _NextCard(item: item, mode: intelligence.autonomyLabel);
                },
              ),
""", """                  return Column(
                    children: [
                      _NextCard(item: item, mode: intelligence.autonomyLabel),
                      const SizedBox(height: 10),
                      const AutopilotTakeoverCard(),
                    ],
                  );
                },
              ),
""", 1)
player.write_text(s, encoding='utf-8')

card = Path('lib/widgets/autopilot_takeover_card.dart')
s = card.read_text(encoding='utf-8')
prompt = """          if (pendingSong != null)
            Card(color: scheme.primaryContainer, child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 8, 10), child: Row(children: [
"""
prompt_replacement = """          if (pendingSong != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                elevation: 7,
                shadowColor: scheme.shadow.withOpacity(.28),
                borderRadius: BorderRadius.circular(20),
                color: scheme.primaryContainer,
                child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 8, 10), child: Row(children: [
"""
s = s.replace(prompt, prompt_replacement, 1)
s = s.replace("""              FilledButton(onPressed: controller.allowPendingTakeover, child: const Text('Let it choose')),
            ]))),
          Card(child: Padding(
""", """              FilledButton(onPressed: controller.allowPendingTakeover, child: const Text('Let it choose')),
            ])),
              ),
            ),
          Card(child: Padding(
""", 1)
card.write_text(s, encoding='utf-8')
