# Resonate security integration

This branch wires Resonate to the reusable Innotrepid Security package without
embedding any production secrets.

## Runtime configuration

Supply these values through --dart-define or the release build environment:

- INNOTREPID_SECURITY_BASE_URL
- INNOTREPID_SECURITY_PUBLIC_KEY — Ed25519 public verification key
- INNOTREPID_PLAY_CLOUD_PROJECT_NUMBER — Google Cloud project number used by Play Integrity
- FLUTTER_APP_VERSION
- FLUTTER_BUILD_NUMBER

The private entitlement signing key never belongs in Resonate.

The security client is intentionally disabled when required runtime values are
missing, so normal local development and playback do not become dependent on
the production security service.

## Current boundary

The package is integrated and the Android Play Integrity request path is ready,
but no Resonate feature is marked premium yet. The premium product ID and
backend deployment must be confirmed before enabling a real purchase gate.
