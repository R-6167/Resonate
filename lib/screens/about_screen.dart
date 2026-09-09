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
              Text('0.1.3 • Local-first intelligent music player', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 18),
              Text('Resonate is an offline-first music player built around a simple idea: your local library should remain yours while the player becomes more useful the more you listen.', style: theme.textTheme.bodyLarge),
            ]),
          ),
          const SizedBox(height: 28),
          _section(context, 'What is Resonate?', 'Resonate combines local music discovery, reliable playback, audio controls, Bluetooth/media controls and a privacy-first Intelligence layer. Intelligence learns from local listening behavior rather than requiring a cloud recommendation profile.'),
          _section(context, 'How to use Resonate', '1. Give Resonate audio access when Android asks.\n\n2. Open Settings → Library → Scan & folders to choose folders, enable automatic scanning and set the minimum audio length. If folders are selected, automatic scans respect those folders.\n\n3. Open Library, choose a song and tap it to play. Use the Player for seeking, volume and playback controls.\n\n4. Open Settings → Audio for the main equalizer, per-song EQ and effects. Crossfade is under Settings → Playback → Crossfade.\n\n5. Open Settings → Intelligence → Advanced Intelligence to control authority, exploration, confidence, automatic queueing, explanations and learning behavior.\n\n6. On For You, use recommendation feedback to explicitly teach Intelligence what fits.\n\n7. Connect Bluetooth devices through Android. Resonate handles media buttons, notifications and configured connection behavior.\n\n8. Keep listening. Finishes, skips, transitions, explicit feedback, song choices and generated-mix journeys become local signals used to improve recommendations.'),
          _section(context, 'Intelligence explained', 'Resonate Intelligence understands the flow of a listening session, not just isolated song scores. It uses completion and skip behavior, recency, repetition, transition choices, session direction, familiarity and controlled exploration when ranking what should happen next. Suggestions can remain non-authoritative; Assist and Autopilot provide progressively greater authority. Learning is deliberately gradual and based on actual listening evidence.'),
          _section(context, 'Deep Companion', 'Deep Companion extends Intelligence into a continuing musical companion. It keeps bounded local memory of listening patterns, recognizes recurring listening states, adapts to the current session, builds automatic long-form mixes and learns whether those mixes fit. Generated-mix continuity, replay destinations and long-form listening signals can shape future decisions without uploading audio.'),
          _section(context, 'Implemented in 0.1.3', '• Background playback and Android media notification\n• Reliable queue, next/previous, pause/resume and seek controls\n• Duplicate completion protection and safer track-end transitions\n• Crossfade controls, OFF by default\n• System-linked volume control and live volume UI\n• Main equalizer, per-song EQ entry point and audio effects\n• Local music library and one-folder-at-a-time folder selection flow\n• Automatic library scanning with user-defined minimum audio duration\n• Automatic scanning that respects selected folder restrictions\n• Listening history and local Intelligence event storage\n• Explainable local recommendations with confidence\n• Intelligence authority, exploration, automatic queue and session controls\n• Behavioral learning from completion, skip, replay and transition signals\n• Explicit recommendation feedback\n• Persistent cross-session Intelligence state and Companion memory\n• Adaptive session sequencing and automatic local mixtape generation\n• Long-mix analysis and generated-mix continuity learning\n• Autopilot readiness and takeover controls\n• Intelligence settings import/export and local Save settings option\n• Theme and Companion-style Settings organization\n• Bluetooth/media-control settings\n• Diagnostics flight recorder, crash reporting and in-app problem reporting\n• Local-first privacy model\n• Responsive library-to-player startup and faster manual next/previous transitions\n• Library visibility restrictions applied to restored queues and queue additions'),
          _section(context, 'Next / still being refined', '• Further playback edge-case testing across devices, especially rare track-end/source-switch races\n• Deeper replay-pattern and segment evidence\n• Stronger cross-session mix-to-mix musical-journey memory\n• More automatic Companion actions beyond recommendations and queueing\n• Broader Companion home and richer mix surfaces\n• Deeper Intelligence integration with per-song EQ\n• Additional Bluetooth/device refinements\n• Continued library scanning refinements\n\nThese are refinements or future Companion capabilities, not placeholders for features already present in the app.'),
          _section(context, 'Privacy', 'Resonate is designed around local-first operation. Listening signals, pattern memory, generated-mix memory, replay positions and explicit feedback used by Intelligence are stored and processed on the device. Deep Companion does not require uploaded audio or a remote recommendation profile.'),
          _section(context, 'License', 'Resonate is licensed under the MIT License. The product and source copyright notice is attributed to Innotrepid, the operating studio for Resonate. The parent/holding company relationship can be documented separately if the corporate structure changes.'),
          _licenseSection(context),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 18),
          Center(child: Text('Copyright © 2026 Innotrepid', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
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
    SelectableText('MIT License\n\nCopyright (c) 2026 Innotrepid\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.', style: Theme.of(context).textTheme.bodySmall),
  ]));
}
