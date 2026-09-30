#!/usr/bin/env python3
"""Larger Driving transport targets + Bluetooth car context Driving suggestion."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def patch_mode_provider() -> None:
    path = ROOT / "lib/providers/mode_provider.dart"
    t = path.read_text()
    if "attachBluetooth" in t and "hasDrivingSuggestion" in t:
        print("mode: driving suggest already present")
        return

    if "bluetooth_provider.dart" not in t:
        t = t.replace(
            "import 'music_provider.dart';\n",
            "import 'music_provider.dart';\nimport 'bluetooth_provider.dart';\n",
            1,
        )

    if "BluetoothProvider? _bluetooth" not in t:
        t = t.replace(
            "  MusicProvider? _music;\n",
            "  MusicProvider? _music;\n  BluetoothProvider? _bluetooth;\n",
            1,
        )

    # State for suggestion
    if "_drivingSuggestOpen" not in t:
        t = t.replace(
            "  bool _ready = false;\n",
            "  bool _ready = false;\n"
            "  bool _drivingSuggestOpen = false;\n"
            "  bool _drivingSuggestDismissed = false;\n",
            1,
        )

    if "hasDrivingSuggestion" not in t:
        t = t.replace(
            "  bool get isReady => _ready;\n",
            "  bool get isReady => _ready;\n"
            "  /// True when car Bluetooth is active and Driving mode is not selected.\n"
            "  bool get hasDrivingSuggestion =>\n"
            "      _drivingSuggestOpen && _mode != ResonateMode.driving;\n",
            1,
        )

    if "void attachBluetooth" not in t:
        insert = """
  /// Listen for car/vehicle audio context and offer Driving mode (non-blocking).
  void attachBluetooth(BluetoothProvider bluetooth) {
    _bluetooth?.removeListener(_onBluetoothChanged);
    _bluetooth = bluetooth;
    _bluetooth!.addListener(_onBluetoothChanged);
    _onBluetoothChanged();
  }

  void _onBluetoothChanged() {
    final ctx = _bluetooth?.audioContext ?? BluetoothAudioContext.unknown;
    final car = ctx == BluetoothAudioContext.car;

    if (!car) {
      // Reset session dismiss so the next car connection can suggest again.
      final changed = _drivingSuggestOpen || _drivingSuggestDismissed;
      _drivingSuggestOpen = false;
      _drivingSuggestDismissed = false;
      if (changed) notifyListeners();
      return;
    }

    // Already driving — no banner.
    if (_mode == ResonateMode.driving) {
      if (_drivingSuggestOpen) {
        _drivingSuggestOpen = false;
        notifyListeners();
      }
      return;
    }

    if (_drivingSuggestDismissed) return;

    if (!_drivingSuggestOpen) {
      _drivingSuggestOpen = true;
      notifyListeners();
    }
  }

  Future<void> acceptDrivingSuggestion() async {
    _drivingSuggestOpen = false;
    _drivingSuggestDismissed = false;
    await setMode(ResonateMode.driving);
  }

  void dismissDrivingSuggestion() {
    _drivingSuggestOpen = false;
    _drivingSuggestDismissed = true;
    notifyListeners();
  }
"""
        t = t.replace(
            "  void attachMusic(MusicProvider music) {\n"
            "    _music = music;\n"
            "    _pushPolicyToEngine();\n"
            "  }\n",
            "  void attachMusic(MusicProvider music) {\n"
            "    _music = music;\n"
            "    _pushPolicyToEngine();\n"
            "  }\n"
            + insert,
            1,
        )
        print("mode: attachBluetooth + driving suggestion")

    # Clear suggestion when user switches to driving manually
    if "_drivingSuggestOpen = false;" not in t.split("Future<void> setMode")[1][:500]:
        t = t.replace(
            "  Future<void> setMode(ResonateMode mode) async {\n    if (_mode == mode) return;\n    _mode = mode;\n    _pushPolicyToEngine();\n    notifyListeners();\n",
            "  Future<void> setMode(ResonateMode mode) async {\n"
            "    if (_mode == mode) return;\n"
            "    _mode = mode;\n"
            "    if (mode == ResonateMode.driving) {\n"
            "      _drivingSuggestOpen = false;\n"
            "      _drivingSuggestDismissed = false;\n"
            "    }\n"
            "    _pushPolicyToEngine();\n"
            "    notifyListeners();\n",
            1,
        )

    path.write_text(t)
    print("mode provider patched")


def patch_main() -> None:
    path = ROOT / "lib/main.dart"
    t = path.read_text()

    # Ensure BluetoothProvider is registered before ModeProvider
    # and ModeProvider calls attachBluetooth.

    # Remove standalone Bluetooth line if present (we'll re-add early)
    t2 = t.replace(
        "        ChangeNotifierProvider(create: (_) => BluetoothProvider()),\n",
        "",
    )
    if t2 != t:
        t = t2
        print("main: removed late BluetoothProvider")

    # Insert Bluetooth before ModeProvider block
    mode_create = "        ChangeNotifierProvider(\n          create: (context) {\n            final modes = ModeProvider();\n            modes.attachMusic(context.read<MusicProvider>());\n"
    if "modes.attachBluetooth" in t:
        print("main: attachBluetooth already")
    elif mode_create in t:
        # Bluetooth must exist first
        if "BluetoothProvider()" not in t.split("ModeProvider()")[0]:
            t = t.replace(
                mode_create,
                "        ChangeNotifierProvider(create: (_) => BluetoothProvider()),\n"
                + mode_create,
                1,
            )
            print("main: Bluetooth before Mode")
        t = t.replace(
            "            modes.attachMusic(context.read<MusicProvider>());\n"
            "            return modes;\n",
            "            modes.attachMusic(context.read<MusicProvider>());\n"
            "            modes.attachBluetooth(context.read<BluetoothProvider>());\n"
            "            return modes;\n",
            1,
        )
        print("main: attachBluetooth wired")
    else:
        print("main: ModeProvider create pattern miss")

    # Equalizer still needs Bluetooth — if we removed the only Bluetooth and
    # failed to re-add, fix. Count BluetoothProvider creates.
    count = t.count("BluetoothProvider()")
    if count == 0:
        # emergency insert before equalizer
        t = t.replace(
            "        // Bluetooth before Equalizer",
            "        ChangeNotifierProvider(create: (_) => BluetoothProvider()),\n"
            "        // Bluetooth before Equalizer",
            1,
        )
        print("main: emergency Bluetooth restore")
    elif count > 1:
        # keep first only - remove later duplicates carefully
        first = t.find("ChangeNotifierProvider(create: (_) => BluetoothProvider()),")
        second = t.find(
            "ChangeNotifierProvider(create: (_) => BluetoothProvider()),",
            first + 10,
        )
        if second > 0:
            t = (
                t[:second]
                + t[second:].replace(
                    "ChangeNotifierProvider(create: (_) => BluetoothProvider()),\n",
                    "",
                    1,
                )
            )
            print("main: deduped BluetoothProvider")

    path.write_text(t)


def patch_player() -> None:
    path = ROOT / "lib/screens/player_screen.dart"
    t = path.read_text()

    # --- Large transport for Driving (minimal) ---
    old_row = """                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        iconSize: 36,
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed: () {
                          PlaybackAuthority.instance.userPrevious(music);
                        },
                      ),
                      IconButton(
                        iconSize: 30,
                        icon: const Icon(Icons.replay_10_rounded),
                        onPressed: () => PlaybackAuthority.instance.userSeek(
                          music,
                          Duration(milliseconds: math.max(0, currentMs - 10000)),
                        ),
                      ),
                      FilledButton(
                        onPressed: () {
                          music.togglePlayPause();
                        },
                        child: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                      IconButton(
                        iconSize: 30,
                        icon: const Icon(Icons.forward_10_rounded),
                        onPressed: () => PlaybackAuthority.instance.userSeek(
                          music,
                          Duration(milliseconds: math.min(max.toInt(), currentMs + 10000)),
                        ),
                      ),
                      IconButton(
                        iconSize: 36,
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: () {
                          music.nextSong();
                        },
                      ),
                    ],
                  );
