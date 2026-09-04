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
  const SettingsScreen({Key? key}) : super(key: key);
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Settings')), body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 32), children: [
    _category(context, 'Playback', 'How Resonate behaves while you listen', Icons.play_circle_outline, [
      _entry('Playback behaviour', 'Play, pause, next and previous', Icons.play_arrow_rounded, () => _info(context, 'Playback behaviour', 'Playback remains controlled by the player. Bluetooth, notifications and Intelligence route commands through the same playback engine.')),
      _entry('Queue', 'View, reorder and remove upcoming songs', Icons.queue_music_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QueueScreen()))),
      _entry('Queue behaviour', 'Anticipation and next-track handling', Icons.playlist_add_rounded, () => _info(context, 'Queue behaviour', 'Your current queue remains authoritative. Intelligence can prepare additions, while you can always inspect and change upcoming tracks.')),
      _entry('Crossfade', 'Duration, curve and transition behavior', Icons.compare_arrows, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CrossfadeScreen()))),
      _entry('Gapless playback', 'Continuous playback between queued tracks', Icons.all_inclusive, () => _info(context, 'Gapless playback', 'Resonate prepares local audio as safely as possible for continuous playback.')),
      _entry('Replay gain / loudness', 'Loudness enhancement and level control', Icons.volume_up_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AudioEffectsScreen()))),
      _entry('Volume behaviour', 'Master volume and output level', Icons.volume_down_rounded, () => _info(context, 'Volume behaviour', 'Resonate keeps the app volume synchronized with its active playback deck.')),
      _entry('Resume behaviour', 'Resume after interruption or reopening', Icons.restore_rounded, () => _info(context, 'Resume behaviour', 'Audio interruptions and becoming-noisy events are handled safely through the audio session.')),
    ]),
    _category(context, 'Audio', 'Sound shaping and output', Icons.equalizer_rounded, [
      _entry('Equalizer', 'Main sound profile', Icons.equalizer, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EqualizerScreen()))),
      _entry('Per-song EQ', 'Individual song profiles', Icons.music_note_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EqualizerScreen()))),
      _entry('Effects', 'Bass, reverb and processing', Icons.tune, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AudioEffectsScreen()))),
      _entry('Audio output', 'Android audio session and device routing', Icons.speaker_rounded, () => _info(context, 'Audio output', 'Android manages the physical output route. Resonate follows the active device route.')),
      _entry('Audio focus', 'Calls, navigation and interruptions', Icons.hearing_rounded, () => _info(context, 'Audio focus', 'Audio focus and becoming-noisy events are handled through the Android audio session.')),
    ]),
    _category(context, 'Intelligence', 'Your local companion and its authority', Icons.auto_awesome, [
      _entry('Master switch & Authority', 'Suggestions, Assist or Autopilot', Icons.auto_awesome, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IntelligenceSettingsScreen()))),
      _entry('Suggestions', 'Recommendations without taking control', Icons.lightbulb_outline, () => _info(context, 'Suggestions', 'Intelligence recommends local songs with a reason and confidence score.')),
      _entry('Automatic queue', 'Prepare likely next tracks', Icons.playlist_add_rounded, () => _info(context, 'Automatic queue', 'Autopilot can prepare high-confidence recommendations near the end of a track.')),
      _entry('Exploration', 'Balance familiar choices with discovery', Icons.explore_outlined, () => _info(context, 'Exploration', 'Exploration stays local and confidence-aware as the recommendation graph matures.')),
      _entry('Explanations', 'See why a recommendation was chosen', Icons.question_mark_rounded, () => _info(context, 'Explanations', 'Predictions carry a human-readable reason and confidence.')),
      _entry('Learning', 'Listening memory and feedback', Icons.insights_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IntelligenceSettingsScreen()))),
      _entry('Session intelligence', 'Understand the direction of the current session', Icons.timeline_rounded, () => _info(context, 'Session intelligence', 'The session layer uses recent listening behavior to understand the direction of the current session.')),
      _entry('Reset Intelligence', 'Clear recommendation feedback and relearn', Icons.restart_alt_rounded, () => _confirm(context, 'Reset Intelligence', 'Clear learned recommendation feedback?', () => context.read<IntelligenceProvider>().clearRecommendationFeedback())),
    ]),
    _category(context, 'Bluetooth & Devices', 'Media buttons and connection behavior', Icons.bluetooth_audio_rounded, [
      _entry('Media buttons', 'Headset and Bluetooth button behavior', Icons.headset_rounded, () => _showBluetooth(context)),
      _entry('Connection behaviour', 'Respond to connected audio devices', Icons.devices_other_rounded, () => _showBluetooth(context)),
      _entry('Resume on connect', 'Continue when a device connects', Icons.play_arrow_rounded, () => _showBluetooth(context)),
      _entry('Pause on disconnect', 'Pause when an audio route disappears', Icons.pause_circle_outline, () => _showBluetooth(context)),
      _entry('Device behaviour', 'Android route and media controls', Icons.settings_input_component_rounded, () => _showBluetooth(context)),
    ]),
    _category(context, 'Library', 'Find, scan and manage your local music', Icons.library_music_rounded, [
      _entry('Liked Songs', 'Your personal collection of favorites', Icons.favorite_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LikedSongsScreen()))),
      _entry('Playlists', 'Create and manage personal & smart playlists', Icons.queue_music_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlaylistsScreen()))),
      _entry('Scan & folders', 'Scan now or choose folders to include', Icons.folder_open_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryManagementScreen()))),
      _entry('Metadata', 'Song and artist information', Icons.text_fields_rounded, () => _info(context, 'Metadata', 'Library metadata remains local to the device.')),
      _entry('Artwork', 'Album artwork handling', Icons.image_outlined, () => _info(context, 'Artwork', 'Artwork is kept as local media metadata where available.')),
      _entry('Library exclusions', 'Keep folders out of scanning', Icons.block_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryManagementScreen()))),
    ]),
    _category(context, 'Appearance', 'Make Resonate feel like yours', Icons.palette_outlined, [
      _entry('Theme', 'Light, dark and system appearance', Icons.brightness_6_outlined, () => _showTheme(context)),
      _entry('Visualization', 'Audio spectrum & waveform display', Icons.graphic_eq_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AudioVisualizationSettingsScreen()))),
      _entry('Accent', 'Resonate violet accent', Icons.color_lens_outlined, () => _info(context, 'Accent', 'Resonate currently uses a violet accent with theme-aware contrast.')),
      _entry('Player layout', 'Player presentation and controls', Icons.dashboard_customize_outlined, () => _info(context, 'Player layout', 'Player layout remains stable while Intelligence features are layered around it.')),
      _entry('Artwork style', 'Album-art presentation', Icons.album_outlined, () => _info(context, 'Artwork style', 'Artwork styling remains compatible with the existing player.')),
      _entry('Animations', 'Motion and transition feel', Icons.animation_rounded, () => _info(context, 'Animations', 'Resonate keeps lightweight UI motion and the polished player action animation.')),
      _entry('Compact/full controls', 'Playback control density', Icons.view_agenda_outlined, () => _info(context, 'Compact/full controls', 'Control density remains part of the player presentation layer.')),
    ]),
    _category(context, 'Privacy', 'Keep your listening data yours', Icons.lock_outline_rounded, [
      _entry('Local-only learning', 'No cloud recommendation profile required', Icons.phone_android_rounded, () => _info(context, 'Local-only learning', 'Intelligence uses local listening events and on-device recommendation logic.')),
      _entry('Listening history', 'Browse, understand or clear playback events', Icons.history_rounded, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ListeningHistoryScreen()))),
      _entry('Export Intelligence data', 'Export learned signals', Icons.ios_share_rounded, () => _info(context, 'Export Intelligence data', 'Portable local export is planned.')),
      _entry('Delete Intelligence history', 'Erase listening-learning history', Icons.delete_outline_rounded, () => _confirm(context, 'Delete Intelligence history', 'Clear recommendation feedback now?', () => context.read<IntelligenceProvider>().clearRecommendationFeedback())),
      _entry('Reset everything', 'Return Resonate to a clean state', Icons.delete_forever_rounded, () => _info(context, 'Reset everything', 'A full reset will be added when every persistent provider has a safe reset path.')),
    ]),
    _category(context, 'About', 'Resonate • Aetherion', Icons.info_outline_rounded, [_entry('About & How to use', 'Guide, privacy notes and copyright', Icons.menu_book_outlined, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen())))])
  ]));
  static _SettingEntry _entry(String title,String subtitle,IconData icon,VoidCallback onTap)=>_SettingEntry(title,subtitle,icon,onTap);
  Widget _category(BuildContext context,String title,String subtitle,IconData icon,List<_SettingEntry> entries)=>Card(margin:const EdgeInsets.only(bottom:10),child:ExpansionTile(leading:Icon(icon,color:Theme.of(context).colorScheme.primary),title:Text(title,style:Theme.of(context).textTheme.titleMedium),subtitle:Text(subtitle),children:[for(final entry in entries)ListTile(contentPadding:const EdgeInsets.only(left:24,right:16),leading:Icon(entry.icon),title:Text(entry.title),subtitle:Text(entry.subtitle),trailing:const Icon(Icons.chevron_right),onTap:entry.onTap)]));
  Future<void> _showTheme(BuildContext context)async{await showModalBottomSheet<void>(context:context,showDragHandle:true,builder:(sheet)=>Consumer<ThemeProvider>(builder:(_,theme,__)= >SafeArea(child:ListView(shrinkWrap:true,children:[RadioListTile<String>(title:const Text('System'),value:'system',groupValue:theme.useSystemTheme?'system':(theme.isDarkMode?'dark':'light'),onChanged:(_)=>theme.toggleSystemTheme(true)),RadioListTile<String>(title:const Text('Light'),value:'light',groupValue:theme.useSystemTheme?'system':(theme.isDarkMode?'dark':'light'),onChanged:(_)async{if(theme.useSystemTheme)await theme.toggleSystemTheme(false);if(theme.isDarkMode)await theme.toggleTheme();}),RadioListTile<String>(title:const Text('Dark'),value:'dark',groupValue:theme.useSystemTheme?'system':(theme.isDarkMode?'dark':'light'),onChanged:(_)async{if(theme.useSystemTheme)await theme.toggleSystemTheme(false);if(!theme.isDarkMode)await theme.toggleTheme();})]))));}
  void _info(BuildContext c,String title,String text)=>showModalBottomSheet<void>(context:c,showDragHandle:true,builder:(sheetContext)=>SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(22,8,22,28),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:Theme.of(sheetContext).textTheme.headlineSmall),const SizedBox(height:12),Text(text,style:Theme.of(sheetContext).textTheme.bodyLarge)]))));
  Future<void> _confirm(BuildContext c,String title,String text,Future<void> Function() action)async{final yes=await showDialog<bool>(context:c,builder:(dialogContext)=>AlertDialog(title:Text(title),content:Text(text),actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Continue'))]));if(yes==true)await action();}
  void _showBluetooth(BuildContext c)=>showModalBottomSheet<void>(context:c,showDragHandle:true,builder:(_)=>const _BluetoothControls());
}
class _SettingEntry{final String title,subtitle;final IconData icon;final VoidCallback onTap;const _SettingEntry(this.title,this.subtitle,this.icon,this.onTap);}
class _BluetoothControls extends StatelessWidget{const _BluetoothControls();@override Widget build(BuildContext context)=>Consumer<BluetoothProvider>(builder:(_,bt,__)= >SafeArea(child:ListView(shrinkWrap:true,padding:const EdgeInsets.only(bottom:20),children:[ListTile(title:Text('Bluetooth & media controls',style:Theme.of(context).textTheme.titleLarge),subtitle:Text('Android owns the Bluetooth radio. Resonate handles playback and media commands from connected audio devices.')),SwitchListTile(title:const Text('Bluetooth controls'),value:bt.isEnabled,onChanged:bt.toggleBluetooth),SwitchListTile(title:const Text('Playback notification'),value:bt.showNotification,onChanged:bt.toggleNotification),SwitchListTile(title:const Text('Resume when device connects'),value:bt.resumeOnConnect,onChanged:bt.toggleResumeOnConnect),SwitchListTile(title:const Text('Pause when device disconnects'),value:bt.pauseOnDisconnect,onChanged:bt.togglePauseOnDisconnect),ListTile(title:const Text('Media button behavior'),subtitle:Text(bt.getButtonBehaviorDescription(bt.settings.mediaButtonBehavior)),trailing:const Icon(Icons.chevron_right),onTap:()=>_chooseBehavior(context,bt))])));
  Future<void> _chooseBehavior(BuildContext context,BluetoothProvider bt)async{final selected=await showDialog<int>(context:context,builder:(dialogContext)=>SimpleDialog(title:const Text('Media button behavior'),children:[for(final value in[0,1,2])SimpleDialogOption(onPressed:()=>Navigator.pop(dialogContext,value),child:Text(bt.getButtonBehaviorDescription(value)))]));if(selected!=null)await bt.setMediaButtonBehavior(selected);}
}
