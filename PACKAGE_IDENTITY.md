# Resonate package / brand identity

## Canonical IDs

| Kind | Value | Notes |
|------|--------|------|
| App display name | **Resonate** | AndroidManifest `android:label` |
| Flutter package name | `resonate` | pubspec `name:` (import path) |
| MethodChannels | `com.aetherion.resonate/media_store` | volume, scan, folders, diagnostics |
| | `com.aetherion.resonate/audio_effects` | bass/reverb + optional native DSP |
| Notification channel | `com.aetherion.resonate.audio` | audio_service |
| applicationId / namespace | `com.Aetherion.Resonate` | Gradle — do not change lightly |

## Fixed from legacy `com.example.resonate`

Dart + Kotlin channel strings use **`com.aetherion.resonate/...`** on both sides.

## Kotlin folder path (optional cleanup)

MainActivity may still live under `kotlin/com/example/resonate/` while declaring `package com.Aetherion.Resonate`. That works; matching folders is optional later.
