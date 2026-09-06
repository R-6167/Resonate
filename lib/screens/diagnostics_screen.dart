import 'package:flutter/material.dart';

import '../services/resonate_diagnostics.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  bool _loading = true;
  bool _includeDiagnostics = true;
  Map<String, dynamic> _report = const {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final report = await ResonateDiagnostics.snapshot();
    if (!mounted) return;
    setState(() {
      _report = report;
      _loading = false;
    });
  }

  Future<void> _export() async {
    try {
      await ResonateDiagnostics.exportReport();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Diagnostic report is ready to share.')));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not export diagnostics: $e')));
    }
  }

  Future<void> _sendFeedback() async {
    final messageController = TextEditingController();
    String category = 'Other';
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Send feedback'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'What happened?'),
                items: const [
                  'Playback stopped', 'Wrong song', 'Intelligence choice', 'Autopilot',
                  'Companion / Mixes', 'Bluetooth', 'Equalizer', 'Notification', 'Crash', 'Other',
                ].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                onChanged: (value) => setDialogState(() => category = value ?? 'Other'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(hintText: 'Tell us what happened…'),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include diagnostics'),
                subtitle: const Text('Attach the local event history to help reproduce the problem.'),
                value: _includeDiagnostics,
                onChanged: (value) => setDialogState(() => _includeDiagnostics = value),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save feedback')),
          ],
        ),
      ),
    );
    if (result != true || messageController.text.trim().isEmpty) {
      messageController.dispose();
      return;
    }
    await ResonateDiagnostics.recordFeedback(category: category, message: messageController.text, includeDiagnostics: _includeDiagnostics);
    messageController.dispose();
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Feedback saved locally. Export the report to bring it here.')));
  }

  Future<void> _clear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete diagnostic data?'),
        content: const Text('This deletes locally stored diagnostic events, crash records and feedback. Listening history and music are not affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes == true) {
      await ResonateDiagnostics.clearDiagnostics();
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = (_report['events'] as List?)?.length ?? 0;
    final crashes = (_report['crashes'] as List?)?.length ?? 0;
    final feedback = (_report['feedback'] as List?)?.length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Diagnostics')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 36),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.health_and_safety_rounded, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(child: Text('Development diagnostics', style: Theme.of(context).textTheme.titleLarge)),
                      ]),
                      const SizedBox(height: 12),
                      const Text('Crash capture is mandatory in this development build so we can diagnose bugs. Reports stay on this device until you export them.'),
                    ]),
                  ),
                ),
                ListTile(leading: const Icon(Icons.bug_report_outlined), title: const Text('Crash records'), subtitle: Text('$crashes locally stored'), trailing: const Icon(Icons.lock_outline)),
                ListTile(leading: const Icon(Icons.timeline_rounded), title: const Text('Diagnostic events'), subtitle: Text('$events recent events stored locally')),
                ListTile(leading: const Icon(Icons.feedback_outlined), title: const Text('Saved feedback'), subtitle: Text('$feedback feedback reports stored locally')),
                const Divider(),
                ListTile(leading: const Icon(Icons.upload_file_rounded), title: const Text('Export diagnostic report'), subtitle: const Text('Creates a JSON report containing crashes, events and feedback, then opens Android sharing.'), onTap: _export),
                ListTile(leading: const Icon(Icons.feedback_rounded), title: const Text('Report a problem'), subtitle: const Text('Save structured feedback locally so it can travel with the diagnostic report.'), onTap: _sendFeedback),
                ListTile(leading: const Icon(Icons.visibility_outlined), title: const Text('What is collected?'), subtitle: const Text('Playback/Intelligence diagnostics, errors and device runtime information. No audio files or microphone data.'), onTap: () => showDialog<void>(context: context, builder: (_) => const AlertDialog(title: Text('What is collected?'), content: Text('Resonate records technical events needed to diagnose playback and Intelligence problems: timestamps, event types, errors, stack traces, app/build mode and operating-system information. Feedback text is included when you choose to save it. Music files, microphone/audio recordings, contacts, credentials and arbitrary files are not collected. Reports are not uploaded automatically.'))),
                ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Delete local diagnostics'), subtitle: const Text('Remove stored crash records, diagnostic events and feedback.'), onTap: _clear),
              ],
            ),
    );
  }
}
