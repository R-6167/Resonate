import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/bluetooth_provider.dart';
import '../providers/intelligence_provider.dart';
import '../providers/theme_provider.dart';
import 'about_screen.dart';
import 'audio_effects_screen.dart';
import 'audio_visualization_settings_screen.dart';
import 'crossfade_screen.dart';
import 'diagnostics_screen.dart';
import 'equalizer_screen.dart';
import 'intelligence_settings_screen.dart';
import 'library_management_screen.dart';
import 'liked_songs_screen.dart';
import 'listening_history_screen.dart';
import 'playlists_screen.dart';
import 'queue_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _section(context, 'Playback', Icons.play_circle_outline, [
              _item(context, 'Queue', 'View and manage upcoming songs', Icons.queue_music_rounded, const QueueScreen()),
              _item(context, 'Crossfade', 'Transition duration and curve', Icons.compare_arrows_rounded, const CrossfadeScreen()),
              _item(context, 'Effects', 'Loudness and audio processing', Icons.tune_rounded, const AudioEffectsScreen()),
            ]),
            _section(context, 'Audio', Icons.equalizer_rounded, [
              _item(context, 'Equalizer', 'Main sound profile', Icons.equalizer_rounded, const EqualizerScreen()),
              _item(context, 'Per-song EQ', 'Individual song profiles', Icons.music_note_rounded, const EqualizerScreen()),
            ]),
            _section(context, 'Intelligence', Icons.auto_awesome, [
              _item(context, 'Advanced Intelligence', 'All decision, learning and Companion controls', Icons.auto_awesome, const IntelligenceSettingsScreen()),
              _item(context, 'Suggestions', 'Recommendation confidence, explanations and ranking behavior', Icons.lightbulb_outline_rounded, const IntelligenceDetailScreen(section: 'Suggestions')),
              _item(context, 'Automatic queue', 'How Resonate prepares likely next tracks', Icons.playlist_add_rounded, const IntelligenceDetailScreen(section: 'Automatic queue')),
              _item(context, 'Exploration', 'Balance familiar listening with discovery', Icons.explore_outlined, const IntelligenceDetailScreen(section: 'Exploration')),
              _item(context, 'Explanations', 'Control the reasons and confidence shown with choices', Icons.question_mark_rounded, const IntelligenceDetailScreen(section: 'Explanations')),
              _item(context, 'Learning', 'See and control how local listening memory is formed', Icons.insights_rounded, const IntelligenceDetailScreen(section: 'Learning')),
              _item(context, 'Session Intelligence', 'Use the current listening direction when ranking tracks', Icons.timeline_rounded, const IntelligenceDetailScreen(section: 'Session Intelligence')),
              ListTile(
                leading: const Icon(Icons.restart_alt_rounded),
                title: const Text('Reset learned feedback'),
                subtitle: const Text('Clear recommendation feedback, not listening history'),
                onTap: () => _confirm(context, 'Reset Intelligence', 'Clear learned recommendation feedback?', () => context.read<IntelligenceProvider>().clearRecommendationFeedback()),
              ),
            ]),
            _section(context, 'Bluetooth & Devices', Icons.bluetooth_audio_rounded, [
              _item(context, 'Device controls', 'Media buttons, notification and connection behavior', Icons.settings_input_component_rounded, const BluetoothSettingsScreen()),
            ]),
            _section(context, 'Library', Icons.library_music_rounded, [
              _item(context, 'Liked Songs', 'Your personal collection of favorites', Icons.favorite_rounded, const LikedSongsScreen()),
              _item(context, 'Playlists', 'Create and manage personal and smart playlists', Icons.queue_music_rounded, const PlaylistsScreen()),
              _item(context, 'Scan & folders', 'Scan now or choose folders', Icons.folder_open_rounded, const LibraryManagementScreen()),
            ]),
            _section(context, 'Appearance', Icons.palette_outlined, [
              ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: const Text('Theme'),
                subtitle: const Text('Light, dark or system'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showTheme(context),
              ),
              _item(context, 'Visualization', 'Audio spectrum and waveform display', Icons.graphic_eq_rounded, const AudioVisualizationSettingsScreen()),
            ]),
            _section(context, 'Privacy', Icons.lock_outline_rounded, [
              const ListTile(leading: Icon(Icons.phone_android_rounded), title: Text('Local-only learning'), subtitle: Text('Intelligence uses on-device listening data.')),
              _item(context, 'Privacy & Diagnostics', 'Crash capture, technical events, feedback and report export', Icons.health_and_safety_rounded, const DiagnosticsScreen()),
              _item(context, 'Listening history', 'Browse, understand or clear playback events', Icons.history_rounded, const ListeningHistoryScreen()),
              _confirmItem(context, 'Delete Intelligence history', 'Erase recommendation feedback', Icons.delete_outline_rounded, 'Clear recommendation feedback now?', Icons.delete_outline_rounded, () => context.read<IntelligenceProvider>().clearRecommendationFeedback()),
            ]),
            _section(context, 'About', Icons.info_outline_rounded, [
              _item(context, 'About & How to use', 'Guide, privacy notes and copyright', Icons.menu_book_outlined, const AboutScreen()),
            ]),
          ],
        ),
      );

  Widget _section(BuildContext context, String title, IconData icon, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ExpansionTile(
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: Text(title),
          children: children,
        ),
      );

  Widget _item(BuildContext context, String title, String subtitle, IconData icon, Widget screen) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
      );

  Widget _confirmItem(BuildContext context, String title, String subtitle, IconData icon, String text, IconData trailingIcon, Future<void> Function() action) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Icon(trailingIcon),
        onTap: () => _confirm(context, title, text, action),
      );

  Future<void> _showTheme(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Consumer<ThemeProvider>(
        builder: (_, theme, __) {
          final selected = theme.useSystemTheme ? 'system' : (theme.isDarkMode ? 'dark' : 'light');
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('Theme'), subtitle: Text('Choose how Resonate looks.')),
                RadioGroup<String>(
                  groupValue: selected,
                  onChanged: (value) async {
                    if (value == null) return;
                    if (value == 'system') {
                      await theme.toggleSystemTheme(true);
                    } else {
                      if (theme.useSystemTheme) await theme.toggleSystemTheme(false);
                      final wantsDark = value == 'dark';
                      if (theme.isDarkMode != wantsDark) await theme.toggleTheme();
                    }
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                  child: const Column(
                    children: [
                      RadioListTile<String>(value: 'system', title: Text('System')),
                      RadioListTile<String>(value: 'light', title: Text('Light')),
                      RadioListTile<String>(value: 'dark', title: Text('Dark')),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirm(BuildContext context, String title, String text, Future<void> Function() action) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
        ],
      ),
    );
    if (yes == true) await action();
  }
}

class BluetoothSettingsScreen extends StatelessWidget {
  const BluetoothSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Bluetooth & media controls')),
        body: Consumer<BluetoothProvider>(
          builder: (_, bt, __) => ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'Control how Resonate responds to Bluetooth buttons, notifications and device connection changes.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
              SwitchListTile.adaptive(title: const Text('Bluetooth controls'), subtitle: const Text('Accept play, pause, next and previous commands from connected devices.'), value: bt.isEnabled, onChanged: bt.toggleBluetooth),
              SwitchListTile.adaptive(title: const Text('Playback notification'), subtitle: const Text('Show Resonate playback controls in the Android notification shade.'), value: bt.showNotification, onChanged: bt.toggleNotification),
              SwitchListTile.adaptive(title: const Text('Resume when device connects'), subtitle: const Text('Resume the previous session when a Bluetooth device connects.'), value: bt.resumeOnConnect, onChanged: bt.toggleResumeOnConnect),
              SwitchListTile.adaptive(title: const Text('Pause when device disconnects'), subtitle: const Text('Pause playback when the active Bluetooth device disconnects.'), value: bt.pauseOnDisconnect, onChanged: bt.togglePauseOnDisconnect),
            ],
          ),
        ),
      );
}

