import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/eq_lean_store.dart';
import '../services/resonate_dsp_pipeline.dart';
import '../services/dsp_engine_bridge.dart';
import '../services/equalizer_dvc_sync.dart';
import 'music_provider.dart';
import 'bluetooth_provider.dart';

// See full file in artifacts — loading via push_files next
