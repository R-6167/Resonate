import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QueueProvider extends ChangeNotifier {
  static const _prefsKey = 'resonate_queue_ids';
  final List<String> _queue = [];

  List<String> get queueIds => List.unmodifiable(_queue);

  QueueProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_prefsKey) ?? [];
    _queue.clear();
    _queue.addAll(ids);
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _queue);
  }

  Future<void> setQueue(List<String> ids) async {
    _queue
      ..clear()
      ..addAll(ids);
    await _save();
    notifyListeners();
  }

  Future<void> addToQueue(String id) async {
    _queue.add(id);
    await _save();
    notifyListeners();
  }

  Future<void> removeFromQueue(String id) async {
    _queue.remove(id);
    await _save();
    notifyListeners();
  }

  Future<void> move(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length) return;
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    await _save();
    notifyListeners();
  }

  Future<void> clear() async {
    _queue.clear();
    await _save();
    notifyListeners();
  }
}
