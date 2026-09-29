import 'package:flutter/material.dart';

import 'equalizer_screen.dart';

/// Legacy entry — Effects now live inside [EqualizerScreen].
class AudioEffectsScreen extends StatelessWidget {
  const AudioEffectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Replace route so back stack does not keep a dead Effects page.
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
