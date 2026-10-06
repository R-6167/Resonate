/// User actions that Modes can protect or simplify.
///
/// Modes do not execute these actions; they only describe the interaction
/// requirements that the host UI must enforce.
enum ModeAction {
  playPause,
  next,
  previous,
  seek,
  volume,
  queue,
  shuffle,
  modeChange,
  settings,
  seekForward,
  seekBackward,
}

extension ModeActionX on ModeAction {
  bool get isPlaybackAction => switch (this) {
        ModeAction.playPause ||
        ModeAction.next ||
        ModeAction.previous ||
        ModeAction.seek ||
        ModeAction.volume ||
        ModeAction.seekForward ||
        ModeAction.seekBackward => true,
        _ => false,
      };
}
