#!/usr/bin/env python3
"""Fix malformed try in soft-outgoing ramp that broke MusicProvider brace balance."""
from pathlib import Path

p = Path('lib/providers/music_provider.dart')
t = p.read_text()

# Broken pattern from soft-outgoing patch:
#   try {
#     final outT = ...
#   final inT = ...   <-- missing close, ruins class structure
broken = '''        try {
          final outT = math.pow(t, 1.28).toDouble().clamp(0.0, 1.0);
        final inT = math.pow(t, 0.92).toDouble().clamp(0.0, 1.0);
'''

fixed = '''        final outT = math.pow(t, 1.28).toDouble().clamp(0.0, 1.0);
        final inT = math.pow(t, 0.92).toDouble().clamp(0.0, 1.0);
'''

if broken in t:
    t = t.replace(broken, fixed, 1)
    p.write_text(t)
    print('fixed soft-outgoing try block')
elif fixed in t:
    print('already fixed')
else:
    # broader search
    if 'try {\n          final outT = math.pow(t, 1.28)' in t:
        t = t.replace(
            '        try {\n          final outT = math.pow(t, 1.28).toDouble().clamp(0.0, 1.0);\n',
            '        final outT = math.pow(t, 1.28).toDouble().clamp(0.0, 1.0);\n',
            1,
        )
        p.write_text(t)
        print('fixed via alternate pattern')
    else:
        print('pattern not found')
        # show nearby
        idx = t.find('final outT = math.pow(t, 1.28)')
        if idx >= 0:
            print(repr(t[idx-40:idx+120]))

# brace check
def depth(s):
    d = 0
    in_str = None
    lc = bc = False
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if lc:
            if c == '\n':
                lc = False
            i += 1
            continue
        if bc:
            if c == '*' and i + 1 < n and s[i + 1] == '/':
                bc = False
                i += 2
                continue
            i += 1
            continue
        if in_str:
            if c == '\\':
                i += 2
                continue
            if c == in_str:
                in_str = None
            i += 1
            continue
        if c in ("'", '"'):
            in_str = c
            i += 1
            continue
        if c == '/' and i + 1 < n:
            if s[i + 1] == '/':
                lc = True
                i += 2
                continue
            if s[i + 1] == '*':
                bc = True
                i += 2
                continue
        if c == '{':
            d += 1
        elif c == '}':
            d -= 1
        i += 1
    return d

t2 = p.read_text()
print('brace depth', depth(t2))
print('has playSong', 'Future<bool> playSong(Song song' in t2)
