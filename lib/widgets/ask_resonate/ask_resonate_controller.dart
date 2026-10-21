import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Visual shape used when the Ask Resonate overlay expands.
enum AskResonateShape {
  blob,
  semicircle,
  capsule,
  orbital,
}

/// Global state for the persistent Ask Resonate orb + overlay.
class AskResonateController extends ChangeNotifier {
  static const _shapePreferenceKey = 'ask_resonate_selected_shape_v1';

  AskResonateController() { _loadShape(); }

  Future<void> _loadShape() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_shapePreferenceKey);
      final match = AskResonateShape.values.where((value) => value.name == stored);
      if (!_shapeTouched && match.isNotEmpty && match.first != _shape) {
        _shape = match.first;
        notifyListeners();
      }
    } catch (_) {
      // Keep the safe default shape when preferences are unavailable.
    }
  }

  bool _isOpen = false;
  bool _shapeTouched = false;
  AskResonateShape _shape = AskResonateShape.blob;
  String _contextLabel = 'For You';
  Offset? _orbGlobalPosition;

  bool get isOpen => _isOpen;
  AskResonateShape get shape => _shape;
  String get contextLabel => _contextLabel;
  Offset? get orbGlobalPosition => _orbGlobalPosition;

  void open({AskResonateShape? shape}) {
    if (shape != null) setShape(shape);
    if (_isOpen) {
      notifyListeners();
      return;
    }
    _isOpen = true;
    notifyListeners();
  }

  void close() {
    if (!_isOpen) return;
    _isOpen = false;
    notifyListeners();
  }

  void toggle({AskResonateShape? shape}) {
    if (_isOpen) {
      close();
    } else {
      open(shape: shape);
    }
  }

  void setContext(String label) {
    final next = label.trim();
    if (next.isEmpty || next == _contextLabel) return;
    _contextLabel = next;
    notifyListeners();
  }

  void setShape(AskResonateShape shape) {
    if (_shape == shape) return;
    _shape = shape;
    _shapeTouched = true;
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) => prefs.setString(_shapePreferenceKey, shape.name)).catchError((_) => false);
  }

  void updateOrbGlobalPosition(Offset? position) {
    _orbGlobalPosition = position;
  }
}