"""

    new_row = """                  // Driving (minimal): fewer, larger hit targets — no ±10s seeks.
                  final skipSize = minimal ? 52.0 : (reduced ? 42.0 : 36.0);
                  final playMin = minimal ? 84.0 : (reduced ? 68.0 : 56.0);

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        iconSize: skipSize,
                        style: IconButton.styleFrom(
                          minimumSize: Size(skipSize + 16, skipSize + 16),
                          tapTargetSize: MaterialTapTargetSize.padded,
                        ),
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed: () {
                          PlaybackAuthority.instance.userPrevious(music);
                        },
                      ),
                      if (!minimal)
                        IconButton(
                          iconSize: 30,
                          icon: const Icon(Icons.replay_10_rounded),
                          onPressed: () => PlaybackAuthority.instance.userSeek(
                            music,
                            Duration(milliseconds: math.max(0, currentMs - 10000)),
                          ),
                        ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: Size(playMin, playMin),
                          shape: const CircleBorder(),
                          padding: EdgeInsets.all(minimal ? 20 : 12),
                        ),
                        onPressed: () {
                          music.togglePlayPause();
                        },
                        child: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: minimal ? 40 : 28,
                        ),
                      ),
                      if (!minimal)
                        IconButton(
                          iconSize: 30,
                          icon: const Icon(Icons.forward_10_rounded),
                          onPressed: () => PlaybackAuthority.instance.userSeek(
                            music,
                            Duration(
                              milliseconds: math.min(max.toInt(), currentMs + 10000),
                            ),
                          ),
                        ),
                      IconButton(
                        iconSize: skipSize,
                        style: IconButton.styleFrom(
                          minimumSize: Size(skipSize + 16, skipSize + 16),
                          tapTargetSize: MaterialTapTargetSize.padded,
                        ),
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: () {
                          music.nextSong();
                        },
                      ),
                    ],
                  );
"""

    if "playMin" in t and "minimal ? 52" in t:
        print("player: large transport already")
    elif old_row in t:
        t = t.replace(old_row, new_row, 1)
        print("player: large Driving transport")
    else:
        print("player: transport row miss")

    # --- Driving suggestion banner ---
    if "hasDrivingSuggestion" in t:
        print("player: driving banner already")
    else:
        # Insert after song null check / at top of ListView children
        marker = "          return ListView(\n            padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),\n            children: [\n"
        banner = """          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
            children: [
              if (context.watch<ModeProvider>().hasDrivingSuggestion)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ResonateGlassCard(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                      child: Row(
                        children: [
                          const Text('🚗', style: TextStyle(fontSize: 22)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Car audio detected — switch to Driving mode?',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          TextButton(
                            onPressed: () => context
                                .read<ModeProvider>()
                                .dismissDrivingSuggestion(),
                            child: const Text('Not now'),
                          ),
                          FilledButton(
                            onPressed: () => context
                                .read<ModeProvider>()
                                .acceptDrivingSuggestion(),
                            child: const Text('Driving'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
"""
        if marker in t:
            t = t.replace(marker, banner, 1)
            print("player: driving suggestion banner")
        else:
            print("player: listview marker miss")

    path.write_text(t)


def main() -> None:
    patch_mode_provider()
    patch_main()
    patch_player()
    print("driving ux done")


if __name__ == "__main__":
    main()
