import '../models/media_type.dart';
import '../models/mode_media_item.dart';

/// Conservative metadata classifier.
///
/// Duration is intentionally not a primary signal: long DJ/music mixes must
/// remain music. Classification is a hint; user overrides always win.
class MediaClassifier {
  MediaClassifier._();
  static final MediaClassifier instance = MediaClassifier._();

  static const _podcastPath = ['podcast', 'podcasts'];
  static const _audiobookPath = [
    'audiobook', 'audiobooks', 'audio book', 'audio-book',
    'livre audio', 'hörbuch', 'horbuch'
  ];
  static const _motivationPath = [
    'motivation', 'motivational', 'speech', 'speeches',
    'sermon', 'sermons', 'talk', 'ted'
  ];
  static const _musicPath = [
    'music', 'songs', 'tracks', 'album', 'albums',
    'dj', 'mix', 'mixtape'
  ];

  static const _podcastTitle = [
    'episode', 'episode ', 'ep.', 'ep ', 'podcast', 'show notes'
  ];
  static const _audiobookTitle = [
    'chapter', 'ch.', 'chapter ', 'part ', 'audiobook', 'audio book'
  ];
  static const _motivationTitle = [
    'motivation', 'motivational', 'inspir', 'sermon', 'speech', 'keynote'
  ];

  MediaClassification classify(ModeMediaItem item) {
    final path = item.filePath.toLowerCase().replaceAll('\\', '/');
    final title = item.title.trim().toLowerCase();
    final album = item.album.trim().toLowerCase();
    final artist = item.artist.trim().toLowerCase();

    // Path/folder evidence is strongest because it is explicit organization.
    final pathResult = _classifyPath(path);
    if (pathResult != null) return pathResult;

    final metadata = '$title | $album | $artist';

    if (_containsAny(metadata, _audiobookTitle)) {
      return const MediaClassification(
        type: MediaType.audiobook, confidence: .78,
        source: ClassificationSource.automatic,
        reason: 'Metadata suggests audiobook',
      );
    }
    if (_containsAny(metadata, _podcastTitle)) {
      return const MediaClassification(
        type: MediaType.podcast, confidence: .75,
        source: ClassificationSource.automatic,
        reason: 'Metadata suggests podcast',
      );
    }
    if (_containsAny(metadata, _motivationTitle)) {
      return const MediaClassification(
        type: MediaType.motivation, confidence: .70,
        source: ClassificationSource.automatic,
        reason: 'Metadata suggests speech/motivation',
      );
    }

    final sparse = title.isEmpty || title == 'unknown' ||
        (artist.isEmpty && album.isEmpty) ||
        (artist == 'unknown' && album == 'unknown');
    if (sparse) {
      return const MediaClassification(
        type: MediaType.unknown, confidence: .40,
        source: ClassificationSource.automatic,
        reason: 'Sparse metadata',
      );
    }

    return const MediaClassification(
      type: MediaType.music, confidence: .65,
      source: ClassificationSource.automatic,
      reason: 'Conservative music-first fallback',
    );
  }

  MediaClassification? _classifyPath(String path) {
    if (_containsAny(path, _audiobookPath)) {
      return const MediaClassification(
        type: MediaType.audiobook, confidence: .92,
        source: ClassificationSource.automatic,
        reason: 'Path/folder suggests audiobook',
      );
    }
    if (_containsAny(path, _podcastPath)) {
      return const MediaClassification(
        type: MediaType.podcast, confidence: .90,
        source: ClassificationSource.automatic,
        reason: 'Path/folder suggests podcast',
      );
    }
    if (_containsAny(path, _motivationPath)) {
      return const MediaClassification(
        type: MediaType.motivation, confidence: .85,
        source: ClassificationSource.automatic,
        reason: 'Path/folder suggests speech/motivation',
      );
    }
    if (_containsAny(path, _musicPath)) {
      return const MediaClassification(
        type: MediaType.music, confidence: .80,
        source: ClassificationSource.automatic,
        reason: 'Path/folder suggests music',
      );
    }
    return null;
  }

  static bool _containsAny(String haystack, List<String> needles) =>
      needles.any(haystack.contains);
}
