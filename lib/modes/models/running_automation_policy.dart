/// Safety-oriented timing contract for Running Mode motion automation.
///
/// These values deliberately introduce hysteresis: a single stationary sensor
/// sample must never pause playback, and a brief movement sample must never
/// resume playback.
class RunningAutomationPolicy {
  final Duration stationaryGracePeriod;
  final Duration movingGracePeriod;
  final Duration decisionCooldown;
  final bool suggestPauseAfterStationary;
  final bool suggestResumeAfterMoving;

  const RunningAutomationPolicy({
    this.stationaryGracePeriod = const Duration(seconds: 15),
    this.movingGracePeriod = const Duration(seconds: 5),
    this.decisionCooldown = const Duration(seconds: 10),
    this.suggestPauseAfterStationary = true,
    this.suggestResumeAfterMoving = true,
  });
}
