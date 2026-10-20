#!/usr/bin/env python3
"""Phase 2: versioned DJ analysis columns + DB v5 migration."""
from pathlib import Path

DB = Path("lib/services/database_helper.dart")
t = DB.read_text()
n = 0

if "columnDjAnalysisVersion" in t and "_databaseVersion = 5" in t:
    print("already phase2")
    raise SystemExit(0)

# version bump
if "static const _databaseVersion = 4;" in t:
    t = t.replace("static const _databaseVersion = 4;", "static const _databaseVersion = 5;", 1)
    n += 1
    print("version 5")

# new column constants after analyzed_at
old_cols = "  static const String columnDjAnalyzedAt = 'analyzed_at';\n"
new_cols = (
    "  static const String columnDjAnalyzedAt = 'analyzed_at';\n"
    "  static const String columnDjAnalysisVersion = 'analysis_version';\n"
    "  static const String columnDjBpmSource = 'bpm_source';\n"
    "  static const String columnDjFileSizeBytes = 'file_size_bytes';\n"
    "  static const String columnDjDurationMs = 'duration_ms';\n"
)
if "columnDjAnalysisVersion" not in t and old_cols in t:
    t = t.replace(old_cols, new_cols, 1)
    n += 1
    print("column consts")

# onCreate CREATE TABLE
old_create = (
    "CREATE TABLE $tableSongDjAnalysis ($columnDjSongId TEXT PRIMARY KEY, "
    "$columnDjBpm REAL, $columnDjBpmConfidence REAL NOT NULL DEFAULT 0, "
    "$columnDjBeatOffsetMs INTEGER, $columnDjKeyRoot INTEGER, $columnDjKeyMode TEXT, "
    "$columnDjAnalyzedAt TEXT, FOREIGN KEY ($columnDjSongId) REFERENCES $tableSongs($columnSongId))"
)
new_create = (
    "CREATE TABLE $tableSongDjAnalysis ($columnDjSongId TEXT PRIMARY KEY, "
    "$columnDjBpm REAL, $columnDjBpmConfidence REAL NOT NULL DEFAULT 0, "
    "$columnDjBeatOffsetMs INTEGER, $columnDjKeyRoot INTEGER, $columnDjKeyMode TEXT, "
    "$columnDjAnalyzedAt TEXT, $columnDjAnalysisVersion INTEGER NOT NULL DEFAULT 0, "
    "$columnDjBpmSource TEXT, $columnDjFileSizeBytes INTEGER, $columnDjDurationMs INTEGER, "
    "FOREIGN KEY ($columnDjSongId) REFERENCES $tableSongs($columnSongId))"
)
if old_create in t:
    t = t.replace(old_create, new_create)
    n += 1
    print("create table schema")

# onUpgrade v5 migration
idx = t.find("if (oldVersion < 4)")
if idx > 0 and "oldVersion < 5" not in t:
    rest = t[idx:]
    end_marker = "\n  Future<int> insertListeningEvent"
    ei = rest.find(end_marker)
    if ei > 0:
        block = rest[:ei]
        last = block.rfind("\n  }")
        if last >= 0:
            migration = (
                "\n    if (oldVersion < 5) {\n"
                "      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjAnalysisVersion INTEGER NOT NULL DEFAULT 0'); } catch (_) {}\n"
                "      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjBpmSource TEXT'); } catch (_) {}\n"
                "      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjFileSizeBytes INTEGER'); } catch (_) {}\n"
                "      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjDurationMs INTEGER'); } catch (_) {}\n"
                "    }"
            )
            new_block = block[:last] + migration + block[last:]
            t = t[:idx] + new_block + rest[ei:]
            n += 1
            print("upgrade v5")
        else:
            print("MISS upgrade insert point")
    else:
        print("MISS insertListeningEvent")
elif "oldVersion < 5" in t:
    print("upgrade already")
else:
    print("MISS oldVersion < 4")

# upsert map
old_upsert = """          columnDjSongId: analysis.songId,
          columnDjBpm: analysis.bpm,
          columnDjBpmConfidence: analysis.bpmConfidence,
          columnDjBeatOffsetMs: analysis.beatOffsetMs,
          columnDjKeyRoot: analysis.keyRoot,
          columnDjKeyMode: analysis.keyMode,
          columnDjAnalyzedAt: analysis.analyzedAt?.toIso8601String(),
"""
new_upsert = """          columnDjSongId: analysis.songId,
          columnDjBpm: analysis.bpm,
          columnDjBpmConfidence: analysis.bpmConfidence,
          columnDjBeatOffsetMs: analysis.beatOffsetMs,
          columnDjKeyRoot: analysis.keyRoot,
          columnDjKeyMode: analysis.keyMode,
          columnDjAnalyzedAt: analysis.analyzedAt?.toIso8601String(),
          columnDjAnalysisVersion: analysis.analysisVersion,
          columnDjBpmSource: analysis.bpmSource,
          columnDjFileSizeBytes: analysis.fileSizeBytes,
          columnDjDurationMs: analysis.durationMs,
"""
if "columnDjAnalysisVersion: analysis.analysisVersion" not in t and old_upsert in t:
    t = t.replace(old_upsert, new_upsert, 1)
    n += 1
    print("upsert fields")
else:
    if "columnDjAnalysisVersion: analysis.analysisVersion" in t:
        print("upsert already")
    else:
        print("MISS upsert")

DB.write_text(t)
print("patches", n)
