from pathlib import Path

p=Path('lib/providers/music_provider.dart')
s=p.read_text()
old='''    // Every mutation of either native AudioPlayer goes through one FIFO lane.\n    // The intent gate still makes stale work harmless at its checkpoints, but\n    // the native player itself is never mutated concurrently by two callers.\n    await ResonateDiagnostics.record('playback_operation_queued', {\n      'command': command,\n      'source': source,\n      'userInitiated': userInitiated,\n      'intentToken': effectiveIntent,\n    });\n    final next = _playOperation.then((_) => operation());\n    _playOperation = next.then<void>((_) {}, onError: (_, __) {});\n    return next;'''
new='''    // Transport controls must not wait behind a source load. Source-changing\n    // operations remain serialized to protect just_audio's native player.\n    await ResonateDiagnostics.record('playback_operation_queued', {\n      'command': command,\n      'source': source,\n      'userInitiated': userInitiated,\n      'intentToken': effectiveIntent,\n      'lane': userInitiated && const {'toggle', 'pause', 'seek'}.contains(command) && audioPlayer.audioSource != null\n          ? 'transport_priority'\n          : 'source_serialized',\n    });\n    if (userInitiated && const {'toggle', 'pause', 'seek'}.contains(command) && audioPlayer.audioSource != null) {\n      return operation();\n    }\n    final next = _playOperation.then((_) => operation());\n    _playOperation = next.then<void>((_) {}, onError: (_, __) {});\n    return next;'''
if old not in s: raise SystemExit('music serialization block not found')
s=s.replace(old,new,1)
if "package:flutter/services.dart" not in s: s=s.replace("import 'package:flutter/foundation.dart';\n", "import 'package:flutter/foundation.dart';\nimport 'package:flutter/services.dart';\n", 1)
marker="  static const _resumeSongIdKey = 'playback_resume_song_id';\n"
if marker in s and "_systemVolumeChannel" not in s: s=s.replace(marker,"  static const _resumeSongIdKey = 'playback_resume_song_id';\n  static const MethodChannel _systemVolumeChannel = MethodChannel('com.example.resonate/media_store');\n",1)
needle="      _resumeSongId = prefs.getString(_resumeSongIdKey);\n"
if needle in s and "await _syncSystemVolume();" not in s: s=s.replace(needle,needle+"      await _syncSystemVolume();\n",1)
old_vol="  Future<void> setVolume(double volume) async { _volume = volume.clamp(0.0, 1.0).toDouble(); try { await audioPlayer.setVolume(_volume); if (!inactivePlayer.playing) await inactivePlayer.setVolume(_volume); notifyListeners(); } catch (_) {} }"
new_vol="""  Future<void> _syncSystemVolume() async {\n    try {\n      final raw = await _systemVolumeChannel.invokeMethod<dynamic>('getSystemVolume');\n      if (raw is Map) {\n        final current = (raw['current'] as num?)?.toDouble() ?? 0;\n        final max = (raw['max'] as num?)?.toDouble() ?? 0;\n        if (max > 0) { _volume = (current / max).clamp(0.0, 1.0).toDouble(); notifyListeners(); }\n      }\n    } catch (_) {}\n  }\n\n  Future<void> setVolume(double volume) async {\n    _volume = volume.clamp(0.0, 1.0).toDouble();\n    try {\n      await _systemVolumeChannel.invokeMethod('setSystemVolume', {'value': _volume});\n      await audioPlayer.setVolume(1.0);\n      await inactivePlayer.setVolume(1.0);\n    } catch (_) {}\n    notifyListeners();\n  }"""
if old_vol not in s: raise SystemExit('setVolume block not found')
s=s.replace(old_vol,new_vol,1)
p.write_text(s)

