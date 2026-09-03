import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../providers/intelligence_provider.dart';
import '../providers/bluetooth_provider.dart';
import '../screens/equalizer_screen.dart';
import '../screens/audio_effects_screen.dart';
import '../screens/crossfade_screen.dart';
import '../screens/audio_visualization_settings_screen.dart';
import '../screens/library_management_screen.dart';
import '../screens/intelligence_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), elevation: 0),
      body: ListView(
        children: [
          _section(context, 'Appearance'),
          Consumer<ThemeProvider>(
            builder: (_, theme, __) => Column(children: [
              SwitchListTile(title: const Text('Dark Mode'), subtitle: const Text('Use the dark Resonate interface'), value: theme.isDarkMode, onChanged: (_) => theme.toggleTheme()),
              SwitchListTile(title: const Text('Use System Theme'), subtitle: const Text('Follow Android appearance settings'), value: theme.useSystemTheme, onChanged: theme.toggleSystemTheme),
            ]),
          ),
          const Divider(),
          _section(context, 'Audio'),
          _route(context, Icons.equalizer, 'Equalizer', 'Main and per-song sound profiles', const EqualizerScreen()),
          _route(context, Icons.tune, 'Audio Effects', 'Bass, reverb and processing controls', const AudioEffectsScreen()),
          _route(context, Icons.compare_arrows, 'Crossfade', 'Duration, curve and transition behavior', const CrossfadeScreen()),
          _route(context, Icons.graphic_eq, 'Visualization', 'Customize the Now Playing visualizer', const AudioVisualizationSettingsScreen()),
          const Divider(),
          _section(context, 'Playback & Devices'),
          Consumer<BluetoothProvider>(
            builder: (_, bt, __) => ListTile(
              leading: const Icon(Icons.bluetooth_audio_rounded),
              title: const Text('Bluetooth & Media Controls'),
              subtitle: Text(bt.bluetoothConnected ? 'Connected to ${bt.connectedDeviceName}' : 'Media-button and device behavior'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showBluetooth(context),
            ),
          ),
          const Divider(),
          _section(context, 'Intelligence'),
          Consumer<IntelligenceProvider>(
            builder: (_, intelligence, __) => ListTile(
              leading: Icon(intelligence.isEnabled ? Icons.auto_awesome : Icons.auto_awesome_outlined),
              title: const Text('Resonate Intelligence'),
              subtitle: Text(intelligence.isEnabled ? intelligence.autonomyLabel : 'Off'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IntelligenceSettingsScreen())),
            ),
          ),
          const Divider(),
          _section(context, 'Library'),
          _route(context, Icons.folder_open_outlined, 'Library Management', 'Choose folders Resonate is allowed to scan', const LibraryManagementScreen()),
          const Divider(),
          _section(context, 'About'),
          const ListTile(title: Text('App Version'), subtitle: Text('0.1.0')),
          ListTile(title: const Text('About Resonate'), subtitle: const Text('A local-first intelligent music player by Aetherion LLC'), onTap: () => _showAbout(context)),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
  );

  Widget _route(BuildContext context, IconData icon, String title, String subtitle, Widget page) => ListTile(
    leading: Icon(icon), title: Text(title), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right),
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

  void _showBluetooth(BuildContext context) {
    showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => const _BluetoothControls());
  }
}

class _BluetoothControls extends StatelessWidget {
  const _BluetoothControls();

  @override
  Widget build(BuildContext context) {
    return Consumer<BluetoothProvider>(
      builder: (_, bt, __) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 20),
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Bluetooth & media controls'), subtitle: Text('Android owns the Bluetooth radio. Resonate handles playback and media commands from connected audio devices.')),
            SwitchListTile(title: const Text('Bluetooth controls'), value: bt.isEnabled, onChanged: bt.toggleBluetooth),
            SwitchListTile(title: const Text('Playback notification'), value: bt.showNotification, onChanged: bt.toggleNotification),
            SwitchListTile(title: const Text('Resume when device connects'), value: bt.resumeOnConnect, onChanged: bt.toggleResumeOnConnect),
            SwitchListTile(title: const Text('Pause when device disconnects'), value: bt.pauseOnDisconnect, onChanged: bt.togglePauseOnDisconnect),
            ListTile(title: const Text('Media button behavior'), subtitle: Text(bt.getButtonBehaviorDescription(bt.settings.mediaButtonBehavior)), trailing: const Icon(Icons.chevron_right), onTap: () => _chooseBehavior(context, bt)),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseBehavior(BuildContext context, BluetoothProvider bt) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Media button behavior'),
        children: [
          for (final value in [0, 1, 2])
            SimpleDialogOption(onPressed: () => Navigator.pop(context, value), child: Text(bt.getButtonBehaviorDescription(value))),
        ],
      ),
    );
    if (selected != null) await bt.setMediaButtonBehavior(selected);
  }
}
