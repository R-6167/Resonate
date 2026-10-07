#!/usr/bin/env python3
from pathlib import Path
p = Path('lib/modes/screens/modes_screen.dart')
t = p.read_text()
broken = '''        Text(

          ListTile(
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
          'Content folders',
          style: Theme.of(context).textTheme.titleMedium,
        ),
'''
fixed = '''        ListTile(
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
        ),
'''
if broken in t:
    t = t.replace(broken, fixed, 1)
    p.write_text(t)
    print('fixed')
elif "'Content folders'" in t and 'Mode shelf' in t:
    print('maybe already ok or different whitespace')
    # try softer
    if 'Text(\n\n          ListTile' in t or 'Text(\n\n          ListTile' in t.replace('\r',''):
        print('soft match needed')
    # print surrounding
    i = t.find('Content folders')
    print(repr(t[i-200:i+80]))
else:
    print('pattern miss')
