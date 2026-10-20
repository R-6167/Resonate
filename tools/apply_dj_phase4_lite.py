#!/usr/bin/env python3
"""Phase 4 lite: energy/loudness columns, estimator pass-through, analysis service."""
from pathlib import Path

# --- database_helper.dart ---
DB = Path("lib/services/database_helper.dart")
t = DB.read_text()
changed = False

if "columnDjEnergy" not in t:
    t = t.replace(
        "static const String columnDjDurationMs = 'duration_ms';",
        "static const String columnDjDurationMs = 'duration_ms';\n"
        "  static const String columnDjEnergy = 'energy';\n"
        "  static const String columnDjLoudness = 'loudness';",
        1,
    )
    changed = True

if "_databaseVersion = 5" in t:
    t = t.replace("_databaseVersion = 5", "_databaseVersion = 6", 1)
    changed = True

if "columnDjEnergy REAL" not in t and "CREATE TABLE $tableSongDjAnalysis" in t:
    t = t.replace(
        "$columnDjDurationMs INTEGER, FOREIGN KEY ($columnDjSongId)",
        "$columnDjDurationMs INTEGER, $columnDjEnergy REAL, $columnDjLoudness REAL, FOREIGN KEY ($columnDjSongId)",
    )
    changed = True

if "oldVersion < 6" not in t:
    block = """    if (oldVersion < 5) {
      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjAnalysisVersion INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjBpmSource TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjFileSizeBytes INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjDurationMs INTEGER'); } catch (_) {}
    }
"""
    new_block = block + """    if (oldVersion < 6) {
      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjEnergy REAL'); } catch (_) {}
      try { await db.execute('ALTER TABLE $tableSongDjAnalysis ADD COLUMN $columnDjLoudness REAL'); } catch (_) {}
    }
"""
    if block in t:
        t = t.replace(block, new_block, 1)
        changed = True
    else:
        print("WARN: oldVersion < 5 block not found")

# upsert map
if "columnDjEnergy: analysis.energy" not in t:
    old_up = """          columnDjFileSizeBytes: analysis.fileSizeBytes,
          columnDjDurationMs: analysis.durationMs,
        },"""
    new_up = """          columnDjFileSizeBytes: analysis.fileSizeBytes,
          columnDjDurationMs: analysis.durationMs,
          columnDjEnergy: analysis.energy,
          columnDjLoudness: analysis.loudness,
        },"""
    if old_up in t:
        t = t.replace(old_up, new_up, 1)
        changed = True
    else:
        print("WARN: upsert map miss")

if changed:
    DB.write_text(t)
    print("database_helper updated")
else:
    print("database_helper already ok")

# --- dj_analysis_service.dart ---
AS = Path("lib/services/dj_analysis_service.dart")
ta = AS.read_text()
if "energy: estimate.energy" not in ta:
    old_a = """              bpmSource: estimate.source,
              fileSizeBytes: size,
              durationMs: song.duration.inMilliseconds > 0
                  ? song.duration.inMilliseconds
                  : null,
            );"""
    new_a = """              bpmSource: estimate.source,
              fileSizeBytes: size,
              durationMs: song.duration.inMilliseconds > 0
                  ? song.duration.inMilliseconds
                  : null,
              energy: estimate.energy,
              loudness: estimate.loudness,
            );"""
    if old_a in ta:
        AS.write_text(ta.replace(old_a, new_a, 1))
        print("analysis_service wired energy")
    else:
        print("WARN: analysis_service construct miss")
else:
    print("analysis_service already has energy")

print("done")
