#!/usr/bin/env python3
import base64
from pathlib import Path
code = base64.b64decode(Path('tools/apply_notif_full.b64').read_text().strip()).decode()
exec(compile(code, 'apply_full.py', 'exec'), {'__name__': '__main__'})
