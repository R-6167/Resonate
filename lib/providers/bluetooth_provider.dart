import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BluetoothSettings {
  bool enabled;
  bool showNotification;
  bool resumeOnConnect;
  bool pauseOnDisconnect;
  int mediaButtonBehavior;

  BluetoothSettings({
    this.enabled = true,
    this.showNotification = true,
    this.resumeOnConnect = false,
    this.pauseOnDisconnect = false,
    this.mediaButtonBehavior = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'showNotification': showNotification,
      'resumeOnConnect': resumeOnConnect,
      'pauseOnDisconnect': pauseOnDisconnect,
      'mediaButtonBehavior': mediaButtonBehavior,
    };
  }

  factory BluetoothSettings.fromMap(
    Map<String, dynamic> map,
  ) {
    return BluetoothSettings(
      enabled: map['enabled'] ?? true,
      showNotification: map['showNotification'] ?? true,
      resumeOnConnect: map['resumeOnConnect'] ?? false,
      pauseOnDisconnect: map['pauseOnDisconnect'] ?? false,
      mediaButtonBehavior: map['mediaButtonBehavior'] ?? 0,
    );
  }
}

class BluetoothProvider extends ChangeNotifier {
  late BluetoothSettings _settings;

  bool _bluetoothConnected = false;
  String _connectedDeviceName = '';

  int _buttonPressCount = 0;
  DateTime _lastButtonPress = DateTime.now();

  BluetoothProvider() {
    _settings = BluetoothSettings();

    _loadBluetoothSettings();
    _initializeBluetoothListeners();
  }

  // ---------------------------------------------------------------------------
  // GETTERS
  // ---------------------------------------------------------------------------

  BluetoothSettings get settings => _settings;

  bool get bluetoothConnected => _bluetoothConnected;

  String get connectedDeviceName => _connectedDeviceName;

  bool get isEnabled => _settings.enabled;

  bool get showNotification => _settings.showNotification;

  bool get resumeOnConnect => _settings.resumeOnConnect;

  bool get pauseOnDisconnect => _settings.pauseOnDisconnect;

  // ---------------------------------------------------------------------------
  // LOAD SETTINGS
  // ---------------------------------------------------------------------------

  Future<void> _loadBluetoothSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final enabled =
          prefs.getBool('bt_enabled') ?? true;

      final showNotification =
          prefs.getBool('bt_show_notification') ?? true;

      final resumeOnConnect =
          prefs.getBool('bt_resume_on_connect') ?? false;

      final pauseOnDisconnect =
          prefs.getBool('bt_pause_on_disconnect') ?? false;

      final mediaButtonBehavior =
          prefs.getInt('bt_button_behavior') ?? 0;

      _settings = BluetoothSettings(
        enabled: enabled,
        showNotification: showNotification,
        resumeOnConnect: resumeOnConnect,
        pauseOnDisconnect: pauseOnDisconnect,
        mediaButtonBehavior: mediaButtonBehavior,
      );

      notifyListeners();
    } catch (e) {
      debugPrint(
        'Error loading Bluetooth settings: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // SAVE SETTINGS
  // ---------------------------------------------------------------------------

  Future<void> _saveBluetoothSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool(
        'bt_enabled',
        _settings.enabled,
      );

      await prefs.setBool(
        'bt_show_notification',
        _settings.showNotification,
      );

      await prefs.setBool(
        'bt_resume_on_connect',
        _settings.resumeOnConnect,
      );

      await prefs.setBool(
        'bt_pause_on_disconnect',
        _settings.pauseOnDisconnect,
      );

      await prefs.setInt(
        'bt_button_behavior',
        _settings.mediaButtonBehavior,
      );
    } catch (e) {
      debugPrint(
        'Error saving Bluetooth settings: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // INITIALIZE BLUETOOTH
  // ---------------------------------------------------------------------------

  void _initializeBluetoothListeners() {
    // Actual Bluetooth integration can be connected here.
    //
    // At present this provider manages Bluetooth-related settings
    // and connection state, but does not directly control the
    // device Bluetooth radio.
    debugPrint(
      'Bluetooth listeners initialized',
    );
  }

  // ---------------------------------------------------------------------------
  // BLUETOOTH SETTINGS
  // ---------------------------------------------------------------------------

  Future<void> toggleBluetooth(
    bool enabled,
  ) async {
    _settings.enabled = enabled;

    await _saveBluetoothSettings();

    notifyListeners();
  }

  Future<void> toggleNotification(
    bool show,
  ) async {
    _settings.showNotification = show;

    await _saveBluetoothSettings();

    notifyListeners();
  }

  Future<void> toggleResumeOnConnect(
    bool enabled,
  ) async {
    _settings.resumeOnConnect = enabled;

    await _saveBluetoothSettings();

    notifyListeners();
  }

  Future<void> togglePauseOnDisconnect(
    bool enabled,
  ) async {
    _settings.pauseOnDisconnect = enabled;

    await _saveBluetoothSettings();

    notifyListeners();
  }

  Future<void> setMediaButtonBehavior(
    int behavior,
  ) async {
    _settings.mediaButtonBehavior = behavior;

    await _saveBluetoothSettings();

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // BLUETOOTH CONNECTION STATE
  // ---------------------------------------------------------------------------

  void handleBluetoothConnected(
    String deviceName,
  ) {
    _bluetoothConnected = true;
    _connectedDeviceName = deviceName;

    debugPrint(
      'Bluetooth connected: $deviceName',
    );

    notifyListeners();
  }

  void handleBluetoothDisconnected() {
    _bluetoothConnected = false;
    _connectedDeviceName = '';

    debugPrint(
      'Bluetooth disconnected',
    );

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // MEDIA BUTTON HANDLING
  // ---------------------------------------------------------------------------

  String handleMediaButtonPress() {
    final now = DateTime.now();

    final timeSinceLastPress =
        now.difference(_lastButtonPress).inMilliseconds;

    // More than 300 ms between presses means this is
    // the beginning of a new press sequence.
    if (timeSinceLastPress > 300) {
      _buttonPressCount = 1;
    } else {
      _buttonPressCount++;
    }

    _lastButtonPress = now;

    switch (_settings.mediaButtonBehavior) {
      case 0:
        // Single tap = Play/Pause
        // Double tap = Next
        // Triple tap = Previous

        if (_buttonPressCount == 1) {
          return 'play_pause';
        }

        if (_buttonPressCount == 2) {
          return 'next';
        }

        if (_buttonPressCount >= 3) {
          _buttonPressCount = 0;
          return 'previous';
        }

        return 'play_pause';

      case 1:
        // Always Play/Pause
        return 'play_pause';

      case 2:
        // Always Next
        return 'next';

      default:
        return 'play_pause';
    }
  }

  // ---------------------------------------------------------------------------
  // MEDIA BUTTON DESCRIPTION
  // ---------------------------------------------------------------------------

  String getButtonBehaviorDescription(
    int behavior,
  ) {
    switch (behavior) {
      case 0:
        return 'Single tap: Play/Pause, Double: Next, Triple: Previous';

      case 1:
        return 'Always Play/Pause';

      case 2:
        return 'Always Next';

      default:
        return 'Unknown';
    }
  }

  // ---------------------------------------------------------------------------
  // CONNECTION STATUS
  // ---------------------------------------------------------------------------

  String getConnectionStatus() {
    if (!_bluetoothConnected) {
      return 'No device connected';
    }

    return 'Connected to $_connectedDeviceName';
  }
}
