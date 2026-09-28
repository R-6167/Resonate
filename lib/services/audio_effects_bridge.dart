import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AudioEffectsBridge {
  static const MethodChannel _channel =
      MethodChannel('com.aetherion.resonate/audio_effects');

  static Future<void> attachToSession(int sessionId) async {
    if (sessionId <= 0) return;
    try {
      await _channel.invokeMethod('attachToSession', {'sessionId': sessionId});
    } catch (e) {
      debugPrint('AudioEffectsBridge.attachToSession failed: $e');
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
      final s = (strength.clamp(0.0, 1.0) * 1900 - 900).round();
      await _channel.invokeMethod('setReverb', {'strength': s});
    } catch (e) {
      debugPrint('setReverb failed: $e');
    }
  }

  /// Live DSP ENGINE preamp (DVC) on every registered A/B sink handle.
  static Future<Map<String, dynamic>?> setLiveDspPreampDb(double db) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('setLiveDspPreampDb', {
        'db': db.clamp(-12.0, 12.0),
      });
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } catch (e) {
      debugPrint('setLiveDspPreampDb failed: $e');
    }
    return null;
  }

  /// Live multi-band EQ on every registered A/B sink handle.
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
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } catch (e) {
      debugPrint('setLiveDspEqBands failed: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getLiveDspStatus() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('getLiveDspStatus');
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
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
}
