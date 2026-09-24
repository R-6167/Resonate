#!/usr/bin/env python3
from pathlib import Path

MP = Path("lib/providers/music_provider.dart")
t = MP.read_text()

old = """          'tempoApplied': tempoApplied,
        },
      )
    } catch (e) {
      debugPrint('DJ handoff prepare skipped: $e');"""

new = """          'tempoApplied': tempoApplied,
        },
      );
    } catch (e) {
      debugPrint('DJ handoff prepare skipped: $e');"""

if old in t:
    MP.write_text(t.replace(old, new, 1))
    print("fixed semicolon")
elif ");\n    } catch (e) {\n      debugPrint('DJ handoff prepare skipped" in t:
    print("already fixed")
else:
    print("MISS")
    raise SystemExit(1)
