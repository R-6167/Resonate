/// Bookkeeping for the bounded concatenating-source window.
///
/// MusicProvider remains responsible for constructing and mutating the native
/// audio source; this object only owns the window metadata.
class GaplessWindowState {
  int start = 0;
  List<String> songIds = const [];
  bool active = false;

  void reset() {
    active = false;
    songIds = const [];
  }

  void activate({required int windowStart, required List<String> ids}) {
    start = windowStart;
    songIds = List<String>.unmodifiable(ids);
    active = true;
  }

  int localIndexOf(String songId) => songIds.indexOf(songId);
}
