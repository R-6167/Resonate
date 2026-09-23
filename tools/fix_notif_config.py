#!/usr/bin/env python3
from pathlib import Path
p = Path('lib/main.dart')
t = p.read_text()
old = """      androidNotificationOngoing: true,
      androidStopForegroundOnPause: false,"""
new = """      // audio_service asserts: ongoing must be false when stopForegroundOnPause is false.
      androidNotificationOngoing: false,
      // Keep the media session / notification while paused so play-pause stays real-time.
      androidStopForegroundOnPause: false,"""
if old not in t:
    if 'androidNotificationOngoing: false' in t:
        print('already fixed')
    else:
        raise SystemExit('config block not found')
else:
    p.write_text(t.replace(old, new, 1))
    print('fixed')
assert 'androidNotificationOngoing: false' in p.read_text()
