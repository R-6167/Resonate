package com.aetherion.dsp_engine;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * Loads native libdsp_engine.so for Dart FFI.
 * No method-channel surface — process path is pure FFI.
 */
public class DspEnginePlugin implements FlutterPlugin {
  static {
    System.loadLibrary("dsp_engine");
  }

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    // Native library loaded via static initializer for FFI.
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {}
}
