#!/usr/bin/env python3
"""Apply DJ Mode Step 1 wiring to main, settings, and database_helper."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

def patch_main(text: str) -> str:
    if "DjModeProvider" in text:
        return text
    if "import 'providers/dj_mode_provider.dart';" not in text:
        if "import 'providers/crossfade_provider.dart';" in text:
            text = text.replace(
                "import 'providers/crossfade_provider.dart';",
                "import 'providers/crossfade_provider.dart';\nimport 'providers/dj_mode_provider.dart';",
            )
        else:
            text = text.replace(
                "import 'providers/music_provider.dart';",
                "import 'providers/music_provider.dart';\nimport 'providers/dj_mode_provider.dart';",
            )
    needle = (
        "        ChangeNotifierProvider(\n"
        "          create: (context) =>\n"
        "              CrossfadeProvider(music: context.read<MusicProvider>()),\n"
        "        ),"
    )
    insert = needle + (
        "\n        ChangeNotifierProvider(\n"
        "          create: (context) =>\n"
        "              DjModeProvider(music: context.read<MusicProvider>()),\n"
        "        ),"
    )
    if needle not in text:
        raise SystemExit("main: CrossfadeProvider block not found")
    return text.replace(needle, insert, 1)

def patch_settings(text: str) -> str:
    if "DjModeSettingsScreen" in text:
        return text
    if "import 'dj_mode_settings_screen.dart';" not in text:
        text = text.replace(
            "import 'crossfade_screen.dart';",
            "import 'crossfade_screen.dart';\nimport 'dj_mode_settings_screen.dart';",
        )
    needle = (
        "              _item(context, 'Crossfade', 'Transition duration and curve', "
        "Icons.compare_arrows_rounded, const CrossfadeScreen()),"
    )
    insert = needle + (
        "\n              _item(context, 'DJ Mode', 'Optional beat, tempo and harmonic blending', "
        "Icons.headphones_rounded, const DjModeSettingsScreen()),"
    )
    if needle not in text:
        raise SystemExit("settings: Crossfade item not found")
    return text.replace(needle, insert, 1)

def patch_database(text: str) -> str:
    if "tableSongDjAnalysis" in text and "oldVersion < 4" in text and "getDjAnalysis" in text:
        return text
    if "import '../models/dj_analysis.dart';" not in text:
        text = text.replace(
            "import '../models/listening_event.dart';",
            "import '../models/listening_event.dart';\nimport '../models/dj_analysis.dart';",
        )
    text = text.replace(
        "static const _databaseVersion = 3;",
        "static const _databaseVersion = 4;",
    )
    if "tableSongDjAnalysis" not in text:
        text = text.replace(
            "  static const String tableListeningEvents = 'listening_events';",
            "  static const String tableListeningEvents = 'listening_events';\n"
            "  static const String tableSongDjAnalysis = 'song_dj_analysis';\n"
            "  static const String columnDjSongId = 'song_id';\n"
            "  static const String columnDjBpm = 'bpm';\n"
            "  static const String columnDjBpmConfidence = 'bpm_confidence';\n"
            "  static const String columnDjBeatOffsetMs = 'beat_offset_ms';\n"
            "  static const String columnDjKeyRoot = 'key_root';\n"
            "  static const String columnDjKeyMode = 'key_mode';\n"
            "  static const String columnDjAnalyzedAt = 'analyzed_at';",
        )
    create_line = "FOREIGN KEY ($columnEventSongId) REFERENCES $tableSongs($columnSongId))');"
    create_extra = (
        "\n    await db.execute('CREATE TABLE $tableSongDjAnalysis ($columnDjSongId TEXT PRIMARY KEY, "
        "$columnDjBpm REAL, $columnDjBpmConfidence REAL NOT NULL DEFAULT 0, $columnDjBeatOffsetMs INTEGER, "
        "$columnDjKeyRoot INTEGER, $columnDjKeyMode TEXT, $columnDjAnalyzedAt TEXT, "
        "FOREIGN KEY ($columnDjSongId) REFERENCES $tableSongs($columnSongId))');"
    )
    on_create = text.find("Future<void> _onCreate")
    if on_create >= 0 and "CREATE TABLE $tableSongDjAnalysis" not in text[on_create : on_create + 4500]:
        pos = text.find(create_line, on_create)
        if pos < 0:
            raise SystemExit("db: onCreate listening events line not found")
        text = text[: pos + len(create_line)] + create_extra + text[pos + len(create_line) :]

    if "oldVersion < 4" not in text:
        anchor = "      await db.execute('CREATE INDEX idx_favorites_date_added ON $tableFavorites($columnFavoriteDateAdded)');\n    }"
        upgrade4 = (
            "      await db.execute('CREATE INDEX idx_favorites_date_added ON $tableFavorites($columnFavoriteDateAdded)');\n"
            "    }\n"
            "    if (oldVersion < 4) {\n"
            "      await db.execute('CREATE TABLE IF NOT EXISTS $tableSongDjAnalysis ($columnDjSongId TEXT PRIMARY KEY, "
            "$columnDjBpm REAL, $columnDjBpmConfidence REAL NOT NULL DEFAULT 0, $columnDjBeatOffsetMs INTEGER, "
            "$columnDjKeyRoot INTEGER, $columnDjKeyMode TEXT, $columnDjAnalyzedAt TEXT, "
            "FOREIGN KEY ($columnDjSongId) REFERENCES $tableSongs($columnSongId))');\n"
            "    }"
        )
        if anchor not in text:
            raise SystemExit("db: upgrade anchor not found")
        text = text.replace(anchor, upgrade4, 1)

    if "getDjAnalysis" not in text:
        methods = """
  Future<DjAnalysis?> getDjAnalysis(String songId) async {
    try {
      final rows = await (await database).query(
        tableSongDjAnalysis,
        where: '$columnDjSongId = ?',
        whereArgs: [songId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return DjAnalysis.fromMap(rows.first);
    } catch (e) {
      _markDatabaseFailure('database_operation', e);
      return null;
    }
  }

  Future<void> upsertDjAnalysis(DjAnalysis analysis) async {
    try {
      await (await database).insert(
        tableSongDjAnalysis,
        {
          columnDjSongId: analysis.songId,
          columnDjBpm: analysis.bpm,
          columnDjBpmConfidence: analysis.bpmConfidence,
          columnDjBeatOffsetMs: analysis.beatOffsetMs,
          columnDjKeyRoot: analysis.keyRoot,
          columnDjKeyMode: analysis.keyMode,
          columnDjAnalyzedAt: analysis.analyzedAt?.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      _markDatabaseFailure('database_operation', e);
      print('Error upserting dj analysis: $e');
    }
  }

  Future<void> deleteDjAnalysis(String songId) async {
    try {
      await (await database).delete(
        tableSongDjAnalysis,
        where: '$columnDjSongId = ?',
        whereArgs: [songId],
      );
    } catch (e) {
      _markDatabaseFailure('database_operation', e);
    }
  }
"""
        last = text.rfind("}")
        text = text[:last] + methods + "\n" + text[last:]
    return text

def main() -> int:
    main_p = ROOT / "lib/main.dart"
    settings_p = ROOT / "lib/screens/settings_screen.dart"
    db_p = ROOT / "lib/services/database_helper.dart"
    main_p.write_text(patch_main(main_p.read_text()))
    print("main ok")
    settings_p.write_text(patch_settings(settings_p.read_text()))
    print("settings ok")
    db_p.write_text(patch_database(db_p.read_text()))
    print("database ok")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
