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

  static Future<void> release() async {
    try {
      await _channel.invokeMethod('release');
    } catch (_) {}
  }
}
