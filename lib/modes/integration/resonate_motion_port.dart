import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import '../models/motion_state.dart';
import 'mode_motion_port.dart';

/// Real device motion adapter. Sensor ownership stays outside Modes.
class ResonateMotionPort implements ModeMotionPort {
  ResonateMotionPort({
    this.samplingPeriod = const Duration(milliseconds: 500),
    this.movingThreshold = 2.0,
    this.stationaryThreshold = 0.8,
  });

  final Duration samplingPeriod;
  final double movingThreshold;
  final double stationaryThreshold;
  final List<void Function()> _listeners = <void Function()>[];
  StreamSubscription<UserAccelerometerEvent>? _subscription;
  MotionState _motionState = MotionState.unknown;

  @override
  MotionState get motionState => _motionState;

  @override
  void start() {
    if (_subscription != null) return;
    _subscription = userAccelerometerEventStream(
      samplingPeriod: samplingPeriod,
    ).listen(
      _onSample,
      onError: (_) => _setState(MotionState.unknown),
      cancelOnError: false,
    );
  }

  void _onSample(UserAccelerometerEvent event) {
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    final next = magnitude >= movingThreshold
        ? MotionState.moving
        : magnitude <= stationaryThreshold
            ? MotionState.stationary
            : _motionState;
    if (next != _motionState) _setState(next);
  }

  void _setState(MotionState next) {
    if (_motionState == next) return;
    _motionState = next;
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  @override
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _setState(MotionState.unknown);
  }

  @override
  void addListener(void Function() listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  @override
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void dispose() {
    stop();
    _listeners.clear();
  }
}
