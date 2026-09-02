import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'providers/music_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/equalizer_provider.dart';
import 'providers/audio_effects_provider.dart';
import 'providers/crossfade_provider.dart';
import 'providers/audio_visualization_provider.dart';
import 'providers/library_provider.dart';
import 'screens/home_screen.dart';
import 'services/audio_service_handler.dart';
import 'package:audio_service/audio_service.dart';

AudioHandler? _audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _audioHandler = await AudioService.init(
      builder: () => AudioServiceHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.yourcompany.resonate.channel.audio',
        androidNotificationChannelName: 'Audio Playback',
        androidNotificationOngoing: true,
      ),
    );
  } catch (e, stack) {
    debugPrint('AudioService initialization failed: $e');
    debugPrint('$stack');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => MusicProvider(audioHandler: _audioHandler)),
      ChangeNotifierProvider(create: (_) => EqualizerProvider()),
      ChangeNotifierProvider(create: (_) => AudioEffectsProvider()),
      ChangeNotifierProvider(create: (_) => CrossfadeProvider()),
      ChangeNotifierProvider(create: (_) => AudioVisualizationProvider()),
      ChangeNotifierProvider(create: (_) => LibraryProvider()),
    ],
    child: Consumer<ThemeProvider>(builder: (context, themeProvider, _) => MaterialApp(
      title: 'Resonate',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const HomeScreen(),
    )),
  );

  static ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF315B9A), brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: GoogleFonts.interTextTheme(ThemeData(brightness: brightness).textTheme),
      cardTheme: CardThemeData(margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), elevation: 0, side: BorderSide(color: scheme.outlineVariant.withOpacity(.55))),
      inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), filled: true),
    );
  }
}
