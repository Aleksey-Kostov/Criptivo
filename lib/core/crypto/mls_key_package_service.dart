import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';
import 'mls_service.dart';

class MlsKeyPackageService {
  MlsKeyPackageService._();
  static final instance = MlsKeyPackageService._();

  static final _db = Supabase.instance.client;

  /// Качва KeyPackages в Supabase. Извикай след generateKeyPackages.
  Future<int> uploadKeyPackages(List<String> packages) async {
    final user = AuthService.currentUser;
    if (user == null) {
      throw StateError('Not logged in');
    }
    if (packages.isEmpty) return 0;

    final rows = packages
        .map((kp) => {'user_id': user.id, 'key_package_b64': kp})
        .toList();

    await _db.from('mls_key_packages').insert(rows);
    return rows.length;
  }

  /// Колко unused KP има текущият потребител.
  Future<int> countMyAvailable() async {
    final user = AuthService.currentUser;
    if (user == null) return 0;

    final rows = await _db
        .from('mls_key_packages')
        .select('id')
        .eq('user_id', user.id)
        .isFilter('consumed_at', null);

    return (rows as List).length;
  }

  /// Ако pool-ът е под прага — генерира + качва.
  Future<void> ensurePool({int minAvailable = 20, int refillTo = 50}) async {
    final available = await countMyAvailable();
    if (available >= minAvailable) {
      debugPrint('Criptivo: KP pool ok ($available)');
      return;
    }

    final need = refillTo - available;
    debugPrint('Criptivo: refilling KP pool (+$need)');
    final packages = await MlsService.instance.generateKeyPackages(count: need);
    final n = await uploadKeyPackages(packages);
    debugPrint('Criptivo: uploaded $n key packages');
  }

  /// Взима (claim) един KP на [otherUserId]. Null ако няма.
  Future<String?> claimKeyPackage(String otherUserId) async {
    debugPrint('Criptivo: RPC claim for otherUserId=$otherUserId');

    final result = await _db.rpc(
      'claim_mls_key_package',
      params: {'target_user': otherUserId},
    );

    debugPrint('Criptivo: RPC raw type=${result.runtimeType} value=$result');

    if (result == null) return null;

    if (result is List) {
      if (result.isEmpty) return null;
      final row = result.first;
      if (row is Map) {
        return row['key_package_b64'] as String?;
      }
    }

    if (result is Map) {
      return result['key_package_b64'] as String?;
    }

    return null;
  }
}
