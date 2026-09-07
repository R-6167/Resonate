import 'dart:ui' as ui;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/audio_effects_provider.dart';
import 'providers/audio_visualization_provider.dart';
import 'providers/autopilot_controller.dart';
import 'providers/bluetooth_provider.dart';
import 'providers/crossfade_provider.dart';
import 'providers/equalizer_provider.dart';
import 'providers/intelligence_provider.dart';
import 'providers/intelligence_mix_controller.dart';
import 'providers/library_provider.dart';
import 'providers/listening_history_provider.dart';
import 'providers/music_provider.dart';
import 'providers/playback_features_provider.dart';
import 'providers/playlist_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'services/audio_service_handler.dart';
import 'services/playback_diagnostics_observer.dart';
import 'services/resonate_diagnostics.dart';

ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF9A7BFF), brightness: brightness, surface: dark ? const Color(0xFF101016) : const Color(0xFFF8F7FC), surfaceContainerLowest: dark ? const Color(0xFF0A0A0F) : Colors.white, surfaceContainerLow: dark ? const Color(0xFF15151D) : const Color(0xFFF1EFF7), surfaceContainer: dark ? const Color(0xFF1B1A23) : const Color(0xFFECEAF3));
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final onSurface = scheme.onSurface;
  final muted = scheme.onSurfaceVariant;
  final text = base.textTheme.copyWith(
    displaySmall: base.textTheme.displaySmall?.copyWith(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.8, color: onSurface),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: onSurface),
    titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w700, color: onSurface),
    titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600, color: onSurface),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.35, color: onSurface),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.35, color: muted),
    bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.3, color: muted),
    labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: onSurface),
    labelMedium: base.textTheme.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: muted),
    labelSmall: base.textTheme.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w600, color: muted),
  );
  return base.copyWith(colorScheme: scheme, scaffoldBackgroundColor: scheme.surface, canvasColor: scheme.surface, textTheme: text, appBarTheme: AppBarTheme(backgroundColor: scheme.surface, foregroundColor: onSurface, elevation: 0, centerTitle: false, titleTextStyle: text.titleLarge), navigationBarTheme: NavigationBarThemeData(backgroundColor: scheme.surfaceContainerLow, indicatorColor: scheme.primaryContainer, elevation: 0, labelTextStyle: WidgetStatePropertyAll(text.labelMedium)), listTileTheme: ListTileThemeData(iconColor: scheme.onSurfaceVariant, titleTextStyle: text.titleMedium, subtitleTextStyle: text.bodyMedium), cardTheme: CardThemeData(margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 5), color: scheme.surfaceContainerLow, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 0), bottomSheetTheme: BottomSheetThemeData(backgroundColor: scheme.surfaceContainer, modalBackgroundColor: scheme.surfaceContainer, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))), showDragHandle: true), dialogTheme: DialogThemeData(backgroundColor: scheme.surfaceContainer, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)), elevation: 20), inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: scheme.surfaceContainerLow, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(.55))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.primary, width: 1.5)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)), dividerTheme: DividerThemeData(color: scheme.outlineVariant.withOpacity(.45), thickness: 1, space: 1), chipTheme: base.chipTheme.copyWith(backgroundColor: scheme.surfaceContainerLow, selectedColor: scheme.secondaryContainer, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), side: BorderSide(color: scheme.outlineVariant.withOpacity(.45))), sliderTheme: base.sliderTheme.copyWith(trackHeight: 4, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7), overlayShape: const RoundSliderOverlayShape(overlayRadius: 18)), switchTheme: SwitchThemeData(thumbIcon: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? const Icon(Icons.check, size: 15) : const Icon(Icons.remove, size: 15))), iconTheme: IconThemeData(color: scheme.onSurfaceVariant));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) { ResonateDiagnostics.recordCrash(details.exception, details.stack ?? StackTrace.current, source: 'FlutterError'); FlutterError.presentError(details); };
  ui.PlatformDispatcher.instance.onError = (error, stack) { ResonateDiagnostics.recordCrash(error, stack, source: 'PlatformDispatcher'); return true; };
  await ResonateDiagnostics.record('app_started');
  runApp(const ResonateBootstrap());
}

