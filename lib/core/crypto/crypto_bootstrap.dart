import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import 'mls_key_package_service.dart';
import 'mls_service.dart';

class CryptoBootstrap {
  static Future<KeySyncStatus> runAfterLogin() async {
    final user = AuthService.currentUser;
    debugPrint('Criptivo: bootstrap start, user=${user?.id}');
    if (user == null) return KeySyncStatus.error;

    var status = await AuthService.syncPublicKeyToProfile();
    debugPrint('Criptivo: key sync status=$status');

    if (status == KeySyncStatus.mismatch ||
        status == KeySyncStatus.missingLocal ||
        status == KeySyncStatus.invalidLocal) {
      debugPrint('Criptivo: repair keys for testing (status=$status)');
      status = await AuthService.repairKeysForTesting();
      debugPrint('Criptivo: repair result=$status');
    }

    if (status != KeySyncStatus.ok) {
      debugPrint('Criptivo: bootstrap aborted, status=$status');
      return status;
    }

    try {
      debugPrint('Criptivo: forcing MLS identity for ${user.id}');
      await MlsService.instance.createIdentity(user.id);
      debugPrint('Criptivo: MLS identity forced for ${user.id}');

      await MlsKeyPackageService.instance.ensurePool();
      debugPrint('Criptivo: ensurePool finished');
    } catch (e, st) {
      debugPrint('Criptivo: MLS bootstrap FAILED: $e');
      debugPrintStack(stackTrace: st);
    }

    return status;
  }
}
