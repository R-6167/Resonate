import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings.dart';

/// High-level handle around the native DSP ENGINE.
class DspEngine {
  DspEngine._(this._handle, this._sampleRate, this._channels, this._bufferFrames);

  final Pointer<Void> _handle;
  final int _sampleRate;
  final int _channels;
  final int _bufferFrames;
  bool _disposed = false;

  int get sampleRate => _sampleRate;
  int get channels => _channels;
  int get bufferFrames => _bufferFrames;

  static DspEngine create({
    int sampleRate = 48000,
    int channels = 2,
    int bufferFrames = 256,
  }) {
    final lib = NativeLib.instance;
    final cfg = calloc<NativeDspConfig>();
    cfg.ref
      ..sampleRate = sampleRate
      ..channels = channels
      ..bufferFrames = bufferFrames
      ..exclusiveMode = false
      ..bitPerfect = true
      ..realtimePriority = 0;
    final h = lib.create(cfg);
    calloc.free(cfg);
    if (h == nullptr) {
      throw StateError('dsp_create failed');
    }
    return DspEngine._(h, sampleRate, channels, bufferFrames);
  }

  void start() {
    _check();
    NativeLib.instance.start(_handle);
  }

  void stop() {
    _check();
    NativeLib.instance.stop(_handle);
  }

  void setVolume(double linear) {
    _check();
    NativeLib.instance.setVolume(_handle, linear);
  }

  void setPreamp(double linear) {
    _check();
    NativeLib.instance.setPreamp(_handle, linear);
  }

  void setEqEnabled(bool enabled) {
    _check();
    NativeLib.instance.eqSetEnabled(_handle, enabled);
  }

  void setEqBands({
    required List<double> centersHz,
    required List<double> gainsDb,
  }) {
    _check();
    if (centersHz.length != gainsDb.length || centersHz.isEmpty) {
      throw ArgumentError('centersHz and gainsDb must be non-empty and equal length');
    }
    final n = centersHz.length;
    final c = calloc<Double>(n);
    final g = calloc<Double>(n);
    for (var i = 0; i < n; i++) {
      c[i] = centersHz[i];
      g[i] = gainsDb[i];
    }
    NativeLib.instance.eqSetBands(_handle, c, g, n);
    calloc.free(c);
    calloc.free(g);
  }

  void setSpeakerMode(bool enabled) {
    _check();
    NativeLib.instance.setSpeakerMode(_handle, enabled);
  }

  void setVirtualBass(double amount) {
    _check();
    NativeLib.instance.setVirtualBass(_handle, amount);
  }

  void setLimiterCeiling({required double highDb, required double lowDb}) {
    _check();
    NativeLib.instance.setLimiterCeiling(_handle, highDb, lowDb);
  }

  void setCrossoverHz(double hz) {
    _check();
    NativeLib.instance.setCrossoverHz(_handle, hz);
  }

  /// Process interleaved float32 PCM. [frames] is frames per channel.
  void process(Float32List input, Float32List output, int frames) {
    _check();
    final need = frames * _channels;
    if (input.length < need || output.length < need) {
      throw ArgumentError('buffers too short for $frames frames x $_channels ch');
    }
    final inPtr = calloc<Float>(need);
    final outPtr = calloc<Float>(need);
    for (var i = 0; i < need; i++) {
      inPtr[i] = input[i];
    }
    NativeLib.instance.process(_handle, inPtr, outPtr, frames);
    for (var i = 0; i < need; i++) {
      output[i] = outPtr[i];
    }
    calloc.free(inPtr);
    calloc.free(outPtr);
  }

  /// Zero-copy process using caller-owned native pointers (audio thread).
  void processPointers(Pointer<Float> input, Pointer<Float> output, int frames) {
    _check();
    NativeLib.instance.process(_handle, input, output, frames);
  }

  DspEngineStats getStats() {
    _check();
    final s = calloc<NativeDspStats>();
    NativeLib.instance.getStats(_handle, s);
    final out = DspEngineStats(
      processCalls: s.ref.processCalls,
      totalNs: s.ref.totalNs,
      maxNs: s.ref.maxNs,
      overrunCount: s.ref.overrunCount,
      lastFrames: s.ref.lastFrames,
      sampleRate: s.ref.sampleRate,
      channels: s.ref.channels,
    );
    calloc.free(s);
    return out;
  }

  void resetStats() {
    _check();
    NativeLib.instance.resetStats(_handle);
  }

  static DspEngineInfo info([DspEngine? engine]) {
    final s = calloc<NativeDspInfo>();
    NativeLib.instance.getInfo(engine?._handle ?? nullptr, s);
    final out = DspEngineInfo(
      versionMajor: s.ref.versionMajor,
      versionMinor: s.ref.versionMinor,
      versionPatch: s.ref.versionPatch,
      sampleRate: s.ref.sampleRate,
      channels: s.ref.channels,
      maxBands: s.ref.maxBands,
      maxFrames: s.ref.maxFrames,
      features: s.ref.features,
    );
    calloc.free(s);
    return out;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    NativeLib.instance.destroy(_handle);
  }

  void _check() {
    if (_disposed) throw StateError('DspEngine disposed');
  }
}

class DspEngineStats {
  const DspEngineStats({
    required this.processCalls,
    required this.totalNs,
    required this.maxNs,
    required this.overrunCount,
    required this.lastFrames,
    required this.sampleRate,
    required this.channels,
  });

  final int processCalls;
  final int totalNs;
  final int maxNs;
  final int overrunCount;
  final int lastFrames;
  final int sampleRate;
  final int channels;
}

class DspEngineInfo {
  const DspEngineInfo({
    required this.versionMajor,
    required this.versionMinor,
    required this.versionPatch,
    required this.sampleRate,
    required this.channels,
    required this.maxBands,
    required this.maxFrames,
    required this.features,
  });

  final int versionMajor;
  final int versionMinor;
  final int versionPatch;
  final int sampleRate;
  final int channels;
  final int maxBands;
  final int maxFrames;
  final int features;

  String get versionString => '$versionMajor.$versionMinor.$versionPatch';
}
