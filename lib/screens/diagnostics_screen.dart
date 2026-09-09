import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/resonate_diagnostics.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});
  @override State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  bool _loading = true;
  Map<String, dynamic> _report = const {};

  @override void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    final report = await ResonateDiagnostics.snapshot();
    if (!mounted) return;
    setState(() { _report = report; _loading = false; });
  }

  Future<void> _export() async {
    try {
      final saved = await ResonateDiagnostics.exportReport();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved == null ? 'Save cancelled. The diagnostic report was not exported.' : 'Diagnostic report saved locally.')));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save diagnostics: $e')));
    }
  }

  Future<void> _reportProblem() async {
    final session = _report['session'] as Map?;
    final sessionId = session?['id']?.toString() ?? 'unknown';
    final summary = _report['summary'] as Map?;
    final crashes = summary?['crashCount'] ?? 0;
    final events = summary?['eventCount'] ?? 0;
    final uri = Uri(
      scheme: 'mailto',
      path: 'innotrepid@gmail.com',
      queryParameters: {
        'subject': 'Resonate problem report',
        'body': 'Hi Resonate team,\n\nI am reporting a problem with Resonate.\n\nSession: $sessionId\nDiagnostic events: $events\nCrash records: $crashes\n\nWhat happened:\n\n',
      },
    );
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) throw Exception('No email app is available.');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No email app is available on this device.')));
    }
  }

  Future<void> _clear() async {
    final yes = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Delete diagnostic data?'), content: const Text('This deletes locally stored diagnostic events, crash records and feedback. Listening history and music are not affected.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))]));
    if (yes == true) { await ResonateDiagnostics.clearDiagnostics(); await _refresh(); }
  }

  void _showWhatCollected() => showDialog<void>(context: context, builder: (_) => const AlertDialog(title: Text('What is collected?'), content: Text('Resonate records technical events needed to diagnose playback and Intelligence problems: timestamps, playback commands and generations, song/queue state, player processing state, positions, buffering, engine transitions, errors, stack traces, app/build mode and operating-system information. Feedback text is included when you choose to save it. Music files, microphone/audio recordings, contacts, credentials and arbitrary files are not collected. Reports are never uploaded automatically.')));

  @override Widget build(BuildContext context) {
    final events = (_report['events'] as List?)?.length ?? 0;
    final crashes = (_report['crashes'] as List?)?.length ?? 0;
    final feedback = (_report['feedback'] as List?)?.length ?? 0;
    return Scaffold(appBar: AppBar(title: const Text('Privacy & Diagnostics')), body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 36), children: [
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(Icons.health_and_safety_rounded, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 12), Expanded(child: Text('Development diagnostics', style: Theme.of(context).textTheme.titleLarge))]), const SizedBox(height: 12), const Text('Diagnostics stay on this device. Save report lets you choose where the JSON is stored. Report a problem opens your installed email app directly. Nothing is uploaded automatically.')]))) ,
      ListTile(leading: const Icon(Icons.bug_report_outlined), title: const Text('Crash records'), subtitle: Text('$crashes locally stored'), trailing: const Icon(Icons.lock_outline)),
      ListTile(leading: const Icon(Icons.timeline_rounded), title: const Text('Diagnostic events'), subtitle: Text('$events recent events stored locally')),
      ListTile(leading: const Icon(Icons.feedback_outlined), title: const Text('Saved feedback'), subtitle: Text('$feedback feedback reports stored locally')),
      const Divider(),
      ListTile(leading: const Icon(Icons.email_outlined), title: const Text('Report a problem'), subtitle: const Text('Open your email app with a Resonate report template.'), onTap: _reportProblem),
      ListTile(leading: const Icon(Icons.save_alt_rounded), title: const Text('Save diagnostic report'), subtitle: const Text('Choose the folder and filename with the Android Save As dialog.'), onTap: _export),
      ListTile(leading: const Icon(Icons.visibility_outlined), title: const Text('What is collected?'), subtitle: const Text('Playback/Intelligence diagnostics, errors and device runtime information. No audio files or microphone data.'), onTap: _showWhatCollected),
      ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Delete local diagnostics'), subtitle: const Text('Remove stored crash records, diagnostic events and feedback.'), onTap: _clear),
    ]));
  }
}
