import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import 'mls_service.dart';

class CryptoBootstrap {
  /// След login: оправя X25519 sync (test) + зарежда/създава MLS identity.
  static Future<KeySyncStatus> runAfterLogin() async {
    final user = AuthService.currentUser;
    if (user == null) return KeySyncStatus.error;

    // --- X25519 (стар слой, нужен докато chat още го ползва) ---
    var status = await AuthService.syncPublicKeyToProfile();

    if (status == KeySyncStatus.mismatch ||
        status == KeySyncStatus.missingLocal ||
        status == KeySyncStatus.invalidLocal) {
      debugPrint('Criptivo: repair keys for testing (status=$status)');
      status = await AuthService.repairKeysForTesting();
    }

    if (status != KeySyncStatus.ok) {
      return status;
    }

    // --- MLS ---
    try {
      final existing = await MlsService.instance.loadIdentityFromStorage();
      if (existing == null) {
        await MlsService.instance.createIdentity(user.id);
        await MlsService.instance.generateKeyPackages(count: 50);
        debugPrint('Criptivo: MLS identity created for ${user.id}');
      } else {
        debugPrint('Criptivo: MLS identity loaded: ${existing.identity}');
      }
    } catch (e) {
      debugPrint('Criptivo: MLS bootstrap failed: $e');
      // Не блокираме home заради MLS засега
    }

    return status;
  }
}
