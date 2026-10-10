import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../modes/integration/resonate_mode_ports.dart';
import '../modes/models/resonate_mode.dart';
import '../modes/providers/mode_provider.dart';
import '../modes/screens/modes_screen.dart';

/// Compact listening-mode chip — same language as [DjModeStatusChip].
///
/// Tapping opens Modes settings. Always visible so the active mode is obvious
/// on Home and Now Playing (Normal included, quieter styling).
class ResonateModeChip extends StatelessWidget {
  const ResonateModeChip({
    super.key,
    this.dense = false,
    this.showNormal = true,
  });

  final bool dense;

  /// When false, hides the chip in Normal mode (still shows for all others).
  final bool showNormal;

  @override
  Widget build(BuildContext context) {
    return Consumer<ModeProvider>(
      builder: (context, modes, _) {
        // Keep the identifier visible while persisted Mode state restores.
        // The Consumer rebuilds with the restored active Mode when ready.
        final mode = modes.mode;
        if (!showNormal && mode == ResonateMode.normal) {
          return const SizedBox.shrink();
        }

        final scheme = Theme.of(context).colorScheme;
        final active = mode != ResonateMode.normal;
        final label = dense
            ? (active ? mode.label : 'Normal')
            : (active ? 'Mode · ${mode.label}' : 'Mode · Normal');

        final chip = Chip(
          visualDensity:
              dense ? VisualDensity.compact : VisualDensity.standard,
          avatar: Icon(
            _iconFor(mode),
            size: dense ? 15 : 17,
            color: active ? scheme.tertiary : scheme.onSurfaceVariant,
          ),
          label: Text(
            label,
            style: TextStyle(
              fontSize: dense ? 11.5 : 13,
              fontWeight: FontWeight.w600,
              color: active ? null : scheme.onSurfaceVariant,
            ),
          ),
          side: active
              ? BorderSide(color: scheme.tertiary.withValues(alpha: 0.4))
              : null,
        );

        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<
                    void>(
                  builder: (_) => ModesScreen(
                    folderPicker: const ResonateModeFolderPickerPort(),
                  ),
                ),
              );
            },
            child: chip,
          ),
        );
      },
    );
  }

  static IconData _iconFor(ResonateMode mode) => switch (mode) {
        ResonateMode.normal => Icons.music_note_rounded,
        ResonateMode.running => Icons.directions_run_rounded,
        ResonateMode.driving => Icons.directions_car_rounded,
        ResonateMode.work => Icons.work_outline_rounded,
        ResonateMode.podcast => Icons.podcasts_rounded,
        ResonateMode.motivation => Icons.local_fire_department_rounded,
        ResonateMode.audiobook => Icons.menu_book_rounded,
      };
}