class IntelligenceDetailScreen extends StatelessWidget {
  final String section;
  const IntelligenceDetailScreen({super.key, required this.section});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(section)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 36),
          children: [
            Card(child: Padding(padding: const EdgeInsets.all(18), child: Text(_description(section), style: Theme.of(context).textTheme.bodyLarge))),
            const SizedBox(height: 10),
            if (section == 'Suggestions') const _SuggestionsControls(),
            if (section == 'Automatic queue') const _QueueControls(),
            if (section == 'Exploration') const _ExplorationControls(),
            if (section == 'Explanations') const _ExplanationControls(),
            if (section == 'Learning') const _LearningControls(),
            if (section == 'Session Intelligence') const _SessionControls(),
            const SizedBox(height: 18),
            OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IntelligenceSettingsScreen())), icon: const Icon(Icons.tune_rounded), label: const Text('Open all Intelligence settings')),
          ],
        ),
      );

  String _description(String s) => switch (s) {
        'Suggestions' => 'Suggestions are the lowest-authority Intelligence layer. Resonate can recommend tracks with a confidence score and a human-readable reason without taking playback control.',
        'Automatic queue' => 'Automatic queue prepares a small runway of likely next tracks. It does not replace the normal player when Intelligence is disabled.',
        'Exploration' => 'Exploration controls how aggressively Resonate moves beyond familiar listening. Higher values favor new or less-heard tracks.',
        'Explanations' => 'Explanations keep Intelligence understandable by showing why a recommendation was selected and how confident Resonate is.',
        'Learning' => 'Learning is continuous and local. Finishes, skips, replay behavior, recency and song-to-song choices become evidence over time; there is no artificial graduation shortcut.',
        'Session Intelligence' => 'Session Intelligence reads the current listening direction so recent artists, completions and skips can influence what feels right next.',
        _ => '',
      };
}

