/// Coarse movement states supplied by a host sensor adapter.
///
/// Modes does not access device sensors directly. The host application maps
/// sensor data to this small, deterministic state machine.
enum MotionState {
  unknown,
  stationary,
  moving,
  stopped,
}
