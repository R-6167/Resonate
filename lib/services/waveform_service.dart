import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class WaveformService {
  // Compute a lightweight waveform approximation by sampling file bytes in blocks.
  // This is a fast, platform-independent approximation (not a true PCM-based FFT).

  static Future<String> _cachePath(String key) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/waveform_cache_$key.json';
  }

  static String _hash(String input) => md5.convert(utf8.encode(input)).toString();

  /// Returns a cached waveform sample list (0..100) or computes it from the file bytes.
  static Future<List<int>> getWaveform(String filePath, {int samples = 120}) async {
    try {
      final key = _hash(filePath);
      final cacheFile = await _cachePath(key);
      final cf = File(cacheFile);
      if (await cf.exists()) {
        final content = await cf.readAsString();
        final List<dynamic> arr = json.decode(content);
        return arr.map((e) => (e as num).toInt()).toList();
      }

      final f = File(filePath);
      if (!await f.exists()) return List.filled(samples, 0);

      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) return List.filled(samples, 0);

      final seg = (bytes.length / samples).ceil();
      final List<int> result = [];
      for (var i = 0; i < bytes.length; i += seg) {
        final end = (i + seg < bytes.length) ? i + seg : bytes.length;
        int sum = 0;
        for (var j = i; j < end; j++) {
          sum += (bytes[j] & 0xFF);
        }
        final avg = sum ~/ (end - i);
        // normalize 0..255 to 0..100
        final norm = ((avg / 255.0) * 100).round();
        result.add(norm);
      }

      // If result length differs from requested samples, resample
      if (result.length != samples) {
        final resampled = <int>[];
        for (var i = 0; i < samples; i++) {
          final idx = (i * result.length / samples).floor();
          resampled.add(result[idx.clamp(0, result.length - 1)]);
        }
        await cf.writeAsString(json.encode(resampled));
        return resampled;
      }

      await cf.writeAsString(json.encode(result));
      return result;
    } catch (e) {
      // On any error, return an empty waveform with zeros
      return List.filled(samples, 0);
    }
  }
}
