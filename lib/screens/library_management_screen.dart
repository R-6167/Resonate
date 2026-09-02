import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../services/audio_file_service.dart';

class LibraryManagementScreen extends StatelessWidget {
  const LibraryManagementScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Library Management')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.library_music),
              title: const Text('Scan device audio'),
              subtitle: Text(library.isScanning
                  ? 'Scanning MediaStore…'
                  : '${library.allSongs.length} songs indexed'),
              trailing: library.isScanning
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : FilledButton(
                      onPressed: library.scanDeviceAudio,
                      child: const Text('Scan'),
                    ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Scanned Directories',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          FutureBuilder<List<String>>(
            future: AudioFileService.getMusicDirectories(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final dirs = snapshot.data!;
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: dirs.length,
                itemBuilder: (context, index) => ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(dirs[index]),
                  subtitle: const Text('MediaStore audio location'),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Resonate scans Android MediaStore automatically when the library opens. '
                'A manual scan is available above when new music is added.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
