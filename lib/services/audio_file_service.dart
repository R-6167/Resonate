import 'dart:io';
import 'package:flutter_audio_query/flutter_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/song.dart';

class AudioFileService {
  static const _audioExtensions = {'.mp3', '.wav', '.flac', '.m4a', '.aac', '.ogg'};

  /// Get all music directories on the device
  static Future<List<String>> getMusicDirectories() async {
    final directories = <String>{};

    // Add standard music directories
    if (Platform.isAndroid) {
      directories.add('/storage/emulated/0/Music');
      directories.add('/storage/emulated/0/Download');
      directories.add('/storage/emulated/0/Documents');
      directories.add('/storage/emulated/0/DCIM');
      
      // Add external storage if available
      try {
        final externalDir = Directory('/sdcard/Music');
        if (await externalDir.exists()) {
          directories.add(externalDir.path);
        }
      } catch (e) {
        print('Error accessing external storage: $e');
      }
    }

    return directories.toList();
  }

  /// Get total music files count
  static Future<int> getMusicFileCount() async {
    int count = 0;
    final dirs = await getMusicDirectories();

    for (final dir in dirs) {
      try {
        final directory = Directory(dir);
        if (await directory.exists()) {
          await directory.list(recursive: true).listen((entity) {
            if (entity is File && _isAudioFile(entity.path)) {
              count++;
            }
          }).asFuture();
        }
      } catch (e) {
        print('Error counting files in $dir: $e');
      }
    }

    return count;
  }

  /// Get storage usage info
  static Future<Map<String, dynamic>> getStorageInfo() async {
    try {
      int totalSize = 0;
      final dirs = await getMusicDirectories();

      for (final dir in dirs) {
        try {
          final directory = Directory(dir);
          if (await directory.exists()) {
            await directory.list(recursive: true).listen((entity) {
              if (entity is File && _isAudioFile(entity.path)) {
                totalSize += entity.lengthSync();
              }
            }).asFuture();
          }
        } catch (e) {
          print('Error calculating size in $dir: $e');
        }
      }

      return {
        'totalSize': totalSize,
        'formattedSize': _formatBytes(totalSize),
      };
    } catch (e) {
      print('Error getting storage info: $e');
      return {'totalSize': 0, 'formattedSize': '0 B'};
    }
  }

  /// Scan for audio files in all music directories
  static Future<List<Song>> scanAudioFiles() async {
    print('🔍 AudioFileService: Starting audio file scan...');
    
    // Request permissions
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      print('❌ Storage permission denied');
      return [];
    }

    final songs = <Song>[];
    final dirs = await getMusicDirectories();

    for (final dir in dirs) {
      try {
        final directory = Directory(dir);
        if (await directory.exists()) {
          print('📂 Scanning: $dir');
          
          await directory.list(recursive: true).forEach((entity) {
            if (entity is File && _isAudioFile(entity.path)) {
              try {
                final song = _fileToSong(entity);
                if (song != null) {
                  songs.add(song);
                  print('✅ Found: ${song.title}');
                }
              } catch (e) {
                print('Error processing file ${entity.path}: $e');
              }
            }
          });
        }
      } catch (e) {
        print('Error scanning directory $dir: $e');
      }
    }

    print('🎵 AudioFileService: Found ${songs.length} audio files');
    return songs;
  }

  /// Check if file is audio format
  static bool _isAudioFile(String path) {
    final ext = path.toLowerCase();
    return _audioExtensions.any((extension) => ext.endsWith(extension));
  }

  /// Convert file to Song object
  static Song? _fileToSong(File file) {
    try {
      final name = file.path.split('/').last;
      final nameWithoutExt = name.replaceAll(RegExp(r'\.[^.]*$'), '');
      
      return Song(
        id: file.path.hashCode.toString(),
        title: nameWithoutExt,
        artist: 'Unknown Artist',
        album: 'Unknown Album',
        filePath: file.path,
        duration: Duration.zero, // Would need metadata reading for accurate duration
        dateAdded: file.lastModifiedSync(),
        albumArt: null,
      );
    } catch (e) {
      print('Error converting file to song: $e');
      return null;
    }
  }

  /// Format bytes to human readable format
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    int i = (bytes.toString().length / 3).ceil();
    double size = bytes / (1000 * (i - 1));
    return '${size.toStringAsFixed(2)} ${suffixes[i - 1]}';
  }

  /// Format duration
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
