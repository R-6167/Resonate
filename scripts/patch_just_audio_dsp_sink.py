#!/usr/bin/env python3
"""Idempotent patch: inject DspEngineSinkHook into just_audio AudioPlayer.java.

Exit codes:
  0 — patched and verified, or already patched and verified
  1 — dependency file missing, upstream layout mismatch, or patch verification failure.
A changed just_audio layout is a deliberate hard failure: update this patch against the
new upstream implementation instead of silently shipping a build without live DSP.
"""
from __future__ import annotations

import glob
import os
import sys

MARKER = "DspEngineSinkHook"
REQUIRED_PATCH_MARKERS = (
    "protected AudioSink buildAudioSink(",
    "Class.forName(\"com.aetherion.resonate.dsp.DspEngineSinkHook\")",
    "sinkBuilder.setAudioProcessors(extra)",
    "defaultFactory",
)


def verify_patched_source(source: str, path: str) -> bool:
    missing = [marker for marker in REQUIRED_PATCH_MARKERS if marker not in source]
    if missing:
        print(
            f"ERROR: DSP sink patch marker present but implementation is incomplete in {path}; "
            f"missing: {', '.join(missing)}",
            file=sys.stderr,
        )
        return False
    print(f"Verified DSP sink injection markers in {path}")
    return True

OLD = """    private void ensurePlayerInitialized() {
        if (player == null) {
            RenderersFactory renderersFactory = (eventHandler, videoListener, audioListener, textOutput, metadataOutput) -> {
                Renderer[] defaultRenderers = new DefaultRenderersFactory(context)
                    .createRenderers(eventHandler, videoListener, audioListener, textOutput, metadataOutput);
                Renderer[] allRenderers = Arrays.copyOf(defaultRenderers, defaultRenderers.length + 1);
                allRenderers[defaultRenderers.length] = new ObserverRenderer();
                return allRenderers;
            };
            ExoPlayer.Builder builder = new ExoPlayer.Builder(context, renderersFactory);
            builder.setUseLazyPreparation(useLazyPreparation);
            if (loadControl != null) {
                builder.setLoadControl(loadControl);
            }
            if (livePlaybackSpeedControl != null) {
                builder.setLivePlaybackSpeedControl(livePlaybackSpeedControl);
            }
            player = builder.build();
            player.setTrackSelectionParameters(
                player.getTrackSelectionParameters()
                    .buildUpon()
                    .setAudioOffloadPreferences(audioOffloadPreferences)
                    .build()
            );
            setAudioSessionId(player.getAudioSessionId());
            player.addListener(this);
        }
    }"""

NEW = """    private void ensurePlayerInitialized() {
        if (player == null) {
            DefaultRenderersFactory defaultFactory = new DefaultRenderersFactory(context) {
                @Override
                protected AudioSink buildAudioSink(
                        Context context,
                        boolean enableFloatOutput,
                        boolean enableAudioTrackPlaybackParams) {
                    DefaultAudioSink.Builder sinkBuilder = new DefaultAudioSink.Builder(context)
                            .setEnableFloatOutput(enableFloatOutput)
                            .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams);
                    try {
                        Class<?> hook = Class.forName("com.aetherion.resonate.dsp.DspEngineSinkHook");
                        java.lang.reflect.Method m = hook.getMethod("createProcessors");
                        Object raw = m.invoke(null);
                        if (raw instanceof androidx.media3.common.audio.AudioProcessor[]) {
                            androidx.media3.common.audio.AudioProcessor[] extra =
                                    (androidx.media3.common.audio.AudioProcessor[]) raw;
                            if (extra.length > 0) {
                                sinkBuilder.setAudioProcessors(extra);
                                android.util.Log.i("just_audio", "Injected " + extra.length + " host AudioProcessor(s)");
                            }
                        }
                    } catch (Throwable t) {
                        android.util.Log.w("just_audio", "DspEngineSinkHook not available, pass-through", t);
                    }
                    return sinkBuilder.build();
                }
            };
            RenderersFactory renderersFactory = (eventHandler, videoListener, audioListener, textOutput, metadataOutput) -> {
                Renderer[] defaultRenderers = defaultFactory
                    .createRenderers(eventHandler, videoListener, audioListener, textOutput, metadataOutput);
                Renderer[] allRenderers = Arrays.copyOf(defaultRenderers, defaultRenderers.length + 1);
                allRenderers[defaultRenderers.length] = new ObserverRenderer();
                return allRenderers;
            };
            ExoPlayer.Builder builder = new ExoPlayer.Builder(context, renderersFactory);
            builder.setUseLazyPreparation(useLazyPreparation);
            if (loadControl != null) {
                builder.setLoadControl(loadControl);
            }
            if (livePlaybackSpeedControl != null) {
                builder.setLivePlaybackSpeedControl(livePlaybackSpeedControl);
            }
            player = builder.build();
            player.setTrackSelectionParameters(
                player.getTrackSelectionParameters()
                    .buildUpon()
                    .setAudioOffloadPreferences(audioOffloadPreferences)
                    .build()
            );
            setAudioSessionId(player.getAudioSessionId());
            player.addListener(this);
        }
    }"""


