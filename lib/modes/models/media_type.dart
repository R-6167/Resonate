/// Primary media kinds used by the Media Classifier and Mode Engine.
///
/// Duration is intentionally not a primary classification signal.
enum MediaType {
  music,
  podcast,
  audiobook,
  motivation,
  unknown,
}

extension MediaTypeX on MediaType {
  String get label => switch (this) {
        MediaType.music => 'Music',
        MediaType.podcast => 'Podcast',
        MediaType.audiobook => 'Audiobook',
        MediaType.motivation => 'Motivation / Speech',
        MediaType.unknown => 'Unknown',
      };

  String get storageKey => name;

  static MediaType fromStorage(String? raw) {
    if (raw == null || raw.isEmpty) return MediaType.unknown;
    return MediaType.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => MediaType.unknown,
    );
  }
}

enum ClassificationSource {
  automatic,
  user,
}

class MediaClassification {
  final MediaType type;
  final double confidence;
  final ClassificationSource source;
  final String? reason;

  const MediaClassification({
    required this.type,
    required this.confidence,
    required this.source,
    this.reason,
  });

  bool get isUserOverride => source == ClassificationSource.user;

  MediaClassification copyWith({
    MediaType? type,
    double? confidence,
    ClassificationSource? source,
    String? reason,
  }) {
    return MediaClassification(
      type: type ?? this.type,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
      reason: reason ?? this.reason,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.storageKey,
        'confidence': confidence,
        'source': source.name,
        if (reason != null) 'reason': reason,
      };

  factory MediaClassification.fromJson(Map<String, dynamic> json) {
    return MediaClassification(
      type: MediaTypeX.fromStorage(json['type'] as String?),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      source: (json['source'] as String?) == 'user'
          ? ClassificationSource.user
          : ClassificationSource.automatic,
      reason: json['reason'] as String?,
    );
  }
}