p=Path('android/app/src/main/kotlin/com/example/resonate/MainActivity.kt')
s=p.read_text()
if 'import android.media.AudioManager' not in s: s=s.replace('import android.media.audiofx.BassBoost\n','import android.media.AudioManager\nimport android.media.audiofx.BassBoost\n',1)
needle='''                "requestNotificationPermission" -> requestNotificationPermission(result)\n                "pickFolder" -> pickFolder(result)'''
repl='''                "requestNotificationPermission" -> requestNotificationPermission(result)\n                "getSystemVolume" -> getSystemVolume(result)\n                "setSystemVolume" -> setSystemVolume(call.argument<Double>("value") ?: 1.0, result)\n                "pickFolder" -> pickFolder(result)'''
if needle in s and '"getSystemVolume"' not in s: s=s.replace(needle,repl,1)
insert='''    private fun pickFolder(result: MethodChannel.Result) {'''
methods='''    private fun getSystemVolume(result: MethodChannel.Result) {\n        try { val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager; result.success(mapOf("current" to audioManager.getStreamVolume(AudioManager.STREAM_MUSIC), "max" to audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC))) }\n        catch (e: Exception) { result.error("SYSTEM_VOLUME_ERROR", e.message, null) }\n    }\n\n    private fun setSystemVolume(value: Double, result: MethodChannel.Result) {\n        try { val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager; val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC); audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, (value.coerceIn(0.0,1.0)*max).roundToInt(), 0); result.success(true) }\n        catch (e: Exception) { result.error("SYSTEM_VOLUME_ERROR", e.message, null) }\n    }\n\n'''
if insert in s and 'private fun getSystemVolume' not in s: s=s.replace(insert,methods+insert,1)
if 'import kotlin.math.roundToInt' not in s: s=s.replace('import io.flutter.plugin.common.MethodChannel\n','import io.flutter.plugin.common.MethodChannel\nimport kotlin.math.roundToInt\n',1)
p.write_text(s)

p=Path('lib/providers/listening_history_provider.dart')
s=p.read_text()
if "import 'dart:async';" not in s: s=s.replace("import 'package:flutter/foundation.dart';\n","import 'dart:async';\nimport 'package:flutter/foundation.dart';\n",1)
if 'Timer? _refreshTimer;' not in s: s=s.replace('  bool _loading = false;\n','  bool _loading = false;\n  Timer? _refreshTimer;\n',1)
s=s.replace('  ListeningHistoryProvider() { load(); }',"  ListeningHistoryProvider() { load(); _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) { if (!_loading) load(); }); }")
if 'void dispose()' not in s: s=s.replace('\n}\n','\n  @override\n  void dispose() { _refreshTimer?.cancel(); super.dispose(); }\n}\n',1)
p.write_text(s)

