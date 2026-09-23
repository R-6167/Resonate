# Resonate package identity

Canonical Android applicationId / namespace: **com.Aetherion.Resonate**

MethodChannel names (Dart ↔ native):
- `com.aetherion.resonate/media_store`
- `com.aetherion.resonate/audio_effects`

Kotlin sources live under:
`android/app/src/main/kotlin/com/Aetherion/Resonate/MainActivity.kt`

Do not use `com.example.resonate` anywhere. The old path
`android/app/src/main/kotlin/com/example/resonate/` is a leftover stub only.

Scan contract (Dart ↔ native): `filePath`, `title`, `artist`, `album`, `duration`, `dateAdded`.

Crossfade: outgoing volume uses wall-clock equal-power ramp; never cut before silence.

Notification: androidNotificationOngoing false with stopForegroundOnPause false (audio_service assert).
