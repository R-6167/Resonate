import 'dart:async';
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
import 'providers/dj_mode_provider.dart';
import 'providers/equalizer_provider.dart';
import 'providers/intelligence_provider.dart';
import 'providers/intelligence_mix_controller.dart';
import 'providers/library_provider.dart';
import 'providers/listening_history_provider.dart';
import 'providers/music_provider.dart';
import 'modes/providers/mode_provider.dart';
import 'modes/integration/resonate_mode_ports.dart';
import 'modes/integration/resonate_motion_port.dart';
import 'modes/models/running_intent.dart';
import 'providers/playback_features_provider.dart';
import 'providers/playlist_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'services/audio_service_handler.dart';
import 'services/playback_diagnostics_observer.dart';
import 'services/resonate_diagnostics.dart';

/// Brand spectrum from the Resonate mark: cyan-blue → violet → pink → orange.
class ResonateBrand {
  static const blue = Color(0xFF3D9EFF);
  static const violet = Color(0xFF9A5CFF);
  static const pink = Color(0xFFFF4DB8);
  static const orange = Color(0xFFFF8A3D);
  static const night = Color(0xFF050510);
  static const mist = Color(0xFFF5F2FF);
}

ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final seed = dark ? ResonateBrand.violet : ResonateBrand.blue;

  var scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );

  // Pin the spectrum so UI stays true to the logo, not only seed-derived hues.
  scheme = scheme.copyWith(
    primary: dark ? const Color(0xFFB29BFF) : const Color(0xFF6B4EFF),
    onPrimary: Colors.white,
    primaryContainer: dark ? const Color(0xFF2A1F4D) : const Color(0xFFE8E0FF),
    onPrimaryContainer: dark ? const Color(0xFFE6DEFF) : const Color(0xFF2A1468),
    secondary: dark ? const Color(0xFFFF7AC8) : const Color(0xFFE91E8C),
    onSecondary: Colors.white,
    secondaryContainer: dark ? const Color(0xFF4A1838) : const Color(0xFFFFD6EC),
    onSecondaryContainer: dark ? const Color(0xFFFFD6EC) : const Color(0xFF5C0A3A),
    tertiary: ResonateBrand.orange,
    onTertiary: Colors.white,
    tertiaryContainer: dark ? const Color(0xFF4A2E14) : const Color(0xFFFFE4CC),
    onTertiaryContainer: dark ? const Color(0xFFFFE4CC) : const Color(0xFF4A2200),
    surface: dark ? const Color(0xFF0C0C14) : ResonateBrand.mist,
    surfaceContainerLowest: dark ? ResonateBrand.night : Colors.white,
    surfaceContainerLow: dark ? const Color(0xFF14141E) : const Color(0xFFEEEAFF),
    surfaceContainer: dark ? const Color(0xFF1A1A26) : const Color(0xFFE6E0F7),
    surfaceContainerHigh: dark ? const Color(0xFF222230) : const Color(0xFFDDD5F2),
    surfaceContainerHighest: dark ? const Color(0xFF2A2A3A) : const Color(0xFFD4CAED),
    outline: dark ? const Color(0xFF5A5670) : const Color(0xFF9B92B8),
    outlineVariant: dark ? const Color(0xFF3A3650) : const Color(0xFFCDC4E4),
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

  final radius = BorderRadius.circular(18);

  return base.copyWith(
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface.withValues(alpha: 0.92),
      foregroundColor: onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: scheme.surface,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: scheme.surface,
            ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(text.labelLarge),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: scheme.primary, size: 24);
        }
        return IconThemeData(color: muted, size: 24);
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.secondary,
      foregroundColor: scheme.onSecondary,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      selectedColor: scheme.primaryContainer,
      labelStyle: text.labelLarge?.copyWith(fontSize: 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return scheme.onPrimary;
        return scheme.outline;
      }),
      trackColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return scheme.primary;
        return scheme.surfaceContainerHighest;
      }),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.secondary,
      overlayColor: scheme.secondary.withValues(alpha: 0.16),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
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
        // Bluetooth before Modes + Equalizer (car context + EQ profiles).
        ChangeNotifierProvider(create: (_) => BluetoothProvider()),
        // Modes: policy only. Ports never force play or reclaim focus.
        ChangeNotifierProvider(
          create: (context) {
            final modes = ModeProvider();
            modes.attachPlayback(
              ResonateModePlaybackPort(context.read<MusicProvider>()),
            );
            modes.attachMediaSource(const ResonateModeMediaSourcePort());
            modes.attachContext(
              ResonateModeContextPort(context.read<BluetoothProvider>()),
            );
            final music = context.read<MusicProvider>();
            modes.attachMotion(
              ResonateMotionPort(),
              isPlaying: () => music.isPlaying,
              onIntent: (intent) {
                if (intent.type == RunningIntentType.suggestPause) {
                  unawaited(music.pause(source: 'running_automation'));
                } else if (intent.type == RunningIntentType.suggestResume) {
                  unawaited(music.resumePlayback(source: 'running_automation'));
                }
              },
            );
            music.attachModes(modes);
            context.read<IntelligenceProvider>().attachModes(modes);
            return modes;
          },
        ),
        ChangeNotifierProvider(
          create: (context) => AutopilotController(
            music: context.read<MusicProvider>(),
            intelligence: context.read<IntelligenceProvider>(),
            modes: context.read<ModeProvider>(),
          ),
        ),
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
              DjModeProvider(music: context.read<MusicProvider>()),
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