class _SuggestionsControls extends StatelessWidget {
  const _SuggestionsControls();
  @override
  Widget build(BuildContext c) => Consumer<IntelligenceProvider>(builder: (_, i, __) => Column(children: [
        SwitchListTile.adaptive(title: const Text('Intelligence suggestions'), subtitle: const Text('Allow local recommendations to appear on For You and Player.'), value: i.isEnabled, onChanged: i.setEnabled),
        const ListTile(title: Text('Confidence and explanations'), subtitle: Text('Tune these in Advanced Intelligence.')),
      ]));
}

class _QueueControls extends StatelessWidget {
  const _QueueControls();
  @override
  Widget build(BuildContext c) => Consumer<IntelligenceProvider>(builder: (_, i, __) => Column(children: [
        SwitchListTile.adaptive(title: const Text('Automatic queue'), subtitle: const Text('Keep likely next tracks prepared.'), value: true, onChanged: (_) => Navigator.push(c, MaterialPageRoute(builder: (_) => const IntelligenceSettingsScreen()))),
        ListTile(title: const Text('Authority'), subtitle: Text(i.isAutopilot ? 'Autopilot is allowed to choose when confidence is high.' : 'Current autonomy: ${i.autonomyLabel}')),
      ]));
}

class _ExplorationControls extends StatelessWidget {
  const _ExplorationControls();
  @override
  Widget build(BuildContext c) => const ListTile(title: Text('Exploration control'), subtitle: Text('Use Advanced Intelligence to set the exact exploration percentage. Changes apply to recommendation ranking.'));
}

class _ExplanationControls extends StatelessWidget {
  const _ExplanationControls();
  @override
  Widget build(BuildContext c) => const ListTile(title: Text('Show reasons'), subtitle: Text('Recommendation explanations can be enabled or disabled in Advanced Intelligence.'));
}

class _LearningControls extends StatelessWidget {
  const _LearningControls();
  @override
  Widget build(BuildContext c) => const Column(children: [
        ListTile(leading: Icon(Icons.school_rounded), title: Text('Learning is active while you listen'), subtitle: Text('Resonate learns from actual interaction signals over time.')),
        ListTile(leading: Icon(Icons.storage_rounded), title: Text('Local memory'), subtitle: Text('Learning stays on this device and remains independent from basic playback.')),
      ]);
}

class _SessionControls extends StatelessWidget {
  const _SessionControls();
  @override
  Widget build(BuildContext c) => const Column(children: [
        ListTile(leading: Icon(Icons.timeline_rounded), title: Text('Current-session signals'), subtitle: Text('Recent skips, completions, artists and transition choices can influence the next recommendation.')),
        ListTile(leading: Icon(Icons.refresh_rounded), title: Text('Continuous adaptation'), subtitle: Text('Session direction updates as the current listening session changes.')),
      ]);
}