p=Path('lib/screens/player_screen.dart')
s=p.read_text().replace("duration: const Duration(milliseconds: 1800)","duration: const Duration(milliseconds: 3200)").replace("const Duration(milliseconds: 500)","const Duration(milliseconds: 900)",1)
s=s.replace('class _WaveSeekBar extends StatelessWidget {','class _WaveSeekBar extends StatefulWidget {',1)
start=s.find('class _WaveSeekBar extends StatefulWidget {'); end=s.find('\nclass _WaveSeekPainter',start)
if start<0 or end<0: raise SystemExit('wave bounds not found')
widget='''class _WaveSeekBar extends StatefulWidget {\n  final double value; final double max; final ValueChanged<double> onStart; final ValueChanged<double> onUpdate; final ValueChanged<double> onEnd;\n  const _WaveSeekBar({required this.value, required this.max, required this.onStart, required this.onUpdate, required this.onEnd});\n  @override State<_WaveSeekBar> createState() => _WaveSeekBarState();\n}\nclass _WaveSeekBarState extends State<_WaveSeekBar> {\n  double? _interactionValue;\n  double _valueFor(Offset local, double width) => width <= 0 ? 0 : (local.dx / width).clamp(0.0,1.0) * widget.max;\n  @override Widget build(BuildContext context) => LayoutBuilder(builder:(context,constraints){ final display=_interactionValue ?? widget.value; return GestureDetector(behavior:HitTestBehavior.opaque, onHorizontalDragStart:(d){final v=_valueFor(d.localPosition,constraints.maxWidth);setState(()=>_interactionValue=v);widget.onStart(v);}, onHorizontalDragUpdate:(d){final v=_valueFor(d.localPosition,constraints.maxWidth);setState(()=>_interactionValue=v);widget.onUpdate(v);}, onHorizontalDragEnd:(_){final v=_interactionValue ?? widget.value;setState(()=>_interactionValue=null);widget.onEnd(v);}, onTapDown:(d){final v=_valueFor(d.localPosition,constraints.maxWidth);setState(()=>_interactionValue=v);widget.onStart(v);}, onTapUp:(d){final v=_valueFor(d.localPosition,constraints.maxWidth);setState(()=>_interactionValue=null);widget.onEnd(v);}, child:SizedBox(height:64,child:CustomPaint(painter:_WaveSeekPainter(progress:widget.max<=0?0:display/widget.max,color:Theme.of(context).colorScheme.primary,muted:Theme.of(context).colorScheme.outlineVariant)))); });\n}\n'''
s=s[:start]+widget+s[end:]
old='''              Consumer<IntelligenceProvider>(\n                builder: (context, intelligence, _) {'''
if old in s and 'const AutopilotTakeoverCard(),\n              const SizedBox(height: 10),\n              Consumer<IntelligenceProvider>' not in s: s=s.replace(old,'              const AutopilotTakeoverCard(),\n              const SizedBox(height: 10),\n'+old,1)
s=s.replace('''              const SizedBox(height: 14),\n              const SizedBox(height: 8),\n              const AutopilotTakeoverCard(),\n''','''              const SizedBox(height: 14),\n''',1)
old='''              SwitchListTile(\n                secondary: const Icon(Icons.volume_down_rounded),\n                title: const Text('Volume normalization'),\n                subtitle: Text(\n                  'Target ${playback.targetLoudness.toStringAsFixed(0)} LUFS • track gain when available',\n                ),\n                value: playback.normalizationEnabled,\n                onChanged: playback.setNormalizationEnabled,\n              ),'''
new='''              Consumer<PlaybackFeaturesProvider>(builder: (_, current, __) => SwitchListTile(secondary: const Icon(Icons.volume_down_rounded), title: const Text('Volume normalization'), subtitle: Text('Target ${current.targetLoudness.toStringAsFixed(0)} LUFS • track gain when available'), value: current.normalizationEnabled, onChanged: current.setNormalizationEnabled)),'''
if old not in s: raise SystemExit('normalization switch not found')
s=s.replace(old,new,1)
p.write_text(s)

p=Path('lib/screens/home_screen.dart')
s=p.read_text()
old='''      child: Column(\n        crossAxisAlignment: CrossAxisAlignment.start,\n        children: ['''
new='''      child: Stack(children: [\n        Positioned(right: -8, bottom: 4, child: IgnorePointer(child: Opacity(opacity: .07, child: Text('RESONATE', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, letterSpacing: 3))))),\n        Column(crossAxisAlignment: CrossAxisAlignment.start, children: ['''
if old not in s: raise SystemExit('hero column not found')
s=s.replace(old,new,1)
s=s.replace('''              Icon(\n                intelligence.isAutopilot\n                    ? Icons.smart_toy_rounded\n                    : Icons.auto_awesome,\n              ),''','''              AnimatedSwitcher(duration: const Duration(milliseconds: 420), transitionBuilder: (child, animation) => RotationTransition(turns: Tween(begin: .88, end: 1.0).animate(animation), child: FadeTransition(opacity: animation, child: child)), child: Icon(intelligence.isAutopilot ? Icons.smart_toy_rounded : Icons.auto_awesome, key: ValueKey(intelligence.autonomyLabel))),''',1)
p.write_text(s)

p=Path('lib/screens/intelligence_settings_screen.dart')
s=p.read_text().replace('  bool _crossfade = true;','  bool _crossfade = false;',1)
p.write_text(s)
print('repair patch applied')
