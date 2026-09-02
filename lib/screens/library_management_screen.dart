import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../services/audio_file_service.dart';

class LibraryManagementScreen extends StatefulWidget {
  const LibraryManagementScreen({Key? key}) : super(key: key);

  @override
  State<LibraryManagementScreen> createState() =>
      _LibraryManagementScreenState();
}

class _LibraryManagementScreenState extends State<LibraryManagementScreen> {
  bool _isScanning = false;
  int _foundFiles = 0;
  String _totalSize = '0 B';
  int _musicFileCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStorageInfo();
  }

  Future<void> _loadStorageInfo() async {
    final info = await AudioFileService.getStorageInfo();
    final count = await AudioFileService.getMusicFileCount();
    
    setState(() {
      _totalSize = info['formattedSize'] ?? '0 B';
      _musicFileCount = count;
    });
  }

  Future<void> _scanForMusic() async {
    setState(() => _isScanning = true);
    
    try {
      print('🔍 Starting audio file scan...');
      final songs = await AudioFileService.scanAudioFiles();
      
      setState(() => _foundFiles = songs.length);

      if (mounted && songs.isNotEmpty) {
        // Add songs to library
        final libraryProvider =
            context.read<LibraryProvider>();
        await libraryProvider.addSongs(songs);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Found and added $_foundFiles songs'),
            duration: const Duration(seconds: 2),
          ),
        );

        // Refresh storage info
        await _loadStorageInfo();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ No audio files found'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('Error scanning: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error scanning: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library Management'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Storage Info Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.storage,
                        size: 32,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Music Storage',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Total size: $_totalSize',
                              style:
                                  Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              _musicFileCount.toString(),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Audio Files',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: Theme.of(context)
                            .dividerColor,
                      ),
                      Expanded(
                        child: Consumer<LibraryProvider>(
                          builder: (context, libraryProvider, _) {
                            return Column(
                              children: [
                                Text(
                                  libraryProvider.allSongs.length
                                      .toString(),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'In Library',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall,
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Scan Button
          FilledButton.icon(
            onPressed: _isScanning ? null : _scanForMusic,
            icon: _isScanning
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  )
                : const Icon(Icons.search),
            label: Text(_isScanning
                ? 'Scanning... ($_foundFiles found)'
                : 'Scan for Music'),
          ),

          const SizedBox(height: 24),

          // Directories Section
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
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              final dirs = snapshot.data ?? [];
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: dirs.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    leading: const Icon(Icons.folder_music),
                    title: Text(dirs[index]),
                    subtitle: const Text('Music directory'),
                  );
                },
              );
            },
          ),

          const SizedBox(height: 24),

          // Info Section
          Card(
            color: Theme.of(context)
                .colorScheme
                .primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ℹ️ How to scan',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1. Tap "Scan for Music" to search all music directories\n'
                    '2. Supported formats: MP3, WAV, FLAC, M4A, AAC, OGG\n'
                    '3. Files will be added to your library automatically',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
