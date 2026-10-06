/// Minimal media metadata required by Modes.
///
/// This keeps the Modes module independent from Resonate's Song model.
class ModeMediaItem {
  final String id;
  final String filePath;
  final String title;
  final String album;
  final String artist;

  const ModeMediaItem({
    required this.id,
    required this.filePath,
    required this.title,
    this.album = '',
    this.artist = '',
  });
}
