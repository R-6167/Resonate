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
import 'services/audio_service_handler.dart'; // our handler
import 'package:audio_service/audio_service.dart';

// Global audio handler to be initialized in the background
AudioHandler? _audioHandler;

Future<void> main() async {
  print('🚀 [MAIN] App starting...');
  WidgetsFlutterBinding.ensureInitialized();
  print('🚀 [MAIN] Widgets binding initialized');

  // Initialize audio_service in background WITHOUT AWAITING
  print('🚀 [MAIN] Scheduling audio service initialization in background...');
  _initializeAudioServiceAsync();

  print('✅ [MAIN] Main complete - launching app');
  runApp(const MyApp());
}

/// Initialize audio service in the background without blocking the UI
Future<void> _initializeAudioServiceAsync() async {
  try {
    print('🎵 [AUDIO_SERVICE] Initializing in background...');
    _audioHandler = await AudioService.init(
      builder: () => AudioServiceHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.yourcompany.resonate.channel.audio',
        androidNotificationChannelName: 'Audio Playback',
        androidNotificationOngoing: true,
      ),
    );
    print('✅ [AUDIO_SERVICE] Initialization complete');
  } catch (e) {
    print('❌ [AUDIO_SERVICE] Initialization failed: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    print('🎨 [MyApp] Building app...');
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            print('📱 [Provider] Creating ThemeProvider');
            return ThemeProvider();
          },
        ),
        // Audio handler will be initialized in background
        // Pass null initially, MusicProvider should handle null gracefully
        ChangeNotifierProvider(
          create: (_) {
            print('🎵 [Provider] Creating MusicProvider');
            return MusicProvider(audioHandler: _audioHandler);
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            print('🎚️ [Provider] Creating EqualizerProvider');
            return EqualizerProvider();
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            print('🔊 [Provider] Creating AudioEffectsProvider');
            return AudioEffectsProvider();
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            print('➡️ [Provider] Creating CrossfadeProvider');
            return CrossfadeProvider();
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            print('📊 [Provider] Creating AudioVisualizationProvider');
            return AudioVisualizationProvider();
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            print('📚 [Provider] Creating LibraryProvider (NON-BLOCKING)');
            return LibraryProvider();
          },
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          print('🎨 [Builder] Building MaterialApp with theme');
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
