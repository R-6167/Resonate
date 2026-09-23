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
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF9A7BFF),
    brightness: brightness,
    surface: dark ? const Color(0xFF101016) : const Color(0xFFF8F7FC),
    surfaceContainerLowest: dark ? const Color(0xFF0A0A0F) : Colors.white,
    surfaceContainerLow: dark ? const Color(0xFF15151D) : const Color(0xFFF1EFF7),
    surfaceContainer: dark ? const Color(0xFF1B1A23) : const Color(0xFFECEAF3),
  );
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final onSurface = scheme.onSurface;
  final muted = scheme.onSurfaceVariant;
  final text = base.textTheme.copyWith(
    displaySmall: base.textTheme.displaySmall?.copyWith(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.8,
      color: onSurface,
    ),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      color: onSurface,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: onSurface,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: onSurface,
    ),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(
      fontSize: 16,
      height: 1.35,
      color: onSurface,
    ),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      height: 1.35,
      color: muted,
    ),
    bodySmall: base.textTheme.bodySmall?.copyWith(
      fontSize: 12,
      height: 1.3,
      color: muted,
    ),
    labelLarge: base.textTheme.labelLarge?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: onSurface,
    ),
  );
  return base.copyWith(
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(text.labelLarge),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final audioHandler = await AudioService.init(
    builder: () => AudioServiceHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.aetherion.resonate.audio',
      androidNotificationChannelName: 'Resonate Playback',
      // audio_service asserts: ongoing must be false when stopForegroundOnPause is false.
      androidNotificationOngoing: false,
      // Keep the media session / notification while paused so play-pause stays real-time.
      androidStopForegroundOnPause: false,
      androidNotificationChannelDescription: 'Now playing and transport controls',
      fastForwardInterval: Duration(seconds: 10),
      rewindInterval: Duration(seconds: 10),
      // Must be a real bitmap (PNG) resource. audio_service defaults to
      // mipmap/ic_launcher which this project did not ship; Unisoc/HMD then
      // posts a FGS notification with icon=0 and crashes MainActivity on
      // first play (IllegalArgumentException: no valid small icon) while
      // ExoPlayer has already started — "Resonate keeps stopping".
      // A vector drawable is also rejected as a small icon on this OEM.
      androidNotificationIcon: 'drawable/ic_stat_resonate',
    ),
  );

  await ResonateDiagnostics.record('app_started', {});

  runApp(ResonateApp(audioHandler: audioHandler));
}

class ResonateApp extends StatelessWidget {
  final AudioHandler audioHandler;

  const ResonateApp({super.key, required this.audioHandler});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(
          create: (_) => MusicProvider(audioHandler: audioHandler),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              IntelligenceProvider(music: context.read<MusicProvider>()),
        ),
        ChangeNotifierProvider(
          create: (context) => IntelligenceMixController(
            music: context.read<MusicProvider>(),
            intelligence: context.read<IntelligenceProvider>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              PlaybackDiagnosticsObserver(music: context.read<MusicProvider>()),
        ),
        ChangeNotifierProvider(
          create: (context) => AutopilotController(
            music: context.read<MusicProvider>(),
            intelligence: context.read<IntelligenceProvider>(),
          ),
        ),
        // Bluetooth before Equalizer so EQ can bind device profiles.
        ChangeNotifierProvider(create: (_) => BluetoothProvider()),
        ChangeNotifierProvider(
          create: (context) => EqualizerProvider(
            equalizer: context.read<MusicProvider>().equalizer,
            loudnessEnhancer: context.read<MusicProvider>().loudnessEnhancer,
            music: context.read<MusicProvider>(),
            bluetooth: context.read<BluetoothProvider>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => AudioEffectsProvider(
            player: context.read<MusicProvider>().audioPlayer,
            loudnessEnhancer: context.read<MusicProvider>().loudnessEnhancer,
          ),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              CrossfadeProvider(music: context.read<MusicProvider>()),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              PlaybackFeaturesProvider(music: context.read<MusicProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => AudioVisualizationProvider()),
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
        ChangeNotifierProvider(create: (_) => PlaylistProvider()),
        ChangeNotifierProvider(create: (_) => ListeningHistoryProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          title: 'Resonate',
          debugShowCheckedModeBanner: false,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          themeMode: themeProvider.useSystemTheme
              ? ThemeMode.system
              : (themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light),
          home: const _LifecycleHome(),
        ),
      ),
    );
  }
}

/// Persists resume position when the app is backgrounded or detached.
class _LifecycleHome extends StatefulWidget {
  const _LifecycleHome();

  @override
  State<_LifecycleHome> createState() => _LifecycleHomeState();
}

class _LifecycleHomeState extends State<_LifecycleHome>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      try {
        context.read<MusicProvider>().onAppBackgrounded();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) => const HomeScreen();
}
