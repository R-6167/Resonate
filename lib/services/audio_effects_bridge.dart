import 'package:flutter/services.dart';

class AudioEffectsBridge {
  static const MethodChannel _channel = MethodChannel('com.example.resonate/audio_effects');

  static Future<void> attachToSession(int sessionId) async {
    await _channel.invokeMethod('attachToSession', {'sessionId': sessionId});
  }

  static Future<void> setBassBoost(double value) async {
    await _channel.invokeMethod('setBassBoost', {'strength': (value.clamp(0.0, 1.0) * 1000).round()});
  }

  static Future<void> setVirtualizer(double value) async {
    await _channel.invokeMethod('setVirtualizer', {'strength': (value.clamp(0.0, 1.0) * 1000).round()});
  }

  static Future<void> setReverb(double value) async {
    await _channel.invokeMethod('setReverb', {'strength': (value.clamp(0.0, 1.0) * 1000).round()});
  }

  static Future<void> release() async {
    await _channel.invokeMethod('release');
  }
}