class ResonateBootstrap extends StatefulWidget { const ResonateBootstrap({super.key}); @override State<ResonateBootstrap> createState() => _ResonateBootstrapState(); }
class _ResonateBootstrapState extends State<ResonateBootstrap> {
  AudioHandler? _audioHandler; Object? _startupError;
  @override void initState() { super.initState(); _initializeAudioService(); }
  Future<void> _initializeAudioService() async {
    try {
      final handler = await AudioService.init(builder: () => AudioServiceHandler(), config: const AudioServiceConfig(androidNotificationChannelId: 'com.Aetherion.Resonate.audio', androidNotificationChannelName: 'Resonate Playback', androidNotificationChannelDescription: 'Playback controls, current song and album artwork for Resonate.', notificationColor: Color(0xFF9A7BFF), androidNotificationIcon: 'drawable/ic_stat_resonate', androidNotificationOngoing: true, androidStopForegroundOnPause: true, androidShowNotificationBadge: false, androidResumeOnClick: true, androidNotificationClickStartsActivity: true, fastForwardInterval: Duration(seconds: 10), rewindInterval: Duration(seconds: 10), artDownscaleWidth: 512, artDownscaleHeight: 512)).timeout(const Duration(seconds: 10));
      try { await const MethodChannel('com.example.resonate/media_store').invokeMethod<bool>('requestNotificationPermission'); } catch (_) {}
      if (!mounted) return; setState(() => _audioHandler = handler);
    } catch (e, stack) { await ResonateDiagnostics.recordCrash(e, stack, source: 'AudioService startup'); if (!mounted) return; setState(() => _startupError = e); }
  }
  @override Widget build(BuildContext context) {
    final handler = _audioHandler;
    if (handler == null) return MaterialApp(title: 'Resonate', debugShowCheckedModeBanner: false, theme: _theme(Brightness.light), darkTheme: _theme(Brightness.dark), home: Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(28), child: _startupError == null ? Column(mainAxisSize: MainAxisSize.min, children: [const _ResonateLogo(size: 92), const SizedBox(height: 28), Text('Resonate', style: Theme.of(context).textTheme.displaySmall), const SizedBox(height: 8), Text('Tuning into your library…', style: Theme.of(context).textTheme.bodyMedium), const SizedBox(height: 28), const SizedBox(width: 180, child: LinearProgressIndicator(minHeight: 3)), const SizedBox(height: 14), Text('Preparing your listening space', style: Theme.of(context).textTheme.bodySmall)]) : Column(mainAxisSize: MainAxisSize.min, children: [const _ResonateLogo(size: 72), const SizedBox(height: 20), const Icon(Icons.warning_amber_rounded, size: 44), const SizedBox(height: 12), const Text('Audio service could not start.', textAlign: TextAlign.center), const SizedBox(height: 8), Text('Resonate startup timed out or failed.\n$_startupError', textAlign: TextAlign.center), const SizedBox(height: 20), FilledButton(onPressed: () { setState(() => _startupError = null); _initializeAudioService(); }, child: const Text('Retry'))])))));
    return ResonateApp(audioHandler: handler);
  }
}

class _ResonateLogo extends StatelessWidget {
  final double size;
  const _ResonateLogo({required this.size});
  @override Widget build(BuildContext context) => Container(width: size, height: size, decoration: BoxDecoration(borderRadius: BorderRadius.circular(size * .27), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFB9A2FF), Color(0xFF7657E8)]), boxShadow: [BoxShadow(blurRadius: 28, spreadRadius: 2, color: Color(0x337657E8))]), child: CustomPaint(painter: _ResonateLogoPainter()));
}

class _ResonateLogoPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = size.width * .075..strokeCap = StrokeCap.round;
    final center = Offset(size.width * .45, size.height * .5);
    final radius = size.width * .22;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -mathPi * .78, mathPi * 1.56, false, paint);
    final inner = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = size.width * .075..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius * .58), -mathPi * .70, mathPi * 1.40, false, inner);
    canvas.drawCircle(Offset(size.width * .45, size.height * .5), size.width * .055, Paint()..color = Colors.white);
  }
  @override bool shouldRepaint(covariant _ResonateLogoPainter oldDelegate) => false;
}
const double mathPi = 3.141592653589793;

class ResonateApp extends StatelessWidget {
  final AudioHandler audioHandler; const ResonateApp({super.key, required this.audioHandler});
  @override Widget build(BuildContext context) => MultiProvider(providers: [
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
    ChangeNotifierProvider(create: (_) => MusicProvider(audioHandler: audioHandler)),
    ChangeNotifierProvider(create: (context) => IntelligenceProvider(music: context.read<MusicProvider>())),
    ChangeNotifierProvider(create: (context) => IntelligenceMixController(music: context.read<MusicProvider>(), intelligence: context.read<IntelligenceProvider>())),
    ChangeNotifierProvider(create: (context) => PlaybackDiagnosticsObserver(music: context.read<MusicProvider>())),
    ChangeNotifierProvider(create: (context) => AutopilotController(music: context.read<MusicProvider>(), intelligence: context.read<IntelligenceProvider>())),
    ChangeNotifierProvider(create: (_) => BluetoothProvider()),
    ChangeNotifierProvider(create: (context) => EqualizerProvider(equalizer: context.read<MusicProvider>().equalizer)),
    ChangeNotifierProvider(create: (context) => AudioEffectsProvider(player: context.read<MusicProvider>().audioPlayer, loudnessEnhancer: context.read<MusicProvider>().loudnessEnhancer)),
    ChangeNotifierProvider(create: (context) => CrossfadeProvider(music: context.read<MusicProvider>())),
    ChangeNotifierProvider(create: (context) => PlaybackFeaturesProvider(music: context.read<MusicProvider>())),
    ChangeNotifierProvider(create: (_) => AudioVisualizationProvider()),
    ChangeNotifierProvider(create: (_) => LibraryProvider()),
    ChangeNotifierProvider(create: (_) => PlaylistProvider()),
    ChangeNotifierProvider(create: (_) => ListeningHistoryProvider()),
  ], child: Consumer<ThemeProvider>(builder: (context, themeProvider, _) => MaterialApp(title: 'Resonate', debugShowCheckedModeBanner: false, theme: _theme(Brightness.light), darkTheme: _theme(Brightness.dark), themeMode: themeProvider.useSystemTheme ? ThemeMode.system : (themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light), home: const HomeScreen())));
}
