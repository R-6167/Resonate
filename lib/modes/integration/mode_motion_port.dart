import '../models/motion_state.dart';

/// Host-owned motion/activity source consumed by Running Mode.
///
/// The adapter owns platform sensors and lifecycle. Modes only sees the
/// deterministic coarse state needed by its decision engine.
abstract interface class ModeMotionPort {
  MotionState get motionState;
  void start();
  void stop();
  void addListener(void Function() listener);
  void removeListener(void Function() listener);
}
