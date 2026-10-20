/// In-memory gain state shared by the leveling refresh and volume paths.
/// The EQ preamp remains a user-controlled attenuation stage; track leveling
/// can only attenuate, and each refresh gets a generation to reject stale work.
class LevelingRuntime {
  double userPreampScale = 1.0;
  double effectivePreampScale = 1.0;
  double trackScale = 1.0;
  int refreshGeneration = 0;

  int beginRefresh() => ++refreshGeneration;

  bool isCurrentRefresh(int generation) => generation == refreshGeneration;

  void setUserPreampScale(double value) {
    userPreampScale = value.clamp(0.25, 1.0).toDouble();
    _recomputeEffectiveScale();
  }

  void setTrackScale(double value) {
    trackScale = value.clamp(0.0, 1.0).toDouble();
    _recomputeEffectiveScale();
  }

  void _recomputeEffectiveScale() {
    effectivePreampScale =
        (userPreampScale * trackScale).clamp(0.0, 1.0).toDouble();
  }
}
