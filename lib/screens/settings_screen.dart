import 'package:flutter/material.dart';
import '../ui/resonate_glass.dart';
import 'package:provider/provider.dart';
import '../providers/bluetooth_provider.dart';
import '../providers/intelligence_provider.dart';
import '../providers/theme_provider.dart';
import 'about_screen.dart';
import 'audio_effects_screen.dart';
import 'audio_visualization_settings_screen.dart';
import 'crossfade_screen.dart';
import 'dj_mode_settings_screen.dart';
import 'modes_screen.dart';
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
  Widget build(BuildContext context) {
    return ResonateGlassScaffold(
      title: const Text('Settings'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 36),
        children: [
          ResonateGlassCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Resonate', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    'Local-first listening. Tune playback, intelligence and devices here.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Audio tools are always available',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Equalizer, Crossfade, DJ Mode, and Effects work from Settings even before you play a song. Open Playback to find DJ Mode.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _section(context, 'Playback', Icons.play_circle_outline, [
            _item(context, 'Queue', 'View and manage upcoming songs', Icons.queue_music_rounded, const QueueScreen()),
            _item(context, 'Crossfade', 'Transitions + seamless Repeat one loop', Icons.compare_arrows_rounded, const CrossfadeScreen()),
            _item(context, 'DJ Mode', 'Optional beat, tempo and harmonic blending', Icons.headphones_rounded, const DjModeSettingsScreen()),
          ], initiallyExpanded: true),
          _section(context, 'Modes', Icons.tune_rounded, [
            _item(context, 'Listening modes', 'Normal, Running, Driving, Work, Podcast, Motivation, Audiobook', Icons.tune_rounded, const ModesScreen()),
          ]),
          _section(context, 'Audio', Icons.equalizer_rounded, [
            _item(context, 'Equalizer', 'Tone, preamp, bass, width & reverb', Icons.equalizer_rounded, const EqualizerScreen()),
            _item(context, 'Per-song EQ', 'Individual song profiles', Icons.music_note_rounded, const EqualizerScreen()),
          ]),
          _section(context, 'Intelligence', Icons.auto_awesome, [
            _item(context, 'Advanced Intelligence', 'Modes, consent, companion decision log, learning', Icons.auto_awesome, const IntelligenceSettingsScreen()),
            _item(context, 'DJ Mode', 'Beat/tempo handoffs + optional harmonic bias for Autopilot', Icons.headphones_rounded, const DjModeSettingsScreen()),
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
              subtitle: Text(context.watch<ThemeProvider>().useSystemTheme
                  ? 'System'
                  : (context.watch<ThemeProvider>().isDarkMode ? 'Dark' : 'Light')),
              onTap: () => context.read<ThemeProvider>().toggleTheme(),
            ),
            _item(context, 'Visualization', 'Audio spectrum and waveform display', Icons.graphic_eq_rounded, const AudioVisualizationSettingsScreen()),
          ]),
          _section(context, 'Privacy', Icons.lock_outline_rounded, [
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('Listening history'),
              subtitle: const Text('Local playback history on this device'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ListeningHistoryScreen())),
            ),
          ]),
          _section(context, 'About', Icons.info_outline_rounded, [
            _item(context, 'About Resonate', 'Version, credits and diagnostics entry', Icons.info_outline_rounded, const AboutScreen()),
            _item(context, 'Diagnostics', 'Playback and system diagnostics', Icons.bug_report_outlined, const DiagnosticsScreen()),
          ]),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, IconData icon, List<Widget> children, {bool initiallyExpanded = false}) =>
      ExpansionTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        initiallyExpanded: initiallyExpanded,
        children: children,
      );

  Widget _item(BuildContext context, String title, String subtitle, IconData icon, Widget page) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      );

  Future<void> _confirm(BuildContext context, String title, String body, Future<void> Function() action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (ok == true) await action();
  }
}

class BluetoothSettingsScreen extends StatefulWidget {
  const BluetoothSettingsScreen({super.key});

  @override
  State<BluetoothSettingsScreen> createState() => _BluetoothSettingsScreenState();
}

class _BluetoothSettingsScreenState extends State<BluetoothSettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BluetoothProvider>().refreshConnectedDevices();
    });
  }

  @override
  Widget build(BuildContext context) => ResonateGlassScaffold(
        title: const Text('Bluetooth & media controls'),
        body: Consumer<BluetoothProvider>(
          builder: (_, bt, __) => ListView(
            padding: const EdgeInsets.all(14),
            children: [
              ResonateGlassCard(
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
              const Divider(),
              ListTile(
                leading: const Icon(Icons.devices_other_rounded),
                title: const Text('Current device context'),
                subtitle: Text(
                  bt.bluetoothConnected
                      ? '${bt.connectedDeviceName}\n${bt.audioContextLabel} - ${bt.audioContextHint}'
                      : 'No device connected.\n${bt.audioContextHint}',
                ),
                isThreeLine: true,
              ),
              SwitchListTile.adaptive(
                title: const Text('Adjust exploration for context'),
                subtitle: Text(
                  bt.contextExplorationAdjust
                      ? 'Car/speaker nudge exploration (bias ${bt.explorationBias}).'
                      : 'Context classification only - no exploration change.',
                ),
                value: bt.contextExplorationAdjust,
                onChanged: bt.setContextExplorationAdjust,
              ),
              TextButton.icon(
                onPressed: () => bt.refreshConnectedDevices(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh device detection'),
              ),
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
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Open Advanced Intelligence'),
              subtitle: const Text('Real controls live there'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IntelligenceSettingsScreen())),
            ),
          ],
        ),
      );

  String _description(String section) => switch (section) {
        'Suggestions' => 'Suggestions are the lowest-authority Intelligence layer. Resonate can recommend tracks with a confidence score and a human-readable reason without taking playback control.',
        'Automatic queue' => 'Automatic queue keeps a small runway of likely next tracks ready when autonomy and consent allow it.',
        'Exploration' => 'Exploration controls how aggressively Resonate moves beyond familiar listening. Higher values favor new or less-heard tracks.',
        'Explanations' => 'Explanations control whether recommendation reasons and confidence are shown with companion choices.',
        'Learning' => 'Learning forms local memory from skips, completions and feedback without leaving this device.',
        'Session Intelligence' => 'Session Intelligence reads the current listening direction so recent artists, completions and skips can influence what feels right next.',
        _ => 'Intelligence detail',
      };
}

class _SuggestionsControls extends StatelessWidget {
  const _SuggestionsControls();
  @override
  Widget build(BuildContext c) => Consumer<IntelligenceProvider>(builder: (_, i, __) => Column(children: [
        SwitchListTile.adaptive(title: const Text('Intelligence'), subtitle: Text(i.isEnabled ? 'Active' : 'Off'), value: i.isEnabled, onChanged: i.setEnabled),
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
