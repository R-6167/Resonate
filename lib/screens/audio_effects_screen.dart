import 'package:flutter/material.dart';

import 'equalizer_screen.dart';

/// Effects live on the Equalizer screen now (Bass / Width / Reverb).
/// Loudness was retired — Resonate DSP preamp owns overall level.
/// This route redirects so older bookmarks still land in the right place.
class AudioEffectsScreen extends StatelessWidget {
  const AudioEffectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const EqualizerScreen()),
      );
    });
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
