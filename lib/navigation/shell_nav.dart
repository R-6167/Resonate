import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Tab shell coordinator for [HomeScreen].
///
/// Prefer this over [Navigator.push] of [PlayerScreen] so the bottom navigation
/// bar stays visible and only one player surface exists.
class ShellNav extends ChangeNotifier {
  void Function(int index)? _goToTab;

  void bind(void Function(int index) goToTab) {
    _goToTab = goToTab;
  }

  void unbind() {
    _goToTab = null;
  }

  void goToTab(int index) {
    _goToTab?.call(index);
  }

  /// Player tab index in the main shell (For You=0, Library=1, Player=2, Settings=3).
  void goToPlayer() => goToTab(2);
}

/// Switch to the shell Player tab and drop any routes stacked above the shell.
///
/// Call after starting playback from Library, Album, Queue, etc.
void openShellPlayer(BuildContext context) {
  final shell = context.read<ShellNav>();
  final navigator = Navigator.of(context);
  shell.goToPlayer();
  if (navigator.canPop()) {
    navigator.popUntil((route) => route.isFirst);
  }
}
