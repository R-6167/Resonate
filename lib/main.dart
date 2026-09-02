import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'providers/audio_effects_provider.dart';
import 'providers/audio_visualization_provider.dart';
import 'providers/crossfade_provider.dart';
import 'providers/equalizer_provider.dart';
import 'providers/library_provider.dart';
import 'providers/music_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'services/audio_service_handler.dart';

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF315B9A),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: GoogleFonts.interTextTheme(
      ThemeData(brightness: brightness).textTheme,
    ),
    cardTheme: CardThemeData(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withOpacity(.55)),
      ),
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      filled: true,
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ResonateBootstrap());
}

class ResonateBootstrap extends StatefulWidget {
  const ResonateBootstrap({super.key});

  @override
  State<ResonateBootstrap> createState() => _ResonateBootstrapState();
}

class _ResonateBootstrapState extends State<ResonateBootstrap> {
  AudioHandler? _audioHandler;
  Object? _startupError;

  @override
  void initState() {
    super.initState();
    _initializeAudioService();
  }

  Future<void> _initializeAudioService() async {
    try {
      final handler = await AudioService.init(
        builder: () => AudioServiceHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.example.resonate.audio',
          androidNotificationChannelName: 'Resonate Playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;
      setState(() => _audioHandler = handler);
    } catch (e) {
      if (!mounted) return;
      setState(() => _startupError = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final handler = _audioHandler;

    if (handler == null) {
      return MaterialApp(
        title: 'Resonate',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _startupError == null
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 20),
                        Text('Starting Resonate...'),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          'Audio service could not start.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Resonate startup timed out or failed.\n$_startupError',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: () {
                            setState(() => _startupError = null);
                            _initializeAudioService();
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      );
    }

    return ResonateApp(audioHandler: handler);
  }
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
        ChangeNotifierProvider(create: (_) => EqualizerProvider()),
        ChangeNotifierProvider(create: (_) => AudioEffectsProvider()),
        ChangeNotifierProvider(create: (_) => CrossfadeProvider()),
        ChangeNotifierProvider(create: (_) => AudioVisualizationProvider()),
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Resonate',
            debugShowCheckedModeBanner: false,
            theme: _theme(Brightness.light),
            darkTheme: _theme(Brightness.dark),
            themeMode: themeProvider.isDarkMode
                ? ThemeMode.dark
                : ThemeMode.light,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
