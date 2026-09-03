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

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Settings')), body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
    _header(context, 'Playback', 'How Resonate behaves while you listen', Icons.play_circle_outline),
    _item(context, 'Playback behaviour', 'Play, pause, next and previous', Icons.play_arrow_rounded, () => _info(context, 'Playback behaviour', 'Playback remains controlled by the player. Bluetooth, notifications and Intelligence all route commands through the same playback engine.')),
    _item(context, 'Queue behaviour', 'Queue, anticipation and next-track handling', Icons.queue_music_rounded, () => _info(context, 'Queue behaviour', 'Your current queue remains authoritative. Intelligence can prepare additions in Autopilot, but never becomes the owner of playback.')),
    _item(context, 'Crossfade', 'Duration, curve and transition behavior', Icons.compare_arrows, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CrossfadeScreen()))),
    _item(context, 'Gapless playback', 'Continuous playback between queued tracks', Icons.all_inclusive, () => _info(context, 'Gapless playback', 'Resonate uses just_audio queue preparation for continuous local playback.')),
    _item(context, 'Replay gain / loudness', 'Loudness enhancement and level control', Icons.volume_up_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AudioEffectsScreen()))),
    _item(context, 'Volume behaviour', 'Master volume and output level', Icons.volume_down_rounded, () => _info(context, 'Volume behaviour', 'Resonate keeps the app volume synchronized with its active playback deck.')),
    _item(context, 'Resume behaviour', 'Resume after interruption or reopening', Icons.restore_rounded, () => _info(context, 'Resume behaviour', 'Playback interruption handling is enabled; explicit persistent resume policy can be expanded without changing the player authority model.')),
    _divider(),
    _header(context, 'Audio', 'Sound shaping and output', Icons.equalizer_rounded),
    _item(context, 'Equalizer', 'Main and per-song sound profiles', Icons.equalizer, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EqualizerScreen()))),
    _item(context, 'Per-song EQ', 'Keep individual song profiles', Icons.music_note_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EqualizerScreen()))),
    _item(context, 'Effects', 'Bass, reverb and processing', Icons.tune, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AudioEffectsScreen()))),
    _item(context, 'Audio output', 'Android audio session and device routing', Icons.speaker_rounded, () => _info(context, 'Audio output', 'Android manages the physical output route. Resonate configures a music audio session and follows device changes.')),
    _item(context, 'Audio focus', 'Handle calls, navigation and interruptions', Icons.hearing_rounded, () => _info(context, 'Audio focus', 'Audio focus and becoming-noisy events are handled through the Android audio session.')),
    _divider(),
    _header(context, 'Intelligence', 'Your local companion and its authority', Icons.auto_awesome),
    Consumer<IntelligenceProvider>(builder: (_, intelligence, __) => _item(context, 'Master switch & Authority', intelligence.isEnabled ? intelligence.autonomyLabel : 'Off', Icons.auto_awesome, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IntelligenceSettingsScreen())))),
    _item(context, 'Suggestions', 'Recommendations without taking control', Icons.lightbulb_outline, () => _info(context, 'Suggestions', 'Intelligence can recommend songs with a reason and confidence score.')),
    _item(context, 'Automatic queue', 'Prepare likely next tracks before silence', Icons.playlist_add_rounded, () => _info(context, 'Automatic queue', 'Autopilot can prepare high-confidence recommendations near the end of a track so playback can continue smoothly.')),
    _item(context, 'Exploration', 'Balance familiar choices with discovery', Icons.explore_outlined, () => _info(context, 'Exploration', 'Exploration will remain local and confidence-aware; it will be expanded as the recommendation graph matures.')),
    _item(context, 'Explanations', 'See why a recommendation was chosen', Icons.question_mark_rounded, () => _info(context, 'Explanations', 'Every current prediction carries a human-readable reason and confidence.')),
    _item(context, 'Learning', 'Listening memory and feedback', Icons.insights_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IntelligenceSettingsScreen()))),
    _item(context, 'Session intelligence', 'Learn the direction of the current listening session', Icons.timeline_rounded, () => _info(context, 'Session intelligence', 'Session-aware trajectory is the next layer of the companion system and will build on local listening events.')),
    _item(context, 'Reset Intelligence', 'Clear recommendation feedback and relearn', Icons.restart_alt_rounded, () => _confirm(context, 'Reset Intelligence', 'Clear learned recommendation feedback?', () => context.read<IntelligenceProvider>().clearRecommendationFeedback())),
    _divider(),
    _header(context, 'Bluetooth & Devices', 'Media buttons and connection behavior', Icons.bluetooth_audio_rounded),
    Consumer<BluetoothProvider>(builder: (_, bt, __) => _item(context, 'Media buttons', bt.getButtonBehaviorDescription(bt.settings.mediaButtonBehavior), Icons.headset_rounded, () => _showBluetooth(context))),
    _item(context, 'Connection behaviour', 'Respond to connected audio devices', Icons.devices_other_rounded, () => _showBluetooth(context)),
    _item(context, 'Resume on connect', 'Continue when a device connects', Icons.play_arrow_rounded, () => _showBluetooth(context)),
    _item(context, 'Pause on disconnect', 'Pause when an audio route disappears', Icons.pause_circle_outline, () => _showBluetooth(context)),
    _item(context, 'Device behaviour', 'Android audio route and media controls', Icons.settings_input_component_rounded, () => _showBluetooth(context)),
    _divider(),
    _header(context, 'Library', 'What Resonate can see locally', Icons.library_music_rounded),
    _item(context, 'Scan', 'Find local audio files', Icons.search_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryManagementScreen()))),
    _item(context, 'Folders', 'Choose scan locations', Icons.folder_open_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryManagementScreen()))),
    _item(context, 'Metadata', 'Song and artist information', Icons.text_fields_rounded, () => _info(context, 'Metadata', 'Library metadata remains local to the device.')),
    _item(context, 'Artwork', 'Album artwork handling', Icons.image_outlined, () => _info(context, 'Artwork', 'Artwork is kept as local media metadata and artwork paths where available.')),
    _item(context, 'Library exclusions', 'Keep folders out of scanning', Icons.block_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryManagementScreen()))),
    _divider(),
    _header(context, 'Appearance', 'Make Resonate feel like yours', Icons.palette_outlined),
    Consumer<ThemeProvider>(builder: (_, theme, __) => Column(children: [SwitchListTile.adaptive(title: const Text('Dark theme'), subtitle: Text(theme.isDarkMode ? 'Dark interface' : 'Light interface'), value: theme.isDarkMode, onChanged: (_) => theme.toggleTheme()), SwitchListTile.adaptive(title: const Text('Use system theme'), subtitle: const Text('Follow Android light/dark preference'), value: theme.useSystemTheme, onChanged: theme.toggleSystemTheme)])),
    _item(context, 'Accent', 'Resonate violet accent', Icons.color_lens_outlined, () => _info(context, 'Accent', 'The Intelligence branch uses a violet Resonate accent and layered surfaces for a more expressive visual identity.')),
    _item(context, 'Player layout', 'Player presentation and controls', Icons.dashboard_customize_outlined, () => _info(context, 'Player layout', 'Player layout remains stable while Intelligence features are layered around it.')),
    _item(context, 'Artwork style', 'Album-art presentation', Icons.album_outlined, () => _info(context, 'Artwork style', 'Artwork styling will remain compatible with the existing player.')),
    _item(context, 'Animations', 'Motion and transition feel', Icons.animation_rounded, () => _info(context, 'Animations', 'Resonate keeps the existing polished player action animation and lightweight UI motion.')),
    _item(context, 'Compact/full controls', 'Choose how much playback UI is visible', Icons.view_agenda_outlined, () => _info(context, 'Compact/full controls', 'Control density is reserved for the player layout layer so existing playback features stay intact.')),
    _divider(),
    _header(context, 'Privacy', 'Your listening data stays yours', Icons.lock_outline_rounded),
    _item(context, 'Local-only learning', 'No cloud recommendation profile required', Icons.phone_android_rounded, () => _info(context, 'Local-only learning', 'Intelligence is designed around local listening events and on-device recommendation logic.')),
    _item(context, 'Listening history', 'Playback events used for learning', Icons.history_rounded, () => _info(context, 'Listening history', 'Listening events include completion, skips and transitions so the companion can learn your habits.')),
    _item(context, 'Export Intelligence data', 'Export learned signals', Icons.ios_share_rounded, () => _info(context, 'Export Intelligence data', 'Export is planned as a portable local data feature.')),
    _item(context, 'Delete Intelligence history', 'Erase listening-learning history', Icons.delete_outline_rounded, () => _confirm(context, 'Delete Intelligence history', 'Clear recommendation feedback now?', () => context.read<IntelligenceProvider>().clearRecommendationFeedback())),
    _item(context, 'Reset everything', 'Return Resonate to a clean state', Icons.delete_forever_rounded, () => _info(context, 'Reset everything', 'A full reset will be added only when every persistent provider has a safe reset path.')),
    _divider(),
    _header(context, 'About', 'Resonate', Icons.info_outline_rounded),
    const ListTile(title: Text('Resonate'), subtitle: Text('0.1.0 • Local-first intelligent music player')),
  ]));

  Widget _header(BuildContext c, String title, String subtitle, IconData icon) => Padding(padding: const EdgeInsets.fromLTRB(18, 22, 18, 8), child: Row(children: [Icon(icon, color: Theme.of(c).colorScheme.primary), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(c).textTheme.titleLarge), Text(subtitle, style: Theme.of(c).textTheme.bodySmall)]))]));
  Widget _item(BuildContext c, String title, String subtitle, IconData icon, VoidCallback onTap) => ListTile(leading: Icon(icon), title: Text(title), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right), onTap: onTap);
  Widget _divider() => const Divider(indent: 18, endIndent: 18);
  void _info(BuildContext c, String title, String text) => showModalBottomSheet<void>(context: c, showDragHandle: true, builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(22, 8, 22, 28), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(c).textTheme.headlineSmall), const SizedBox(height: 12), Text(text), const SizedBox(height: 20)]))));
  Future<void> _confirm(BuildContext c, String title, String text, Future<void> Function() action) async { final yes = await showDialog<bool>(context: c, builder: (_) => AlertDialog(title: Text(title), content: Text(text), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continue'))])); if (yes == true) await action(); }
  void _showBluetooth(BuildContext c) => showModalBottomSheet<void>(context: c, showDragHandle: true, builder: (_) => const _BluetoothControls());
}

class _BluetoothControls extends StatelessWidget {
  const _BluetoothControls();
  @override Widget build(BuildContext context) => Consumer<BluetoothProvider>(builder: (_, bt, __) => SafeArea(child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 20), children: [const ListTile(title: Text('Bluetooth & media controls'), subtitle: Text('Android owns the Bluetooth radio. Resonate handles playback and media commands from connected audio devices.')), SwitchListTile(title: const Text('Bluetooth controls'), value: bt.isEnabled, onChanged: bt.toggleBluetooth), SwitchListTile(title: const Text('Playback notification'), value: bt.showNotification, onChanged: bt.toggleNotification), SwitchListTile(title: const Text('Resume when device connects'), value: bt.resumeOnConnect, onChanged: bt.toggleResumeOnConnect), SwitchListTile(title: const Text('Pause when device disconnects'), value: bt.pauseOnDisconnect, onChanged: bt.togglePauseOnDisconnect), ListTile(title: const Text('Media button behavior'), subtitle: Text(bt.getButtonBehaviorDescription(bt.settings.mediaButtonBehavior)), trailing: const Icon(Icons.chevron_right), onTap: () => _chooseBehavior(context, bt))])));
  Future<void> _chooseBehavior(BuildContext context, BluetoothProvider bt) async { final selected = await showDialog<int>(context: context, builder: (_) => SimpleDialog(title: const Text('Media button behavior'), children: [for (final value in [0, 1, 2]) SimpleDialogOption(onPressed: () => Navigator.pop(context, value), child: Text(bt.getButtonBehaviorDescription(value)))])); if (selected != null) await bt.setMediaButtonBehavior(selected); }
}
