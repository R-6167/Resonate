#!/usr/bin/env python3
"""Optional auto-enter Driving when Bluetooth reports car context."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch_mode() -> None:
    path = ROOT / "lib/providers/mode_provider.dart"
    t = path.read_text()
    if "autoEnterDrivingOnCar" in t and "setAutoEnterDrivingOnCar" in t:
        print("mode: auto-enter already present")
        return

    if "_autoEnterDrivingKey" not in t:
        t = t.replace(
            "  static const _modeKey = 'resonate_active_mode_v1';\n",
            "  static const _modeKey = 'resonate_active_mode_v1';\n"
            "  static const _autoEnterDrivingKey = 'resonate_auto_enter_driving_on_car_v1';\n",
            1,
        )

    if "bool _autoEnterDrivingOnCar" not in t:
        t = t.replace(
            "  bool _drivingSuggestDismissed = false;\n",
            "  bool _drivingSuggestDismissed = false;\n"
            "  bool _autoEnterDrivingOnCar = false;\n",
            1,
        )

    if "bool get autoEnterDrivingOnCar" not in t:
        t = t.replace(
            "  bool get hasDrivingSuggestion =>\n"
            "      _drivingSuggestOpen && _mode != ResonateMode.driving;\n",
            "  bool get hasDrivingSuggestion =>\n"
            "      _drivingSuggestOpen &&\n"
            "      _mode != ResonateMode.driving &&\n"
            "      !_autoEnterDrivingOnCar;\n"
            "\n"
            "  /// When true, car Bluetooth enters Driving immediately (no banner).\n"
            "  bool get autoEnterDrivingOnCar => _autoEnterDrivingOnCar;\n",
            1,
        )

    # Load pref in _init
    if "_autoEnterDrivingKey" in t and "getBool(_autoEnterDrivingKey)" not in t:
        t = t.replace(
            "      _mode = ResonateModeX.fromId(prefs.getString(_modeKey));\n"
            "      _userOverrides = await _store.loadAll();\n",
            "      _mode = ResonateModeX.fromId(prefs.getString(_modeKey));\n"
            "      _autoEnterDrivingOnCar =\n"
            "          prefs.getBool(_autoEnterDrivingKey) ?? false;\n"
            "      _userOverrides = await _store.loadAll();\n",
            1,
        )

    # setAutoEnterDrivingOnCar method
    if "setAutoEnterDrivingOnCar" not in t:
        t = t.replace(
            "  void dismissDrivingSuggestion() {\n"
            "    _drivingSuggestOpen = false;\n"
            "    _drivingSuggestDismissed = true;\n"
            "    notifyListeners();\n"
            "  }\n",
            "  void dismissDrivingSuggestion() {\n"
            "    _drivingSuggestOpen = false;\n"
            "    _drivingSuggestDismissed = true;\n"
            "    notifyListeners();\n"
            "  }\n"
            "\n"
            "  Future<void> setAutoEnterDrivingOnCar(bool value) async {\n"
            "    if (_autoEnterDrivingOnCar == value) return;\n"
            "    _autoEnterDrivingOnCar = value;\n"
            "    notifyListeners();\n"
            "    try {\n"
            "      final prefs = await SharedPreferences.getInstance();\n"
            "      await prefs.setBool(_autoEnterDrivingKey, value);\n"
            "    } catch (e) {\n"
            "      debugPrint('ModeProvider auto-enter driving: $e');\n"
            "    }\n"
            "    // If already on car audio, apply immediately.\n"
            "    _onBluetoothChanged();\n"
            "  }\n",
            1,
        )

    # Update _onBluetoothChanged for auto-enter
    old = """  void _onBluetoothChanged() {
    final ctx = _bluetooth?.audioContext ?? BluetoothAudioContext.unknown;
    final car = ctx == BluetoothAudioContext.car;

    if (!car) {
      // Reset session dismiss so the next car connection can suggest again.
      final changed = _drivingSuggestOpen || _drivingSuggestDismissed;
      _drivingSuggestOpen = false;
      _drivingSuggestDismissed = false;
      if (changed) notifyListeners();
      return;
    }

    // Already driving — no banner.
    if (_mode == ResonateMode.driving) {
      if (_drivingSuggestOpen) {
        _drivingSuggestOpen = false;
        notifyListeners();
      }
      return;
    }

    if (_drivingSuggestDismissed) return;

    if (!_drivingSuggestOpen) {
      _drivingSuggestOpen = true;
      notifyListeners();
    }
  }
"""
    new = """  void _onBluetoothChanged() {
    final ctx = _bluetooth?.audioContext ?? BluetoothAudioContext.unknown;
    final car = ctx == BluetoothAudioContext.car;

    if (!car) {
      // Reset session dismiss so the next car connection can suggest again.
      final changed = _drivingSuggestOpen || _drivingSuggestDismissed;
      _drivingSuggestOpen = false;
      _drivingSuggestDismissed = false;
      if (changed) notifyListeners();
      return;
    }

    // Already driving — no banner.
    if (_mode == ResonateMode.driving) {
      if (_drivingSuggestOpen) {
        _drivingSuggestOpen = false;
        notifyListeners();
      }
      return;
    }

    // Auto-enter: switch immediately, no prompt.
    if (_autoEnterDrivingOnCar) {
      _drivingSuggestOpen = false;
      _drivingSuggestDismissed = false;
      unawaited(setMode(ResonateMode.driving));
      return;
    }

    if (_drivingSuggestDismissed) return;

    if (!_drivingSuggestOpen) {
      _drivingSuggestOpen = true;
      notifyListeners();
    }
  }
"""
    if old not in t:
        print("mode: _onBluetoothChanged block miss")
    else:
        t = t.replace(old, new, 1)
        print("mode: auto-enter in BT handler")

    # Need dart:async for unawaited if not present
    if "unawaited" in t and "dart:async" not in t:
        t = "import 'dart:async';\n" + t
        print("mode: added dart:async")

    path.write_text(t)


def patch_modes_screen() -> None:
    path = ROOT / "lib/screens/modes_screen.dart"
    t = path.read_text()
    if "autoEnterDrivingOnCar" in t:
        print("modes UI: toggle already")
        return

    marker = "              const SizedBox(height: 12),\n              for (final mode in ResonateMode.values)\n"
    block = """              const SizedBox(height: 12),
              ResonateGlassCard(
                padding: EdgeInsets.zero,
                child: SwitchListTile.adaptive(
                  secondary: const Icon(Icons.directions_car_rounded),
                  title: const Text('Auto-enter Driving in the car'),
                  subtitle: const Text(
                    'When car Bluetooth is detected, switch to Driving immediately. '
                    'Off = ask first.',
                  ),
                  value: modes.autoEnterDrivingOnCar,
                  onChanged: (v) => modes.setAutoEnterDrivingOnCar(v),
                ),
              ),
              const SizedBox(height: 12),
              for (final mode in ResonateMode.values)
"""
    if marker not in t:
        raise SystemExit("modes UI: marker miss")
    t = t.replace(marker, block, 1)
    path.write_text(t)
    print("modes UI: auto-enter toggle")


def main() -> None:
    patch_mode()
    patch_modes_screen()
    print("auto driving done")


if __name__ == "__main__":
    main()
