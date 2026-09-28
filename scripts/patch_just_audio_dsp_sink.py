#!/usr/bin/env python3
"""Idempotent patch: inject DspEngineSinkHook into just_audio AudioPlayer.java."""
from __future__ import annotations

import glob
import os
import sys

MARKER = "DspEngineSinkHook"  # already-patched detection

# Upstream (minor) ensurePlayerInitialized body — match exact whitespace from pub-cache.
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
            return hits[-1]  # newest
    return None


def main() -> int:
    path = find_audio_player()
    if not path:
        print("ERROR: AudioPlayer.java not found under ~/.pub-cache — run flutter pub get first", file=sys.stderr)
        return 1
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    if MARKER in text:
        print(f"Already patched: {path}")
        return 0
    if OLD not in text:
        print(f"ERROR: expected ensurePlayerInitialized block not found in {path}", file=sys.stderr)
        print("just_audio version may have changed — update OLD/NEW in this script.", file=sys.stderr)
        return 2
    text = text.replace(OLD, NEW, 1)
    # Imports used by the patch (idempotent if already present)
    if "import androidx.media3.exoplayer.audio.DefaultAudioSink;" not in text:
        text = text.replace(
            "import androidx.media3.exoplayer.DefaultRenderersFactory;",
            "import androidx.media3.exoplayer.DefaultRenderersFactory;\n"
            "import androidx.media3.exoplayer.audio.AudioSink;\n"
            "import androidx.media3.exoplayer.audio.DefaultAudioSink;\n"
            "import android.content.Context;",
            1,
        )
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"Patched: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
