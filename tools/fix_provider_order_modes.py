#!/usr/bin/env python3
from pathlib import Path

main = Path(__file__).resolve().parents[1] / "lib/main.dart"
m = main.read_text()

old = """        ChangeNotifierProvider(
          create: (context) =>
              PlaybackDiagnosticsObserver(music: context.read<MusicProvider>()),
        ),
        ChangeNotifierProvider(
          create: (context) => AutopilotController(
            music: context.read<MusicProvider>(),
            intelligence: context.read<IntelligenceProvider>(),
            modes: context.read<ModeProvider>(),
          ),
        ),
        // Bluetooth before Equalizer so EQ can bind device profiles.
        ChangeNotifierProvider(create: (_) => BluetoothProvider()),
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

new = """        ChangeNotifierProvider(
          create: (context) =>
              PlaybackDiagnosticsObserver(music: context.read<MusicProvider>()),
        ),
        // Bluetooth before Modes + Equalizer (car context + EQ profiles).
        ChangeNotifierProvider(create: (_) => BluetoothProvider()),
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
        ChangeNotifierProvider(
          create: (context) => AutopilotController(
            music: context.read<MusicProvider>(),
            intelligence: context.read<IntelligenceProvider>(),
            modes: context.read<ModeProvider>(),
          ),
        ),
"""

if old not in m:
    if "modes: context.read<ModeProvider>()" in m and m.find("BluetoothProvider") < m.find("AutopilotController"):
        print("order already fixed")
    else:
        raise SystemExit("provider block pattern miss")
else:
    m = m.replace(old, new, 1)
    main.write_text(m)
    print("provider order fixed")
