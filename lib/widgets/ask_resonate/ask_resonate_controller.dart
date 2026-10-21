import 'package:flutter/material.dart';

/// Visual shape used when the Ask Resonate overlay expands.
enum AskResonateShape {
  blob,
  semicircle,
  capsule,
  orbital,
}

/// Global state for the persistent Ask Resonate orb + overlay.
class AskResonateController extends ChangeNotifier {
  bool _isOpen = false;
  AskResonateShape _shape = AskResonateShape.blob;
  String _contextLabel = 'For You';
  Offset? _orbGlobalPosition;

  bool get isOpen => _isOpen;
  AskResonateShape get shape => _shape;
  String get contextLabel => _contextLabel;
  Offset? get orbGlobalPosition => _orbGlobalPosition;

  void open({AskResonateShape? shape}) {
    if (shape != null) _shape = shape;
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
    notifyListeners();
  }

  void updateOrbGlobalPosition(Offset? position) {
    _orbGlobalPosition = position;
  }
}
