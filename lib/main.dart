import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_service/audio_service.dart';
import 'audio_handler.dart';
import 'providers/music_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/equalizer_provider.dart';
import 'providers/audio_effects_provider.dart';
import 'providers/crossfade_provider.dart';
import 'providers/audio_visualization_provider.dart';
import 'providers/library_provider.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize just_audio_background for media notifications & background playback
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.resonatemp.resonate.channel.audio',
    androidNotificationChannelName: 'Resonate audio playback',
    androidNotificationOngoing: true,
  );

  // Initialize audio_service and the background audio handler so background isolate is ready
  final audioHandler = await AudioService.init(
    builder: () => audioHandlerFactory(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.resonatemp.resonate.channel.audio',
      androidNotificationChannelName: 'Resonate audio playback',
      androidNotificationOngoing: true,
    ),
  );

  runApp(MyApp(audioHandler: audioHandler));
}

class MyApp extends StatelessWidget {
  final AudioHandler audioHandler;
  const MyApp({Key? key, required this.audioHandler}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => MusicProvider(audioHandler)),
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
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF6366F1),
                brightness: Brightness.light,
              ),
              textTheme: GoogleFonts.poppinsTextTheme(),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF6366F1),
                brightness: Brightness.dark,
              ),
              textTheme: GoogleFonts.poppinsTextTheme(
                ThemeData(brightness: Brightness.dark).textTheme,
              ),
            ),
            themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
