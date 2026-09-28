#!/usr/bin/env python3
"""Patch just_audio Android AudioPlayer to inject host AudioProcessors.

Finds pub-cache (or .flutter-plugins-dependencies path) copies of
com/ryanheise/just_audio/AudioPlayer.java and replaces ensurePlayerInitialized
so DefaultRenderersFactory.buildAudioSink installs processors from
com.Aetherion.Resonate.dsp.DspEngineSinkHook via reflection.

Idempotent: skips files that already contain DspEngineSinkHook.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

MARKER = "DspEngineSinkHook"

OLD = """    private void ensurePlayerInitialized() {
        if (player == null) {
            RenderersFactory renderersFactory = (eventHandler, videoListener, audioListener, textOutput, metadataOutput) -> {
                Renderer[] defaultRenderers = new DefaultRenderersFactory(context)
                    .createRenderers(eventHandler, videoListener, audioListener, textOutput, metadataOutput);
                Renderer[] allRenderers = Arrays.copyOf(defaultRenderers, defaultRenderers.length + 1);
                allRenderers[defaultRenderers.length] = new ObserverRenderer();
                return allRenderers;
            };
            ExoPlayer.Builder builder = new ExoPlayer.Builder(context, renderersFactory);"""

NEW = """    /**
     * Optional host-app hook (Resonate): com.Aetherion.Resonate.dsp.DspEngineSinkHook.createProcessors()
     * Returns androidx.media3.common.audio.AudioProcessor[] for DefaultAudioSink.
     * Resolved via reflection so just_audio does not depend on the app package.
     */
    private static androidx.media3.common.audio.AudioProcessor[] loadHostAudioProcessors() {
        try {
            Class<?> hook = Class.forName("com.Aetherion.Resonate.dsp.DspEngineSinkHook");
            Object result = hook.getMethod("createProcessors").invoke(null);
            if (result instanceof androidx.media3.common.audio.AudioProcessor[]) {
                return (androidx.media3.common.audio.AudioProcessor[]) result;
            }
        } catch (Throwable t) {
            Log.d(TAG, "No host DSP AudioProcessor hook: " + t.getMessage());
        }
        return new androidx.media3.common.audio.AudioProcessor[0];
    }

    private void ensurePlayerInitialized() {
        if (player == null) {
            final DefaultRenderersFactory defaultFactory = new DefaultRenderersFactory(context) {
                @Override
                protected androidx.media3.exoplayer.audio.AudioSink buildAudioSink(
                        Context context,
                        boolean enableFloatOutput,
                        boolean enableAudioTrackPlaybackParams) {
                    androidx.media3.common.audio.AudioProcessor[] hostProcessors = loadHostAudioProcessors();
                    androidx.media3.exoplayer.audio.DefaultAudioSink.Builder sinkBuilder =
                            new androidx.media3.exoplayer.audio.DefaultAudioSink.Builder(context)
                                    .setEnableFloatOutput(enableFloatOutput)
                                    .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams);
                    if (hostProcessors != null && hostProcessors.length > 0) {
                        sinkBuilder.setAudioProcessors(hostProcessors);
                        Log.i(TAG, "Injected " + hostProcessors.length + " host AudioProcessor(s) into DefaultAudioSink");
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
            ExoPlayer.Builder builder = new ExoPlayer.Builder(context, renderersFactory);"""


def candidate_roots() -> list[Path]:
    roots: list[Path] = []
    home = Path.home()
    for p in (
        home / ".pub-cache" / "hosted",
        home / ".pub-cache" / "git",
        Path(os.environ.get("PUB_CACHE", "")) if os.environ.get("PUB_CACHE") else None,
    ):
        if p and p.is_dir():
            roots.append(p)
    # Flutter pub-cache on CI / some installs
    for env_key in ("FLUTTER_ROOT", "FLUTTER_HOME"):
        fr = os.environ.get(env_key)
        if fr:
            roots.append(Path(fr) / ".pub-cache" / "hosted")
    return roots


def find_audio_players() -> list[Path]:
    found: list[Path] = []
    for root in candidate_roots():
        for path in root.rglob("AudioPlayer.java"):
            # just_audio package path
            if "just_audio" in path.as_posix() and "ryanheise" in path.as_posix():
                found.append(path)
    # Also scan project relative pub-cache if present
    cwd = Path.cwd()
    for path in cwd.rglob("AudioPlayer.java"):
        s = path.as_posix()
        if "just_audio" in s and "AudioPlayer.java" in s and path not in found:
            if "ryanheise" in s or "/.pub-cache/" in s:
                found.append(path)
    return found


def patch_file(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        return "skip"
    if OLD not in text:
        return "mismatch"
    path.write_text(text.replace(OLD, NEW, 1), encoding="utf-8")
    return "patched"


def main() -> int:
    files = find_audio_players()
    if not files:
        print("patch_just_audio_dsp_sink: no AudioPlayer.java found under pub-cache", file=sys.stderr)
        print("  Run after: flutter pub get", file=sys.stderr)
        return 1
    ok = 0
    for f in files:
        status = patch_file(f)
        print(f"{status}: {f}")
        if status in ("patched", "skip"):
            ok += 1
    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
