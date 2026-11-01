import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import 'mls_key_package_service.dart';
import 'mls_service.dart';

class CryptoBootstrap {
  static Future<KeySyncStatus> runAfterLogin() async {
    final user = AuthService.currentUser;
    if (user == null) return KeySyncStatus.error;

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

    try {
      final existing = await MlsService.instance.loadIdentityFromStorage();
      if (existing == null) {
        await MlsService.instance.createIdentity(user.id);
        debugPrint('Criptivo: MLS identity created for ${user.id}');
      } else {
        debugPrint('Criptivo: MLS identity loaded: ${existing.identity}');
      }

      // C3: поддържай pool от KeyPackages в Supabase
      await MlsKeyPackageService.instance.ensurePool();
    } catch (e) {
      debugPrint('Criptivo: MLS bootstrap failed: $e');
    }

    return status;
  }
}
