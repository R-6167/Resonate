class AudioVisualizationSettings {
  final bool enabled;
  final String visualizationType;

  const AudioVisualizationSettings({
    this.enabled = false,
    this.visualizationType = 'bars',
  });

  AudioVisualizationSettings copyWith({
    bool? enabled,
    String? visualizationType,
  }) {
    return AudioVisualizationSettings(
      enabled: enabled ?? this.enabled,
      visualizationType:
          visualizationType ?? this.visualizationType,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'visualizationType': visualizationType,
    };
  }

  factory AudioVisualizationSettings.fromMap(
    Map<String, dynamic> map,
  ) {
    return AudioVisualizationSettings(
      enabled: map['enabled'] as bool? ?? false,
      visualizationType:
          map['visualizationType'] as String? ?? 'bars',
    );
  }
}
