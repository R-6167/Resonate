import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About Resonate')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primaryContainer, scheme.surfaceContainerHighest])),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Resonate', style: theme.textTheme.displaySmall?.copyWith(fontFamily: 'serif', fontStyle: FontStyle.italic, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('0.1.0 • Local-first intelligent music player', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 18),
              Text('Resonate is an offline-first music player built around a simple idea: your local library should remain yours while the player becomes more useful the more you listen.', style: theme.textTheme.bodyLarge),
            ]),
          ),
          const SizedBox(height: 28),
          _section(context, 'What is Resonate?', 'Resonate combines local music discovery, reliable playback, audio controls, Bluetooth/media controls and a privacy-first Intelligence layer. The Intelligence system is designed to learn from local listening behavior rather than requiring a cloud recommendation profile.'),
          _section(context, 'How to use Resonate', '1. Give Resonate audio access when Android asks.\n\n2. Open Settings → Library to manage music folders and scanning.\n\n3. Open Library, choose a song and tap it to play. Use the Player for seeking, volume and playback controls.\n\n4. Open Settings → Audio for the main equalizer, per-song EQ and effects. Crossfade is under Settings → Playback → Crossfade.\n\n5. Open Settings → Intelligence → Master switch & Authority. Suggestions keep control manual; Assist and Autopilot progressively allow Intelligence to help with what comes next.\n\n6. On the For You screen, use the thumbs-up or thumbs-down controls on an Intelligence recommendation to explicitly teach it what you like.\n\n7. Connect Bluetooth devices through Android. Resonate handles media buttons and the configured connection behavior.\n\n8. Keep listening. Finishes, skips, transitions, explicit feedback and song choices become local signals used to improve recommendations.'),
          _section(context, 'Intelligence explained', 'Resonate Intelligence now understands the flow of a listening session, not just isolated song scores. It tracks the recent session window, completion versus skip behavior, artists appearing in the current flow, familiarity and freshness. It then balances continuity with controlled exploration when ranking the next tracks. The For You screen shows the current session mode and why a recommendation fits the flow. Autopilot uses the same session context when building its next short sequence. All of this remains local and lightweight.'),
          _section(context, 'Implemented', 'Playback with background audio and media notifications\n\n• Android foreground playback notification\n• Bluetooth/media-button command routing\n• Queue and next/previous playback\n• Crossfade controls\n• Main equalizer and audio effects\n• Per-song EQ entry point\n• Local music library and folder management\n• Listening-event storage for Intelligence\n• Explainable local recommendations\n• Intelligence enable/disable control\n• Suggest / Assist / Autopilot authority levels\n• Automatic Autopilot graduation after sufficient learning\n• Session-aware Autopilot queue selection\n• Behavioral learning from completion and skip signals\n• Explicit thumbs-up / thumbs-down recommendation feedback\n• Persistent local Intelligence feedback\n• Session Intelligence with continuity/exploration balancing\n• Visible session state on For You\n• Theme controls\n• Companion-style Settings organization\n• Local-first privacy model\n• MIT license'),
          _section(context, 'In progress', '• Deeper Intelligence session learning and feedback loops\n• Stronger automatic sequencing and exploration decisions\n• Automatic local mixtape / playlist generation\n• Long-mix analysis and detection of the sections a listener repeatedly enjoys\n• More complete per-song EQ behavior under Intelligence\n• Dedicated sub-settings pages for major Settings categories\n• More advanced library scanning and folder handling\n• Intelligence data export and broader privacy controls\n• Additional Bluetooth/device refinements\n• Broader playback behavior refinements as device testing continues'),
          _section(context, 'Privacy', 'Resonate is designed around local-first operation. Listening signals and explicit feedback used by Intelligence are stored and processed on the device. The current design does not require a remote recommendation profile.'),
          _section(context, 'Open-source licenses', 'Resonate is distributed under the MIT License. The complete license text is shown below. Third-party package license notices will be added as each dependency license is verified.'),
          _licenseSection(context),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 18),
          Center(child: Text('Copyright © 2026 Aetherion', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
          const SizedBox(height: 4),
          Center(child: Text('Resonate • Built for local music, thoughtful playback and private intelligence.', textAlign: TextAlign.center, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, String text) => Padding(padding: const EdgeInsets.only(bottom: 24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 9), Text(text, style: Theme.of(context).textTheme.bodyMedium)]));

  Widget _licenseSection(BuildContext context) => Container(padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: Theme.of(context).colorScheme.surfaceContainerHighest, border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('MIT License', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
    const SizedBox(height: 10),
    SelectableText('MIT License\n\nCopyright (c) 2026 Aetherion\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.', style: Theme.of(context).textTheme.bodySmall),
  ]));
}
