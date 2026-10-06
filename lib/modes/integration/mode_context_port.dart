/// App-facing context the Modes layer may observe (Bluetooth, motion, etc.).
/// Implement on the host app; Modes never reads platform sensors directly.
abstract class ModeContextPort {
  /// Optional label for the active audio route / BT device.
  String? get activeDeviceLabel;

  /// True when the host believes the user is in a vehicle context.
  bool get isCarContext;
}
