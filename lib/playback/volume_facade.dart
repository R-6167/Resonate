/// Small state facade for user/system volume and sleep-fade attenuation.
/// Native platform calls and transition-aware application remain in MusicProvider.
class VolumeFacade {
  double userVolume = 1.0;
  double sleepFadeScale = 1.0;
  int systemVolumePollGeneration = 0;

  void setUserVolume(double value) {
    userVolume = value.clamp(0.0, 1.0).toDouble();
  }

  void setSleepFadeScale(double value) {
    sleepFadeScale = value.clamp(0.0, 1.0).toDouble();
  }

  int beginSystemVolumePoll() => ++systemVolumePollGeneration;

  bool isCurrentSystemVolumePoll(int generation) =>
      generation == systemVolumePollGeneration;

  /// Returns true only when a meaningful normalized volume change occurred.
  bool updateSystemVolume(double current, double max) {
    if (max <= 0) return false;
    final next = (current / max).clamp(0.0, 1.0).toDouble();
    if ((next - userVolume).abs() <= 0.001) return false;
    userVolume = next;
    return true;
  }
}
