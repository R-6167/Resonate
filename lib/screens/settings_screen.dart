import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../providers/intelligence_provider.dart';
import '../providers/bluetooth_provider.dart';
import 'equalizer_screen.dart';
import 'audio_effects_screen.dart';
import 'crossfade_screen.dart';
import 'audio_visualization_settings_screen.dart';
import 'library_management_screen.dart';
import 'intelligence_settings_screen.dart';
import 'about_screen.dart';
import 'queue_screen.dart';
import 'playlists_screen.dart';
import 'liked_songs_screen.dart';
import 'listening_history_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(padding: const EdgeInsets.all(14), children: [
      _section(context, 'Playback', Icons.play_circle_outline, [
        _item(context, 'Queue', 'View and manage upcoming songs', Icons.queue_music_rounded, const QueueScreen()),
        _item(context, 'Crossfade', 'Transition duration and curve', Icons.compare_arrows, const CrossfadeScreen()),
        _item(context, 'Effects', 'Loudness and audio processing', Icons.tune, const AudioEffectsScreen()),
      ]),
      _section(context, 'Audio', Icons.equalizer_rounded, [
        _item(context, 'Equalizer', 'Main sound profile', Icons.equalizer, const EqualizerScreen()),
        _item(context, 'Per-song EQ', 'Individual song profiles', Icons.music_note_rounded, const EqualizerScreen()),
      ]),
      _section(context, 'Intelligence', Icons.auto_awesome, [
        _item(context, 'Master switch & Authority', 'Suggestions, Assist or Autopilot', Icons.auto_awesome, const IntelligenceSettingsScreen()),
        _infoItem(context, 'Suggestions', 'Local recommendations with confidence and explanations.', Icons.lightbulb_outline),
        _infoItem(context, 'Automatic queue', 'Autopilot can prepare likely next tracks.', Icons.playlist_add_rounded),
        _infoItem(context, 'Exploration', 'Balance familiar listening with discovery.', Icons.explore_outlined),
        _infoItem(context, 'Explanations', 'Recommendations include human-readable reasons.', Icons.question_mark_rounded),
        _item(context, 'Learning', 'Listening memory and feedback', Icons.insights_rounded, const IntelligenceSettingsScreen()),
        _infoItem(context, 'Session intelligence', 'Understand the direction of the current session.', Icons.timeline_rounded),
        ListTile(leading: const Icon(Icons.restart_alt_rounded), title: const Text('Reset Intelligence'), subtitle: const Text('Clear learned recommendation feedback'), onTap: () => _confirm(context, 'Reset Intelligence', 'Clear learned recommendation feedback?', () => context.read<IntelligenceProvider>().clearRecommendationFeedback())),
      ]),
      _section(context, 'Bluetooth & Devices', Icons.bluetooth_audio_rounded, [
        ListTile(leading: const Icon(Icons.settings_input_component_rounded), title: const Text('Device controls'), subtitle: const Text('Media buttons, notification and connection behavior'), trailing: const Icon(Icons.chevron_right), onTap: () => _showBluetooth(context)),
      ]),
      _section(context, 'Library', Icons.library_music_rounded, [
        _item(context, 'Liked Songs', 'Your personal collection of favorites', Icons.favorite_rounded, const LikedSongsScreen()),
        _item(context, 'Playlists', 'Create and manage personal and smart playlists', Icons.queue_music_rounded, const PlaylistsScreen()),
        _item(context, 'Scan & folders', 'Scan now or choose folders', Icons.folder_open_rounded, const LibraryManagementScreen()),
      ]),
      _section(context, 'Appearance', Icons.palette_outlined, [
        ListTile(leading: const Icon(Icons.brightness_6_outlined), title: const Text('Theme'), subtitle: const Text('Light, dark or system'), trailing: const Icon(Icons.chevron_right), onTap: () => _showTheme(context)),
        _item(context, 'Visualization', 'Audio spectrum and waveform display', Icons.graphic_eq_rounded, const AudioVisualizationSettingsScreen()),
      ]),
      _section(context, 'Privacy', Icons.lock_outline_rounded, [
        _infoItem(context, 'Local-only learning', 'Intelligence uses on-device listening data.', Icons.phone_android_rounded),
        _item(context, 'Listening history', 'Browse, understand or clear playback events', Icons.history_rounded, const ListeningHistoryScreen()),
        _confirmItem(context, 'Delete Intelligence history', 'Erase recommendation feedback', Icons.delete_outline_rounded, 'Clear recommendation feedback now?', () => context.read<IntelligenceProvider>().clearRecommendationFeedback()),
      ]),
      _section(context, 'About', Icons.info_outline_rounded, [_item(context, 'About & How to use', 'Guide, privacy notes and copyright', Icons.menu_book_outlined, const AboutScreen())]),
    ]),
  );

  Widget _section(BuildContext context, String title, IconData icon, List<Widget> children) => Card(margin: const EdgeInsets.only(bottom: 10), child: ExpansionTile(leading: Icon(icon, color: Theme.of(context).colorScheme.primary), title: Text(title), children: children));
  Widget _item(BuildContext context, String title, String subtitle, IconData icon, Widget screen) => ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 20), leading: Icon(icon), title: Text(title), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)));
  Widget _infoItem(BuildContext context, String title, String text, IconData icon) => ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 20), leading: Icon(icon), title: Text(title), subtitle: Text(text), trailing: const Icon(Icons.info_outline), onTap: () => _info(context, title, text));
  Widget _confirmItem(BuildContext context, String title, String subtitle, IconData icon, String text, Future<void> Function() action) => ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 20), leading: Icon(icon), title: Text(title), subtitle: Text(subtitle), onTap: () => _confirm(context, title, text, action));
  Future<void> _showTheme(BuildContext context) async { await showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => Consumer<ThemeProvider>(builder: (_, theme, __) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [RadioListTile<String>(title: const Text('System'), value: 'system', groupValue: theme.useSystemTheme ? 'system' : (theme.isDarkMode ? 'dark' : 'light'), onChanged: (_) => theme.toggleSystemTheme(true)), RadioListTile<String>(title: const Text('Light'), value: 'light', groupValue: theme.useSystemTheme ? 'system' : (theme.isDarkMode ? 'dark' : 'light'), onChanged: (_) async { if (theme.useSystemTheme) await theme.toggleSystemTheme(false); if (theme.isDarkMode) await theme.toggleTheme(); }), RadioListTile<String>(title: const Text('Dark'), value: 'dark', groupValue: theme.useSystemTheme ? 'system' : (theme.isDarkMode ? 'dark' : 'light'), onChanged: (_) async { if (theme.useSystemTheme) await theme.toggleSystemTheme(false); if (!theme.isDarkMode) await theme.toggleTheme(); })]))); }
  void _info(BuildContext context, String title, String text) => showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (sheet) => SafeArea(child: Padding(padding: const EdgeInsets.all(22), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(sheet).textTheme.headlineSmall), const SizedBox(height: 12), Text(text)]))));
  Future<void> _confirm(BuildContext context, String title, String text, Future<void> Function() action) async { final yes = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(title), content: Text(text), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue'))])); if (yes == true) await action(); }
  void _showBluetooth(BuildContext context) => showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => const _BluetoothControls());
}

class _BluetoothControls extends StatelessWidget {
  const _BluetoothControls();
  @override
  Widget build(BuildContext context) => Consumer<BluetoothProvider>(builder: (_, bt, __) => SafeArea(child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 20), children: [
    ListTile(title: Text('Bluetooth & media controls', style: Theme.of(context).textTheme.titleLarge), subtitle: const Text('Resonate handles media commands from connected audio devices.')),
    SwitchListTile(title: const Text('Bluetooth controls'), value: bt.isEnabled, onChanged: bt.toggleBluetooth),
    SwitchListTile(title: const Text('Playback notification'), value: bt.showNotification, onChanged: bt.toggleNotification),
    SwitchListTile(title: const Text('Resume when device connects'), value: bt.resumeOnConnect, onChanged: bt.toggleResumeOnConnect),
    SwitchListTile(title: const Text('Pause when device disconnects'), value: bt.pauseOnDisconnect, onChanged: bt.togglePauseOnDisconnect),
  ])));
}
