import '../models/media_type.dart';
import '../models/mode_media_item.dart';

/// Central classifier. Duration is deliberately not used as a primary signal.
class MediaClassifier {
  MediaClassifier._();
  static final MediaClassifier instance = MediaClassifier._();

  static const _podcastPath = ['podcast','podcasts','episode','episodes'];
  static const _audiobookPath = ['audiobook','audiobooks','audio book','audio-book','livre audio','hörbuch','horbuch'];
  static const _motivationPath = ['motivation','motivational','speech','speeches','sermon','sermons','talk','ted'];
  static const _musicPath = ['music','songs','tracks','album','albums','dj','mix','mixtape'];

  static const _podcastTitle = ['episode','ep.','ep ','podcast','show notes'];
  static const _audiobookTitle = ['chapter','ch.','part ','audiobook','book '];
  static const _motivationTitle = ['motivation','inspir','sermon','speech','keynote'];

  MediaClassification classify(ModeMediaItem item) {
    final path = item.filePath.toLowerCase().replaceAll('\\', '/');
    final title = item.title.toLowerCase();
    final album = item.album.toLowerCase();
    final artist = item.artist.toLowerCase();
    final blob = '$path | $title | $album | $artist';

    if (_containsAny(path, _audiobookPath)) {
      return const MediaClassification(type: MediaType.audiobook, confidence: .92, source: ClassificationSource.automatic, reason: 'Path/folder suggests audiobook');
    }
    if (_containsAny(path, _podcastPath)) {
      return const MediaClassification(type: MediaType.podcast, confidence: .90, source: ClassificationSource.automatic, reason: 'Path/folder suggests podcast');
    }
    if (_containsAny(path, _motivationPath)) {
      return const MediaClassification(type: MediaType.motivation, confidence: .85, source: ClassificationSource.automatic, reason: 'Path/folder suggests speech/motivation');
    }
    if (_containsAny(path, _musicPath)) {
      return const MediaClassification(type: MediaType.music, confidence: .80, source: ClassificationSource.automatic, reason: 'Path/folder suggests music');
    }
    if (_containsAny(blob, _audiobookTitle)) {
      return const MediaClassification(type: MediaType.audiobook, confidence: .78, source: ClassificationSource.automatic, reason: 'Metadata suggests audiobook');
    }
    if (_containsAny(blob, _podcastTitle)) {
      return const MediaClassification(type: MediaType.podcast, confidence: .75, source: ClassificationSource.automatic, reason: 'Metadata suggests podcast');
    }
    if (_containsAny(blob, _motivationTitle)) {
      return const MediaClassification(type: MediaType.motivation, confidence: .70, source: ClassificationSource.automatic, reason: 'Metadata suggests motivation/speech');
    }

    final sparse = title.trim().isEmpty ||
        title == 'unknown' ||
        (artist.contains('unknown') && album.contains('unknown'));
    if (sparse) {
      return const MediaClassification(type: MediaType.unknown, confidence: .40, source: ClassificationSource.automatic, reason: 'Sparse metadata');
    }

    return const MediaClassification(type: MediaType.music, confidence: .65, source: ClassificationSource.automatic, reason: 'Default music-first classification');
  }

  static bool _containsAny(String haystack, List<String> needles) =>
      needles.any(haystack.contains);
}
