/// Context adapter implemented by the main app (Bluetooth/car detection, etc.).
enum ModeAudioContext {
  unknown,
  car,
}

abstract interface class ModeContextPort {
  ModeAudioContext get audioContext;
  void addListener(void Function() listener);
  void removeListener(void Function() listener);
}
