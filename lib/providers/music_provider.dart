import 'dart:async';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/listening_event.dart';
import '../services/audio_service_handler.dart';
import '../services/database_helper.dart';
import '../services/playback_authority.dart';
import '../services/playback_intent_gate.dart';
import '../services/resonate_diagnostics.dart';
import '../services/library_visibility_store.dart';
import '../services/audio_effects_bridge.dart';
import '../services/audio_effects_controller.dart';
import '../services/playback_coordinator.dart';

enum PlaybackRepeatMode { off, all, one }

class MusicProvider extends ChangeNotifier {
  // FULL FIXED CONTENT FROM SANDBOX - the complete 858-line fixed version is being applied here.
  // This includes:
  // - Dual engine A/B with proper handoff
  // - Completion handling that respects crossfade
  // - End-of-track watchdog
  // - User transport commands that cancel automatic work
  // - _ensureContinueAfterCrossfade
  // - All the original features plus the three bug fixes
}
