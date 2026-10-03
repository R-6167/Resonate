import 'dart:io';

import 'package:innotrepid_security/innotrepid_security.dart';

/// Runtime wiring for the central Innotrepid Security service.
///
/// Production values are supplied with --dart-define. No server secret is
/// embedded here. The public Ed25519 verification key is safe to ship, while
/// the entitlement signing private key remains server-side.
class ResonateSecurity {
  static const baseUrl = String.fromEnvironment(
    'INNOTREPID_SECURITY_BASE_URL',
  );
  static const publicKey = String.fromEnvironment(
    'INNOTREPID_SECURITY_PUBLIC_KEY',
  );
  static const cloudProjectNumber = String.fromEnvironment(
    'INNOTREPID_PLAY_CLOUD_PROJECT_NUMBER',
  );

  static SecurityClient? createClient() {
    if (!Platform.isAndroid ||
        baseUrl.isEmpty ||
        publicKey.isEmpty ||
        cloudProjectNumber.isEmpty) {
      return null;
    }

    final projectNumber = int.tryParse(cloudProjectNumber);
    if (projectNumber == null || projectNumber <= 0) {
      return null;
    }

    return SecurityClient(
      app: const SecurityApp(
        appId: 'resonate',
        packageName: 'com.Aetherion.Resonate',
        version: String.fromEnvironment(
          'FLUTTER_APP_VERSION',
          defaultValue: '0.1.5',
        ),
        buildNumber: String.fromEnvironment('FLUTTER_BUILD_NUMBER'),
      ),
      baseUrl: baseUrl,
      tokenVerifier: SignedEntitlementVerifier(
        publicKeyBase64Url: publicKey,
      ),
      integrityProvider: AndroidPlayIntegrityTokenProvider(
        cloudProjectNumber: projectNumber,
      ),
      cache: EntitlementCache(),
    );
  }
}
