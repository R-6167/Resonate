import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/theme_provider.dart';
import '../screens/equalizer_screen.dart';
import '../screens/audio_effects_screen.dart';
import '../screens/crossfade_screen.dart';
import '../screens/audio_visualization_settings_screen.dart';
import '../screens/library_management_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  static const _projectUrl = 'https://github.com/R-6167/Resonate';
  static const _feedbackUrl = 'https://github.com/R-6167/Resonate/issues/new';

  Future<void> _shareResonate(BuildContext context) async {
    try {
      await SharePlus.instance.share(
        const ShareParams(
          title: 'Resonate Music Player',
          text: 'Try Resonate — a local-first music player for Android.\n\n$_projectUrl',
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the share menu.')),
      );
    }
  }

  Future<void> _sendFeedback(BuildContext context) async {
    final uri = Uri.parse(_feedbackUrl);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the feedback page.')),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the feedback page.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings'), elevation: 0),
        body: Consumer<ThemeProvider>(
          builder: (context, themeProvider, _) => ListView(
            children: [
              _section(context, 'Appearance'),
              SwitchListTile(
                title: const Text('Dark Mode'),
                subtitle: const Text('Use the dark Resonate interface'),
                value: themeProvider.isDarkMode,
                onChanged: (_) => themeProvider.toggleTheme(),
              ),
              SwitchListTile(
                title: const Text('Use System Theme'),
                subtitle: const Text('Follow Android appearance settings'),
                value: themeProvider.useSystemTheme,
                onChanged: themeProvider.toggleSystemTheme,
              ),
              const Divider(),
              _section(context, 'Audio'),
              _route(context, Icons.equalizer, 'Equalizer', 'Shape the sound with the equalizer', const EqualizerScreen()),
              _route(context, Icons.tune, 'Audio Effects', 'Bass, reverb and other processing', const AudioEffectsScreen()),
              _route(context, Icons.compare_arrows, 'Crossfade', 'Smooth transitions between tracks', const CrossfadeScreen()),
              _route(context, Icons.graphic_eq, 'Visualization', 'Customize the lightweight Now Playing visualizer', const AudioVisualizationSettingsScreen()),
              const Divider(),
              _section(context, 'Library'),
              _route(context, Icons.folder_open_outlined, 'Library Management', 'Choose folders Resonate is allowed to scan', const LibraryManagementScreen()),
              const Divider(),
              _section(context, 'Intelligence'),
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('Resonate Intelligence'),
                subtitle: const Text('What to expect from the recommendation engine'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showIntelligence(context),
              ),
              const Divider(),
              _section(context, 'Help Resonate'),
              ListTile(
                leading: const Icon(Icons.share_rounded),
                title: const Text('Share Resonate'),
                subtitle: const Text('Share the project with friends and other testers'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _shareResonate(context),
              ),
              ListTile(
                leading: const Icon(Icons.feedback_outlined),
                title: const Text('Send Feedback'),
                subtitle: const Text('Report a crash, playback problem or suggest an idea'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _sendFeedback(context),
              ),
              const Divider(),
              _section(context, 'About'),
              const ListTile(title: Text('App Version'), subtitle: Text('0.1.0')),
              ListTile(
                title: const Text('About Resonate'),
                subtitle: const Text('A local-first intelligent music player by Aetherion LLC'),
                onTap: () => _showAbout(context),
              ),
            ],
          ),
        ),
      );

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );

  Widget _route(BuildContext context, IconData icon, String title, String subtitle, Widget page) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      );

  void _showAbout(BuildContext context) => showAboutDialog(
        context: context,
        applicationName: 'Resonate',
        applicationVersion: '0.1.0',
        applicationLegalese: '© 2026 Aetherion LLC. Licensed under MIT.',
        children: const [
          SizedBox(height: 16),
          Text('Resonate is an offline-first music experience built to understand how you listen and help decide what should play next — without channels, feeds, or unnecessary background processing.'),
        ],
      );

  void _showIntelligence(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(children: [Icon(Icons.auto_awesome), SizedBox(width: 10), Text('Resonate Intelligence')]),
        content: const SingleChildScrollView(
          child: Text('Resonate Intelligence is being built as a local-first recommendation system.\n\n• It learns from your listening history, skips, completions, favorites and transitions.\n• It builds a personal map of what you tend to play together.\n• It ranks candidates instead of blindly shuffling your library.\n• It will explain why a song was suggested.\n• It is designed to run locally and stay lightweight.\n\nThe long-term goal is a self-sustaining music experience: you open Resonate, and the Home page continuously proposes what fits your listening session — like a personal video platform without channels, subscriptions or a CPU-hungry feed.'),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Got it'))],
      ),
    );
  }
}
