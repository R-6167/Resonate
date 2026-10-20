#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
main = ROOT / "lib/main.dart"
m = main.read_text()

already = "modes.attachPlayback" in m or "ResonateModePlaybackPort" in m
if not already:
    if "import 'modes/providers/mode_provider.dart';" not in m:
        m = m.replace(
            "import 'providers/music_provider.dart';\n",
            "import 'providers/music_provider.dart';\n"
            "import 'modes/providers/mode_provider.dart';\n"
            "import 'modes/integration/resonate_mode_ports.dart';\n",
            1,
        )
    old = """        ChangeNotifierProvider(
          create: (context) =>
              DjModeProvider(music: context.read<MusicProvider>()),
        ),
"""
    new = """        ChangeNotifierProvider(
          create: (context) =>
              DjModeProvider(music: context.read<MusicProvider>()),
        ),
        // Modes: policy only. Ports never force play or reclaim focus.
        ChangeNotifierProvider(
          create: (context) {
            final modes = ModeProvider();
            modes.attachPlayback(
              ResonateModePlaybackPort(context.read<MusicProvider>()),
            );
            modes.attachContext(
              ResonateModeContextPort(context.read<BluetoothProvider>()),
            );
            return modes;
          },
        ),
"""
    if old not in m:
        raise SystemExit("DjModeProvider block miss")
    m = m.replace(old, new, 1)
    main.write_text(m)
    print("main ModeProvider registered")
else:
    print("main already has ResonateModePlaybackPort")
