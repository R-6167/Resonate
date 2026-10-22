import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AudioEffectsBridge {
  static const MethodChannel _channel =
      MethodChannel('com.aetherion.resonate/audio_effects');
  static const MethodChannel _mediaChannel =
      MethodChannel('com.aetherion.resonate/media_store');

  /// Android Visualizer reads a limited playback spectrum, not microphone
  /// recordings. Request permission only when the user is using visualization.
  static Future<bool> requestVisualizationPermission() async {
    try {
      return await _mediaChannel.invokeMethod<bool>('requestVisualizationPermission') ?? false;
    } catch (e) {
      debugPrint('Visualization permission request failed: $e');
      return false;
    }
  }

  static Future<void> refreshVisualizers() async {
    try {
      await _channel.invokeMethod('refreshVisualizers');
    } catch (e) {
      debugPrint('Refreshing playback visualizers failed: $e');
    }
  }

  static Future<void> attachToSession(int sessionId) async {
    if (sessionId <= 0) return;
    try {
      await _channel.invokeMethod('attachToSession', {'sessionId': sessionId});
    } catch (e) {
      debugPrint('AudioEffectsBridge.attachToSession failed: $e');
    }
  }

  static Future<void> detachFromSession(int sessionId) async {
    if (sessionId <= 0) return;
    try {
      await _channel.invokeMethod('detachFromSession', {'sessionId': sessionId});
    } catch (e) {
      debugPrint('AudioEffectsBridge.detachFromSession failed: $e');
    }
  }

  static Future<void> setBassBoost(double strength) async {
    try {
      final s = (strength.clamp(0.0, 1.0) * 1000).round();
      await _channel.invokeMethod('setBassBoost', {'strength': s});
    } catch (e) {
      debugPrint('setBassBoost failed: $e');
    }
  }

  static Future<void> setVirtualizer(double strength) async {
    try {
      final s = (strength.clamp(0.0, 1.0) * 1000).round();
      await _channel.invokeMethod('setVirtualizer', {'strength': s});
    } catch (e) {
      debugPrint('setVirtualizer failed: $e');
    }
  }

  static Future<void> setReverb(double strength) async {
    try {
      final amount = strength.clamp(0.0, 1.0).toDouble();
      // Zero is the explicit disabled sentinel. Android EnvironmentalReverb
      // accepts -900..0 millibels; reserve 0 for off and map enabled values
      // to -900..-1 so positive settings never exceed the platform range.
      final s = amount <= 0 ? 0 : (-900 + (amount * 899).round());
      await _channel.invokeMethod('setReverb', {'strength': s});
    } catch (e) {
      debugPrint('setReverb failed: $e');
    }
  }

  static Future<Map<String, dynamic>?> setLiveDspPreampDb(double db) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('setLiveDspPreampDb', {
        'db': db.clamp(-12.0, 12.0),
      });
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('setLiveDspPreampDb failed: $e');
    }
    return null;
  }

  /// Set the native Digital Volume Control gain, independent of EQ preamp.
  /// The native engine smooths the transition; range is -24 dB to +6 dB.
  static Future<Map<String, dynamic>?> setLiveDspDvcDb(double db) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('setLiveDspDvcDb', {
        'db': db.clamp(-24.0, 6.0),
      });
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('setLiveDspDvcDb failed: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> setLiveDspEqBands({
    List<double>? centersHz,
    required List<double> gainsDb,
    bool enabled = true,
  }) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('setLiveDspEqBands', {
        if (centersHz != null) 'centersHz': centersHz,
        'gainsDb': gainsDb,
        'enabled': enabled,
      });
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('setLiveDspEqBands failed: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> setLiveDspSpeakerMode(bool enabled) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('setLiveDspSpeakerMode', {
        'enabled': enabled,
      });
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('setLiveDspSpeakerMode failed: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> setLiveDspVirtualBass(double amount) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('setLiveDspVirtualBass', {
        'amount': amount.clamp(0.0, 1.0),
      });
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('setLiveDspVirtualBass failed: $e');
    }
    return null;
  }

  /// Returns 32 inexpensive FFT magnitude bands captured from active playback sessions.
  /// Unsupported devices/routes return silence and never affect playback.
  static Future<List<double>> getAudioSpectrum() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('getAudioSpectrum');
      if (raw is List) {
        return raw.map((value) => (value as num).toDouble().clamp(0.0, 1.0)).toList(growable: false);
      }
    } catch (e) {
      debugPrint('getAudioSpectrum failed: $e');
    }
    return const <double>[];
  }

  static Future<Map<String, dynamic>?> getLiveDspStatus() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('getLiveDspStatus');
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('getLiveDspStatus failed: $e');
    }
    return null;
  }

  static Future<void> release() async {
    try {
      await _channel.invokeMethod('release');
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> setLiveDspLimiterCeiling({
    required double highDb,
    required double lowDb,
  }) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('setLiveDspLimiterCeiling', {
        'highDb': highDb.clamp(-6.0, -0.1),
        'lowDb': lowDb.clamp(-6.0, -0.1),
      });
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('setLiveDspLimiterCeiling failed: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> setLiveDspCrossoverHz(double hz) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('setLiveDspCrossoverHz', {
        'hz': hz.clamp(80.0, 200.0),
      });
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint('setLiveDspCrossoverHz failed: $e');
    }
    return null;
  }
}