def find_audio_player() -> str | None:
    home = os.path.expanduser("~")
    patterns = [
        os.path.join(home, ".pub-cache", "hosted", "*", "just_audio-*", "android", "src", "main", "java",
                     "com", "ryanheise", "just_audio", "AudioPlayer.java"),
        os.path.join(home, ".pub-cache", "git", "just_audio-*", "just_audio", "android", "src", "main", "java",
                     "com", "ryanheise", "just_audio", "AudioPlayer.java"),
    ]
    for pat in patterns:
        hits = sorted(glob.glob(pat))
        if hits:
            return hits[-1]
    return None


def main() -> int:
    args = sys.argv[1:]
    verify_only = args == ["--verify"]
    if args and not verify_only:
        print("Usage: patch_just_audio_dsp_sink.py [--verify]", file=sys.stderr)
        return 2

    path = find_audio_player()
    if not path:
        print("ERROR: AudioPlayer.java not found under ~/.pub-cache — run flutter pub get first", file=sys.stderr)
        return 1
    with open(path, "r", encoding="utf-8") as f:
        source = f.read()

    if verify_only:
        if MARKER not in source:
            print(f"ERROR: DSP sink injection marker missing in {path}", file=sys.stderr)
            return 1
        return 0 if verify_patched_source(source, path) else 1

    if MARKER in source:
        print(f"Already patched: {path}")
        return 0 if verify_patched_source(source, path) else 1
    if OLD not in source:
        print(
            f"ERROR: expected ensurePlayerInitialized block not found in {path}. "
            "The just_audio upstream layout changed; refusing to build without DSP sink injection.",
            file=sys.stderr,
        )
        return 1

    patched = source.replace(OLD, NEW, 1)
    if "import androidx.media3.exoplayer.audio.DefaultAudioSink;" not in patched:
        import_anchor = "import androidx.media3.exoplayer.DefaultRenderersFactory;"
        if import_anchor not in patched:
            print(f"ERROR: cannot locate import anchor in {path}", file=sys.stderr)
            return 1
        patched = patched.replace(
            import_anchor,
            import_anchor + "\\n"
            "import androidx.media3.exoplayer.audio.AudioSink;\\n"
            "import androidx.media3.exoplayer.audio.DefaultAudioSink;\\n"
            "import android.content.Context;",
            1,
        )
    with open(path, "w", encoding="utf-8") as f:
        f.write(patched)

    with open(path, "r", encoding="utf-8") as f:
        verified = f.read()
    if MARKER not in verified or not verify_patched_source(verified, path):
        print("ERROR: DSP sink patch verification failed after writing patch", file=sys.stderr)
        return 1
    print(f"Patched and verified: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
