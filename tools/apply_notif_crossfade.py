#!/usr/bin/env python3
import base64
from pathlib import Path

def write(dest, b64path):
    data = base64.b64decode(Path(b64path).read_text().replace("\n","").strip())
    Path(dest).write_bytes(data)
    print("wrote", dest, len(data))

write("lib/services/audio_service_handler.dart", "tools/_payload_handler.b64")
write("lib/main.dart", "tools/_payload_main.b64")
write("lib/providers/music_provider.dart", "tools/_payload_music.b64")
assert "publishPositionTick" in Path("lib/services/audio_service_handler.dart").read_text()
assert "positionOnly" in Path("lib/providers/music_provider.dart").read_text()
assert "androidStopForegroundOnPause: false" in Path("lib/main.dart").read_text()
print("ok")
