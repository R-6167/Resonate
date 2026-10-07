#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

# ---------- player_screen.dart ----------
p = ROOT / "lib/screens/player_screen.dart"
t = p.read_text()

if "mode_guarded_action.dart" not in t:
    t = t.replace(
        "import '../widgets/mode_player_density.dart';\n",
        "import '../widgets/mode_player_density.dart';\n"
        "import '../widgets/mode_guarded_action.dart';\n"
        "import '../modes/models/mode_action.dart';\n",
        1,
    )

# WaveSeekBar call — add density params
old_seek = """              _WaveSeekBar(
                value: position,
                max: max,
"""
# flexible
if "_WaveSeekBar(" in t and "hitHeight:" not in t:
    t = t.replace(
        "_WaveSeekBar(\n                value: position,\n                max: max,",
        "_WaveSeekBar(\n                value: position,\n                max: max,\n                hitHeight: density.seekHitHeight,\n                strokeScale: density.seekStrokeScale,",
        1,
    )
    print("seek params")

# Update _WaveSeekBar class
old_class = """class _WaveSeekBar extends StatefulWidget {
  final double value; final double max; final ValueChanged<double> onStart; final ValueChanged<double> onUpdate; final ValueChanged<double> onEnd;
  const _WaveSeekBar({required this.value, required this.max, required this.onStart, required this.onUpdate, required this.onEnd});
  @override State<_WaveSeekBar> createState() => _WaveSeekBarState();
}
class _WaveSeekBarState extends State<_WaveSeekBar> {
  double? _interactionValue;
  double _valueFor(Offset local, double width) => width <= 0 ? 0 : (local.dx / width).clamp(0.0,1.0) * widget.max;
  @override Widget build(BuildContext context) => LayoutBuilder(builder:(context,constraints){ final display=_interactionValue ?? widget.value; return GestureDetector(behavior:HitTestBehavior.opaque, onHorizontalDragStart:(d){final v=_valueFor(d.localPosition,constraints.maxWidth);setState(()=>_interactionValue=v);widget.onStart(v);}, onHorizontalDragUpdate:(d){final v=_valueFor(d.localPosition,constraints.maxWidth);setState(()=>_interactionValue=v);widget.onUpdate(v);}, onHorizontalDragEnd:(_){final v=_interactionValue ?? widget.value;setState(()=>_interactionValue=null);widget.onEnd(v);}, onTapDown:(d){final v=_valueFor(d.localPosition,constraints.maxWidth);setState(()=>_interactionValue=v);widget.onStart(v);}, onTapUp:(d){final v=_valueFor(d.localPosition,constraints.maxWidth);setState(()=>_interactionValue=null);widget.onEnd(v);}, child:SizedBox(height:64,child:CustomPaint(painter:_WaveSeekPainter(progress:widget.max<=0?0:display/widget.max,color:Theme.of(context).colorScheme.primary,muted:Theme.of(context).colorScheme.outlineVariant)))); });
}
"""

