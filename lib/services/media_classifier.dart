import '../models/media_type.dart';
import '../models/song.dart';

/// Central Media Classifier. Modes must not invent their own content guesses.
///
/// Signals (no duration as primary):
/// path/folder, title, album, artist, light keyword heuristics.
class MediaClassifier {
  MediaClassifier._();
  static final MediaClassifier instance = MediaClassifier._();

  static const _podcastPath = [
    'podcast',
    'podcasts',
    'episode',
    'episodes',
  ];
  static const _audiobookPath = [
    'audiobook',
    'audiobooks',
    'audio book',
    'audio-book',
    'livre audio',
    'hörbuch',
    'horbuch',
  ];
  static const _motivationPath = [
    'motivation',
    'motivational',
    'speech',
    'speeches',
    'sermon',
    'sermons',
    'talk',
    'ted',
  ];
  static const _musicPath = [
    'music',
    'songs',
    'tracks',
    'album',
    'albums',
    'dj',
    'mix',
    'mixtape',
  ];

  static const _podcastTitle = [
    'episode',
    'ep.',
    'ep ',
    'podcast',
    'show notes',
  ];
  static const _audiobookTitle = [
    'chapter',
    'ch.',
    'part ',
    'audiobook',
    'book ',
  ];
  static const _motivationTitle = [
    'motivation',
    'inspir',
    'sermon',
    'speech',
    'keynote',
  ];

  MediaClassification classify(Song song) {
    final path = song.filePath.toLowerCase().replaceAll('\\', '/');
    final title = song.title.toLowerCase();
    final album = song.album.toLowerCase();
    final artist = song.artist.toLowerCase();
    final blob = '$path | $title | $album | $artist';

    // Path / folder signals (strong).
    if (_containsAny(path, _audiobookPath)) {
      return const MediaClassification(
        type: MediaType.audiobook,
        confidence: 0.92,
        source: ClassificationSource.automatic,
        reason: 'Path/folder suggests audiobook',
      );
    }
    if (_containsAny(path, _podcastPath)) {
      return const MediaClassification(
        type: MediaType.podcast,
        confidence: 0.9,
        source: ClassificationSource.automatic,
        reason: 'Path/folder suggests podcast',
      );
    }
    if (_containsAny(path, _motivationPath)) {
      return const MediaClassification(
        type: MediaType.motivation,
        confidence: 0.85,
        source: ClassificationSource.automatic,
        reason: 'Path/folder suggests speech/motivation',
      );
    }
    if (_containsAny(path, _musicPath)) {
      return const MediaClassification(
        type: MediaType.music,
        confidence: 0.8,
        source: ClassificationSource.automatic,
        reason: 'Path/folder suggests music',
      );
    }

    // Title / album / artist keywords (medium).
    if (_containsAny(blob, _audiobookTitle)) {
      return const MediaClassification(
        type: MediaType.audiobook,
        confidence: 0.78,
        source: ClassificationSource.automatic,
        reason: 'Title/album keywords suggest audiobook',
      );
    }
    if (_containsAny(blob, _podcastTitle)) {
      return const MediaClassification(
        type: MediaType.podcast,
        confidence: 0.75,
        source: ClassificationSource.automatic,
        reason: 'Title/album keywords suggest podcast',
      );
    }
    if (_containsAny(blob, _motivationTitle)) {
      return const MediaClassification(
        type: MediaType.motivation,
        confidence: 0.7,
        source: ClassificationSource.automatic,
        reason: 'Title/album keywords suggest motivation/speech',
      );
    }

    // Default: treat as music with moderate confidence (library is music-first).
    // Unknown only when almost no metadata.
    final sparse = title.trim().isEmpty ||
        title == 'unknown' ||
        (artist.contains('unknown') && album.contains('unknown'));
    if (sparse) {
      return const MediaClassification(
        type: MediaType.unknown,
        confidence: 0.4,
        source: ClassificationSource.automatic,
        reason: 'Sparse metadata',
      );
    }

    return const MediaClassification(
      type: MediaType.music,
      confidence: 0.65,
      source: ClassificationSource.automatic,
      reason: 'Default music-first classification',
    );
  }

  static bool _containsAny(String haystack, List<String> needles) {
    for (final n in needles) {
      if (haystack.contains(n)) return true;
    }
    return false;
  }
}
