#!/usr/bin/env python3
"""Wire ModeProvider into main.dart and Modes entry into settings."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def wire_main() -> None:
    path = ROOT / "lib/main.dart"
    t = path.read_text()
    if "ModeProvider" in t:
        print("main: ModeProvider already wired")
        return

    # Import
    if "providers/mode_provider.dart" not in t:
        # after other provider imports
        anchor = "import 'providers/"
        # find a stable import line
        for candidate in [
            "import 'providers/dj_mode_provider.dart';",
            "import 'providers/music_provider.dart';",
            "import 'providers/theme_provider.dart';",
        ]:
            if candidate in t:
                t = t.replace(
                    candidate,
                    candidate + "\nimport 'providers/mode_provider.dart';",
                    1,
                )
                print("main: added import")
                break

    needle = "        ChangeNotifierProvider(create: (_) => AudioVisualizationProvider()),\n"
    insert = (
        "        ChangeNotifierProvider(create: (_) => ModeProvider()),\n"
        "        ChangeNotifierProvider(create: (_) => AudioVisualizationProvider()),\n"
    )
    if needle in t:
        t = t.replace(needle, insert, 1)
        print("main: ModeProvider registered")
    else:
        # fallback near DjModeProvider
        needle2 = (
            "        ChangeNotifierProvider(\n"
            "          create: (context) =>\n"
            "              DjModeProvider(music: context.read<MusicProvider>()),\n"
            "        ),\n"
        )
        if needle2 in t:
            t = t.replace(
                needle2,
                needle2 + "        ChangeNotifierProvider(create: (_) => ModeProvider()),\n",
                1,
            )
            print("main: ModeProvider registered after DjMode")
        else:
            raise SystemExit("Could not find provider insertion point in main.dart")

    path.write_text(t)


def wire_settings() -> None:
    path = ROOT / "lib/screens/settings_screen.dart"
    t = path.read_text()
    if "ModesScreen" in t:
        print("settings: Modes entry already present")
        return

    if "modes_screen.dart" not in t:
        # add import near other screen imports
        for candidate in [
            "import 'dj_mode_settings_screen.dart';",
            "import 'equalizer_screen.dart';",
            "import 'intelligence_settings_screen.dart';",
        ]:
            if candidate in t:
                t = t.replace(
                    candidate,
                    candidate + "\nimport 'modes_screen.dart';",
                    1,
                )
                print("settings: import ModesScreen")
                break

    # Insert Modes item at top of a sensible section — after Appearance or new section near top of body list
    marker = "_section(context, 'Audio', Icons.equalizer_rounded, ["
    block = (
        "_section(context, 'Modes', Icons.tune_rounded, [\n"
        "              _item(context, 'Listening modes', 'Normal, Running, Driving, Work, Podcast, Motivation, Audiobook', Icons.tune_rounded, const ModesScreen()),\n"
        "            ]),\n"
        "            " + marker
    )
    if marker in t:
        t = t.replace(marker, block, 1)
        print("settings: Modes section added")
    else:
        print("settings: Audio section marker miss — manual check needed")

    path.write_text(t)


def main() -> None:
    wire_main()
    wire_settings()
    print("modes foundation wiring done")


if __name__ == "__main__":
    main()
