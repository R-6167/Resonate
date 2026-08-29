import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../providers/equalizer_provider.dart';
import 'equalizer_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
      ),
      body: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return ListView(
            children: [
              // Theme Section
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SwitchListTile(
                title: const Text('Dark Mode'),
                subtitle: const Text('Use dark theme'),
                value: themeProvider.isDarkMode,
                onChanged: (_) => themeProvider.toggleTheme(),
              ),
              SwitchListTile(
                title: const Text('Use System Theme'),
                subtitle: const Text('Follow system settings'),
                value: themeProvider.useSystemTheme,
                onChanged: (value) => themeProvider.toggleSystemTheme(value),
              ),
              const Divider(),

              // Audio Section
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Audio',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ListTile(
                title: const Text('Equalizer'),
                subtitle: const Text('10-band advanced equalizer with presets'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EqualizerScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                title: const Text('Crossfade'),
                subtitle: const Text('Enable smooth transitions'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Crossfade - Feature coming soon'),
                    ),
                  );
                },
              ),
              const Divider(),

              // Library Section
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Library',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ListTile(
                title: const Text('Auto-scan for new songs'),
                subtitle: const Text('Automatically add new audio files'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Auto-scan - Feature coming soon'),
                    ),
                  );
                },
              ),
              ListTile(
                title: const Text('Manage storage'),
                subtitle: const Text('View music directories'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Storage management - Feature coming soon'),
                    ),
                  );
                },
              ),
              const Divider(),

              // About Section
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'About',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const ListTile(
                title: Text('App Version'),
                subtitle: Text('1.0.0'),
              ),
              ListTile(
                title: const Text('About Resonate'),
                subtitle: const Text('A feature-rich music player'),
                onTap: () {
                  showAboutDialog(
                    context: context,
                    applicationName: 'Resonate',
                    applicationVersion: '1.0.0',
                    applicationLegalese:
                        '© 2024 Resonate. Licensed under MIT.',
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
