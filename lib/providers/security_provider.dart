import 'package:flutter/foundation.dart';
import 'package:innotrepid_security/innotrepid_security.dart';

import '../services/resonate_security.dart';

class SecurityProvider extends ChangeNotifier {
  SecurityProvider() : client = ResonateSecurity.createClient();

  final SecurityClient? client;

  bool get isConfigured => client != null;

  bool get hasPremium => client?.hasEntitlement('premium') ?? false;

  Future<void> initialize() async {
    final security = client;
    if (security == null) return;
    await security.loadCachedEntitlement('premium');
    notifyListeners();
  }

  Future<VerificationResult> verifyPurchase(String purchaseToken) async {
    final security = client;
    if (security == null) {
      return const VerificationResult(
        status: VerificationStatus.unavailable,
        reason: 'security_not_configured',
      );
    }
    final result = await security.verify(purchaseToken: purchaseToken);
    notifyListeners();
    return result;
  }

  @override
  void dispose() {
    client?.dispose();
    super.dispose();
  }
}
