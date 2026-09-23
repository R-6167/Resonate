#!/usr/bin/env python3
"""Restore MainActivity scan: filePath/duration keys + unrestricted filter."""
from pathlib import Path
import subprocess

# Recover MainActivity from last good SHA before PLACEHOLDER overwrite
sha = "2f89fc12e92d92ca31814684526b3800d341825f"
path = Path("android/app/src/main/kotlin/com/Aetherion/Resonate/MainActivity.kt")
data = subprocess.check_output(["git", "show", f"{sha}:{path.as_posix()}"])
path.write_bytes(data)
text = path.read_text()

text = text.replace(
    "if (!isInSelectedFolder(relativePath, dataPath, prefixes)) continue",
    "if (folders.isNotEmpty() && !isInSelectedFolder(relativePath, dataPath, prefixes)) continue",
)

old_map = (
    '                    mapOf(\n'
    '                        "id" to id.toString(),\n'
    '                        "title" to (cursor.getString(titleCol) ?: "Unknown"),\n'
    '                        "artist" to (cursor.getString(artistCol) ?: "Unknown"),\n'
    '                        "album" to (cursor.getString(albumCol) ?: "Unknown"),\n'
    '                        "durationMs" to cursor.getLong(durationCol),\n'
    '                        "dateAdded" to cursor.getLong(dateCol),\n'
    '                        "size" to size,\n'
    '                        "uri" to contentUri,\n'
    '                        "path" to (dataPath ?: contentUri),\n'
    '                    )'
)
new_map = (
    '                    mapOf(\n'
    '                        "filePath" to contentUri,\n'
    '                        "title" to (cursor.getString(titleCol) ?: "Unknown Title"),\n'
    '                        "artist" to (cursor.getString(artistCol) ?: "Unknown Artist"),\n'
    '                        "album" to (cursor.getString(albumCol) ?: "Unknown Album"),\n'
    '                        "duration" to cursor.getLong(durationCol),\n'
    '                        "dateAdded" to cursor.getLong(dateCol),\n'
    '                        "size" to size,\n'
    '                    )'
)
if old_map not in text:
    idx = text.find("songs.add")
    raise SystemExit(f"old_map not found near: {text[idx:idx+500]!r}")
text = text.replace(old_map, new_map, 1)

if "override fun onDestroy()" not in text:
    if text.rstrip().endswith("}"):
        text = text.rstrip()[:-1] + (
            "\n    override fun onDestroy() {\n"
            "        releaseEffects()\n"
            "        super.onDestroy()\n"
            "    }\n"
            "}\n"
        )

path.write_text(text)
assert "filePath" in text
assert "folders.isNotEmpty()" in text
assert "PLACEHOLDER" not in text
print("MainActivity fixed OK", len(text))

# Dart resilience
p = Path("lib/services/audio_file_service.dart")
t = p.read_text()
if "map['uri']" not in t:
    t = t.replace(
        "(map['filePath'] ?? '').toString()",
        "(map['filePath'] ?? map['uri'] ?? map['path'] ?? '').toString()",
    )
    if "map['durationMs']" not in t:
        t = t.replace(
            "_toInt(map['duration'])",
            "_toInt(map['duration'] ?? map['durationMs'])",
        )
    p.write_text(t)
print("audio_file_service OK")