new_class = """class _WaveSeekBar extends StatefulWidget {
  final double value;
  final double max;
  final ValueChanged<double> onStart;
  final ValueChanged<double> onUpdate;
  final ValueChanged<double> onEnd;
  final double hitHeight;
  final double strokeScale;
  const _WaveSeekBar({
    required this.value,
    required this.max,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    this.hitHeight = 64,
    this.strokeScale = 1.0,
  });
  @override
  State<_WaveSeekBar> createState() => _WaveSeekBarState();
}

class _WaveSeekBarState extends State<_WaveSeekBar> {
  double? _interactionValue;
  double _valueFor(Offset local, double width) =>
      width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0) * widget.max;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final display = _interactionValue ?? widget.value;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) {
            final v = _valueFor(d.localPosition, constraints.maxWidth);
            setState(() => _interactionValue = v);
            widget.onStart(v);
          },
          onHorizontalDragUpdate: (d) {
            final v = _valueFor(d.localPosition, constraints.maxWidth);
            setState(() => _interactionValue = v);
            widget.onUpdate(v);
          },
          onHorizontalDragEnd: (_) {
            final v = _interactionValue ?? widget.value;
            setState(() => _interactionValue = null);
            widget.onEnd(v);
          },
          onTapDown: (d) {
            final v = _valueFor(d.localPosition, constraints.maxWidth);
            setState(() => _interactionValue = v);
            widget.onStart(v);
          },
          onTapUp: (d) {
            final v = _valueFor(d.localPosition, constraints.maxWidth);
            setState(() => _interactionValue = null);
            widget.onEnd(v);
          },
          child: SizedBox(
            height: widget.hitHeight,
            child: CustomPaint(
              painter: _WaveSeekPainter(
                progress: widget.max <= 0 ? 0 : display / widget.max,
                color: Theme.of(context).colorScheme.primary,
                muted: Theme.of(context).colorScheme.outlineVariant,
                strokeScale: widget.strokeScale,
              ),
            ),
          ),
        );
      },
    );
  }
}
"""

if old_class in t:
    t = t.replace(old_class, new_class, 1)
    print("WaveSeekBar class updated")
elif "strokeScale" in t and "class _WaveSeekBar" in t:
    print("WaveSeekBar already expanded")
else:
    # try partial - if class still one-liner
    if "child:SizedBox(height:64,child:CustomPaint(painter:_WaveSeekPainter" in t:
        t = t.replace(old_class.strip(), new_class.strip(), 1) if old_class.strip() in t else t
        if "hitHeight = 64" not in t:
            print("WARN WaveSeekBar replace failed — writing forced block")
            # Find class _WaveSeekBar and replace until class _WaveSeekPainter
            start = t.find("class _WaveSeekBar extends")
            end = t.find("class _WaveSeekPainter")
            if start >= 0 and end > start:
                t = t[:start] + new_class + "\n" + t[end:]
                print("WaveSeekBar force replaced")
            else:
                raise SystemExit("WaveSeekBar bounds miss")
    else:
        print("WARN WaveSeekBar pattern")

# Painter: add strokeScale
if "strokeScale" not in t[t.find("class _WaveSeekPainter"):t.find("class _WaveSeekPainter")+400]:
    old_p = """class _WaveSeekPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color muted;

  _WaveSeekPainter({
    required this.progress,
    required this.color,
    required this.muted,
  });
"""
    new_p = """class _WaveSeekPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color muted;
  final double strokeScale;

  _WaveSeekPainter({
    required this.progress,
    required this.color,
    required this.muted,
    this.strokeScale = 1.0,
  });
"""
    if old_p in t:
        t = t.replace(old_p, new_p, 1)
        t = t.replace(
            "..strokeWidth = math.max(2, step * 0.46);",
            "..strokeWidth = math.max(2, step * 0.46) * strokeScale;",
            1,
        )
        t = t.replace(
            "..strokeWidth = math.max(2, step * 0.42);",
            "..strokeWidth = math.max(2, step * 0.42) * strokeScale;",
            1,
        )
        print("painter strokeScale")
    else:
        print("WARN painter")

# Wrap transport buttons with ModeGuardedAction
# Previous
old_prev = """                      IconButton(
                        iconSize: density.transportIconSize,
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed: () {
                          PlaybackAuthority.instance.userPrevious(music);
                        },
                      ),
"""
new_prev = """                      ModeGuardedAction(
                        action: ModeAction.previous,
                        onAllowed: () {
                          PlaybackAuthority.instance.userPrevious(music);
                        },
                        child: IconButton(
                          iconSize: density.transportIconSize,
                          icon: const Icon(Icons.skip_previous_rounded),
                          onPressed: null,
                        ),
                      ),
"""
# IconButton with onPressed null still looks disabled - better wrap and use onPressed that calls guarded path
# Better pattern: ModeGuardedAction child is IconButton with onPressed: () => guarded via wrapping that intercepts

