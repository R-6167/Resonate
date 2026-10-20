#!/usr/bin/env python3
from pathlib import Path
import re
p = Path('lib/modes/screens/modes_screen.dart')
t = p.read_text()
# Replace broken Text( ... ListTile ... 'Content folders' ...) block
pat = re.compile(
    r"Text\(\s*ListTile\([\s\S]*?\),\s*const SizedBox\(height: 12\),\s*'Content folders',\s*style: Theme\.of\(context\)\.textTheme\.titleMedium,\s*\),",
    re.M,
)
fixed = '''ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.playlist_play_rounded),
          title: const Text('Mode shelf'),
          subtitle: const Text(
            'Virtual playlist from folders and mode matches — does not hide your library',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ModeShelfScreen(),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Content folders',
          style: Theme.of(context).textTheme.titleMedium,
        ),'''
m = pat.search(t)
if not m:
    print('no regex match')
    # dump snippet
    i = t.find("'Content folders'")
    print(repr(t[max(0,i-400):i+60]))
    raise SystemExit(1)
t = pat.sub(fixed, t, count=1)
p.write_text(t)
print('fixed ok')
