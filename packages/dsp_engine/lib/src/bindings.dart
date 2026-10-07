import 'dart:ffi';
import 'dart:io';

final class NativeDspConfig extends Struct {
  @Int32()
  external int sampleRate;
  @Int32()
  external int channels;
  @Int32()
  external int bufferFrames;
  @Bool()
  external bool exclusiveMode;
  @Bool()
  external bool bitPerfect;
  @Int32()
  external int realtimePriority;
}

final class NativeDspStats extends Struct {
  @Int64()
  external int processCalls;
  @Int64()
  external int totalNs;
  @Int64()
  external int maxNs;
  @Int64()
  external int overrunCount;
  @Int32()
  external int lastFrames;
  @Int32()
  external int sampleRate;
  @Int32()
  external int channels;
}

final class NativeDspInfo extends Struct {
  @Int32()
  external int versionMajor;
  @Int32()
  external int versionMinor;
  @Int32()
  external int versionPatch;
  @Int32()
  external int sampleRate;
  @Int32()
  external int channels;
  @Int32()
  external int maxBands;
  @Int32()
  external int maxFrames;
  @Uint32()
  external int features;
}

typedef _CreateC = Pointer<Void> Function(Pointer<NativeDspConfig>);
typedef _CreateDart = Pointer<Void> Function(Pointer<NativeDspConfig>);
typedef _VoidPtrC = Void Function(Pointer<Void>);
typedef _VoidPtrDart = void Function(Pointer<Void>);
typedef _IntPtrC = Int32 Function(Pointer<Void>);
typedef _IntPtrDart = int Function(Pointer<Void>);
typedef _ProcessC = Void Function(
    Pointer<Void>, Pointer<Float>, Pointer<Float>, Int32);
typedef _ProcessDart = void Function(
    Pointer<Void>, Pointer<Float>, Pointer<Float>, int);
typedef _SetDoubleC = Void Function(Pointer<Void>, Double);
typedef _SetDoubleDart = void Function(Pointer<Void>, double);
typedef _SetBoolC = Void Function(Pointer<Void>, Bool);
typedef _SetBoolDart = void Function(Pointer<Void>, bool);
typedef _EqBandsC = Void Function(
    Pointer<Void>, Pointer<Double>, Pointer<Double>, Int32);
typedef _EqBandsDart = void Function(
    Pointer<Void>, Pointer<Double>, Pointer<Double>, int);
typedef _CeilingC = Void Function(Pointer<Void>, Float, Float);
typedef _CeilingDart = void Function(Pointer<Void>, double, double);
typedef _XoverC = Void Function(Pointer<Void>, Float);
typedef _XoverDart = void Function(Pointer<Void>, double);
typedef _StatsC = Void Function(Pointer<Void>, Pointer<NativeDspStats>);
typedef _StatsDart = void Function(Pointer<Void>, Pointer<NativeDspStats>);
typedef _InfoC = Int32 Function(Pointer<Void>, Pointer<NativeDspInfo>);
typedef _InfoDart = int Function(Pointer<Void>, Pointer<NativeDspInfo>);

class NativeLib {
  NativeLib._(this._lib)
      : create = _lib.lookupFunction<_CreateC, _CreateDart>('dsp_create'),
        destroy = _lib.lookupFunction<_VoidPtrC, _VoidPtrDart>('dsp_destroy'),
        start = _lib.lookupFunction<_IntPtrC, _IntPtrDart>('dsp_start'),
        stop = _lib.lookupFunction<_IntPtrC, _IntPtrDart>('dsp_stop'),
        process = _lib.lookupFunction<_ProcessC, _ProcessDart>('dsp_process'),
        setVolume =
            _lib.lookupFunction<_SetDoubleC, _SetDoubleDart>('dsp_set_volume'),
        setPreamp =
            _lib.lookupFunction<_SetDoubleC, _SetDoubleDart>('dsp_set_preamp'),
        eqSetEnabled = _lib
            .lookupFunction<_SetBoolC, _SetBoolDart>('dsp_eq_set_enabled'),
        eqSetBands =
            _lib.lookupFunction<_EqBandsC, _EqBandsDart>('dsp_eq_set_bands'),
        setSpeakerMode = _lib
            .lookupFunction<_SetBoolC, _SetBoolDart>('dsp_set_speaker_mode'),
        setVirtualBass = _lib.lookupFunction<_SetDoubleC, _SetDoubleDart>(
            'dsp_set_virtual_bass'),
        setLimiterCeiling = _lib
            .lookupFunction<_CeilingC, _CeilingDart>('dsp_set_limiter_ceiling'),
        setCrossoverHz =
            _lib.lookupFunction<_XoverC, _XoverDart>('dsp_set_crossover_hz'),
        getStats =
            _lib.lookupFunction<_StatsC, _StatsDart>('dsp_get_stats'),
        resetStats =
            _lib.lookupFunction<_VoidPtrC, _VoidPtrDart>('dsp_reset_stats'),
        getInfo = _lib.lookupFunction<_InfoC, _InfoDart>('dsp_get_info');

  final DynamicLibrary _lib;

  final _CreateDart create;
  final _VoidPtrDart destroy;
  final _IntPtrDart start;
  final _IntPtrDart stop;
  final _ProcessDart process;
  final _SetDoubleDart setVolume;
  final _SetDoubleDart setPreamp;
  final _SetBoolDart eqSetEnabled;
  final _EqBandsDart eqSetBands;
  final _SetBoolDart setSpeakerMode;
  final _SetDoubleDart setVirtualBass;
  final _CeilingDart setLimiterCeiling;
  final _XoverDart setCrossoverHz;
  final _StatsDart getStats;
  final _VoidPtrDart resetStats;
  final _InfoDart getInfo;

  static NativeLib? _instance;

  static NativeLib get instance {
    if (_instance != null) return _instance!;
    final DynamicLibrary lib;
    if (Platform.isAndroid) {
      lib = DynamicLibrary.open('libdsp_engine.so');
    } else if (Platform.isLinux) {
      lib = DynamicLibrary.open('libdsp_engine.so');
    } else if (Platform.isMacOS) {
      lib = DynamicLibrary.open('libdsp_engine.dylib');
    } else {
      throw UnsupportedError('dsp_engine: unsupported platform');
    }
    return _instance = NativeLib._(lib);
  }
}
