class MusicProvider extends ChangeNotifier {
  final AudioHandler? audioHandler;
  final AudioPlayer audioPlayer = AudioPlayer();

  MusicProvider({this.audioHandler}) {
    // If an audioHandler exists, you may want to listen to its playbackState/mediaItem streams:
    audioHandler?.playbackState.listen((state) {
      // map state.playing etc to provider fields as needed
    });
    audioPlayer.positionStream.listen((pos) {
      currentPosition = pos;
      notifyListeners();
    });
    // existing initialization...
  }

  Future<void> playSong(Song song) async {
    // if audioHandler provided, use it to play via MediaItem
    if (audioHandler != null) {
      final mediaItem = MediaItem(
        id: song.id,
        album: song.album,
        title: song.title,
        artist: song.artist,
        duration: song.duration,
        extras: {'filePath': song.filePath},
      );
      await audioHandler!.addQueueItem(mediaItem);
      await audioHandler!.play();
      // sync local fields to audioHandler.mediaItem stream if necessary
      return;
    }

    // fallback: existing just_audio local player usage
    ...
  }

  // For seek/play/pause/next/previous: call audioHandler?.seek(...)/play()/pause() etc when provided
}
