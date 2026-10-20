#!/usr/bin/env python3
from pathlib import Path
import re

t = Path('lib/providers/music_provider.dart').read_text()
print('size', len(t), 'lines', t.count(chr(10))+1)

# Find class MusicProvider start
m = re.search(r'class MusicProvider\b[^{]*\{', t)
if not m:
    print('NO class MusicProvider')
else:
    print('class at', m.start(), m.group(0)[:80])

# Find all Future<bool> playSong definitions
for m in re.finditer(r'Future<(?:bool|void)> playSong\b', t):
    line = t[:m.start()].count(chr(10))+1
    print('playSong at offset', m.start(), 'line', line)
    # show surrounding 200 chars
    print('  ctx:', repr(t[m.start()-80:m.start()+120]))

for m in re.finditer(r'Future<(?:bool|void)> playQueueIndex\b', t):
    line = t[:m.start()].count(chr(10))+1
    print('playQueueIndex at line', line)

# Brace balance from class start
start = t.find('class MusicProvider')
if start >= 0:
    depth = 0
    in_class = False
    for i, ch in enumerate(t[start:], start):
        if ch == '{':
            depth += 1
            in_class = True
        elif ch == '}':
            depth -= 1
            if in_class and depth == 0:
                print('class closes at offset', i, 'line', t[:i].count(chr(10))+1)
                # methods after class?
                after = t[i+1:]
                if 'playSong' in after:
                    print('WARNING: playSong appears AFTER class close')
                    for m in re.finditer(r'playSong', after):
                        print('  after-class playSong at file line', t[:i+1+m.start()].count(chr(10))+1)
                break

# Check if setQueue at end calls playSong
idx = t.find('await playSong(')
while idx >= 0:
    line = t[:idx].count(chr(10))+1
    print('call await playSong at line', line)
    idx = t.find('await playSong(', idx+1)

# Unmatched braces overall
d = 0
for ch in t:
    if ch == '{': d += 1
    elif ch == '}': d -= 1
print('net brace depth', d)