new_prev = """                      ModeGuardedAction(
                        action: ModeAction.previous,
                        onAllowed: () =>
                            PlaybackAuthority.instance.userPrevious(music),
                        child: SizedBox(
                          width: density.transportIconSize + 24,
                          height: density.transportIconSize + 24,
                          child: Icon(
                            Icons.skip_previous_rounded,
                            size: density.transportIconSize,
                          ),
                        ),
                      ),
"""

if "ModeGuardedAction" not in t or "ModeAction.previous" not in t:
    # Replace whole transport row children with guarded versions
    # Find the return Row for transport
    start = t.find("return Row(\n                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,")
    if start < 0:
        raise SystemExit("transport row miss")
    # Find end of this row
    end = t.find("                    ],\n                  );", start)
    if end < 0:
        raise SystemExit("transport row end miss")
    end = t.find("\n", end)  # keep structure
    # Actually replace from children: [ to ],
    cstart = t.find("children: [", start)
    cend = t.find("                    ],\n                  );", cstart)
    if cstart < 0 or cend < 0:
        raise SystemExit("children miss")
    new_children = """children: [
                      ModeGuardedAction(
                        action: ModeAction.previous,
                        onAllowed: () =>
                            PlaybackAuthority.instance.userPrevious(music),
                        child: SizedBox(
                          width: density.transportIconSize + 28,
                          height: density.transportIconSize + 28,
                          child: Icon(
                            Icons.skip_previous_rounded,
                            size: density.transportIconSize,
                          ),
                        ),
                      ),
                      ModeGuardedAction(
                        action: ModeAction.seekBackward,
                        onAllowed: () => PlaybackAuthority.instance.userSeek(
                          music,
                          Duration(
                            milliseconds: math.max(0, currentMs - 10000),
                          ),
                        ),
                        child: SizedBox(
                          width: density.transportIconSize + 20,
                          height: density.transportIconSize + 20,
                          child: Icon(
                            Icons.replay_10_rounded,
                            size: density.largeControls
                                ? density.transportIconSize - 6
                                : 30,
                          ),
                        ),
                      ),
                      ModeGuardedAction(
                        action: ModeAction.playPause,
                        onAllowed: () {
                          music.togglePlayPause();
                        },
                        child: SizedBox(
                          width: density.playButtonSize,
                          height: density.playButtonSize,
                          child: FilledButton(
                            onPressed: null,
                            style: FilledButton.styleFrom(
                              minimumSize: Size(
                                density.playButtonSize,
                                density.playButtonSize,
                              ),
                              maximumSize: Size(
                                density.playButtonSize,
                                density.playButtonSize,
                              ),
                              padding: EdgeInsets.zero,
                              shape: const CircleBorder(),
                              disabledBackgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primary,
                              disabledForegroundColor: Theme.of(context)
                                  .colorScheme
                                  .onPrimary,
                            ),
                            child: Icon(
                              playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: density.playIconSize,
                            ),
                          ),
                        ),
                      ),
                      ModeGuardedAction(
                        action: ModeAction.seekForward,
                        onAllowed: () => PlaybackAuthority.instance.userSeek(
                          music,
                          Duration(
                            milliseconds:
                                math.min(max.toInt(), currentMs + 10000),
                          ),
                        ),
                        child: SizedBox(
                          width: density.transportIconSize + 20,
                          height: density.transportIconSize + 20,
                          child: Icon(
                            Icons.forward_10_rounded,
                            size: density.largeControls
                                ? density.transportIconSize - 6
                                : 30,
                          ),
                        ),
                      ),
                      ModeGuardedAction(
                        action: ModeAction.next,
                        onAllowed: () => music.nextSong(),
                        child: SizedBox(
                          width: density.transportIconSize + 28,
                          height: density.transportIconSize + 28,
                          child: Icon(
                            Icons.skip_next_rounded,
                            size: density.transportIconSize,
                          ),
                        ),
                      ),
                    """
    t = t[:cstart] + new_children + t[cend:]
    print("transport guarded")
else:
    print("transport already guarded")

# Running hint under transport when two-finger required
if "requiresTwoFingerPlayback" not in t:
    marker = "              const SizedBox(height: 8),\n              if (density.showSecondaryRow)"
    if marker in t:
        t = t.replace(
            marker,
            "              if (density.requiresTwoFingerPlayback)\n"
            "                Padding(\n"
            "                  padding: const EdgeInsets.only(bottom: 6),\n"
            "                  child: Text(\n"
            "                    'Two-finger taps for play / skip / seek',\n"
            "                    textAlign: TextAlign.center,\n"
            "                    style: Theme.of(context).textTheme.labelSmall?.copyWith(\n"
            "                      color: Theme.of(context).colorScheme.tertiary,\n"
            "                    ),\n"
            "                  ),\n"
            "                ),\n"
            "              const SizedBox(height: 8),\n"
            "              if (density.showSecondaryRow)",
            1,
        )
        print("two-finger hint")

p.write_text(t)
print("player done")

# ---------- home_screen.dart ----------
h = ROOT / "lib/screens/home_screen.dart"
ht = h.read_text()

if "mode_player_density.dart" not in ht:
    ht = ht.replace(
        "import '../widgets/resonate_mode_chip.dart';\n",
        "import '../widgets/resonate_mode_chip.dart';\n"
        "import '../widgets/mode_player_density.dart';\n"
        "import '../modes/providers/mode_provider.dart';\n",
        1,
    )

if "ModePlayerDensity.fromMode" not in ht:
    # _HomeDashboard build watches library/music/intelligence - add modes
    old = "    final library = context.watch<LibraryProvider>();\n    final music = context.watch<MusicProvider>();\n    final intelligence = context.watch<IntelligenceProvider>();\n"
    new = "    final library = context.watch<LibraryProvider>();\n    final music = context.watch<MusicProvider>();\n    final intelligence = context.watch<IntelligenceProvider>();\n    final modes = context.watch<ModeProvider>();\n    final density = ModePlayerDensity.fromMode(modes);\n"
    if old not in ht:
        raise SystemExit("home watch miss")
    ht = ht.replace(old, new, 1)

    # Now playing FilledButton.tonalIcon enlarge
    old_btn = "trailing: FilledButton.tonalIcon(onPressed: () => PlaybackAuthority.instance.userToggle(music), icon: Icon(music.isPlaying ? Icons.pause : Icons.play_arrow), label: Text(music.isPlaying ? 'Pause' : 'Play')),"
    new_btn = """trailing: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: Size(density.homePlayMinWidth, density.homePlayMinHeight),
              padding: EdgeInsets.symmetric(
                horizontal: density.largeControls ? 18 : 12,
                vertical: density.largeControls ? 12 : 8,
              ),
            ),
            onPressed: () => PlaybackAuthority.instance.userToggle(music),
            icon: Icon(
              music.isPlaying ? Icons.pause : Icons.play_arrow,
              size: density.largeControls ? 28 : 22,
            ),
            label: Text(music.isPlaying ? 'Pause' : 'Play'),
          ),"""
    if old_btn in ht:
        ht = ht.replace(old_btn, new_btn, 1)
        print("home play density")
    else:
        print("WARN home play btn")

    # Resume button similar if present
    if "music.continueListening()" in ht and "homePlayMinWidth" not in ht[ht.find("continueListening"):ht.find("continueListening")+200]:
        pass  # optional

    h.write_text(ht)
    print("home density")
else:
    print("home already density")

doc = ROOT / "docs/MODES.md"
if doc.exists():
    d = doc.read_text()
    d = d.replace(
        "- [ ] **`ModeInteractionGuard` in real UI**",
        "- [x] **`ModeInteractionGuard` in real UI** (Running two-finger transport)",
        1,
    )
    doc.write_text(d)

print("all done")
