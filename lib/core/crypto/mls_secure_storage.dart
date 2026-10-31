import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Локално защитено хранилище за MLS state.
/// Никога не качвай тези данни в Supabase.
class MlsSecureStorage {
  MlsSecureStorage._();

  static const _identityKey = 'mls_identity_state_v2';

  static String _groupKey(String groupId) => 'mls_group_state_v1_$groupId';

  static final FlutterSecureStorage _secure = FlutterSecureStorage(
    webOptions: const WebOptions(
      dbName: 'criptivo_secure_db',
      publicKey: 'criptivo_public_key_store',
    ),
  );

  // --- Identity ---

  static Future<void> saveIdentityState(String protectedStateJson) async {
    await _secure.write(key: _identityKey, value: protectedStateJson);
  }

  static Future<String?> loadIdentityState() async {
    return _secure.read(key: _identityKey);
  }

  static Future<void> clearIdentityState() async {
    await _secure.delete(key: _identityKey);
  }

  static Future<bool> hasIdentity() async {
    final v = await loadIdentityState();
    return v != null && v.isNotEmpty;
  }

  // --- Group state ---

  static Future<void> saveGroupState(
    String groupId,
    String groupStateJson,
  ) async {
    await _secure.write(key: _groupKey(groupId), value: groupStateJson);
  }

  static Future<String?> loadGroupState(String groupId) async {
    return _secure.read(key: _groupKey(groupId));
  }

  static Future<void> clearGroupState(String groupId) async {
    await _secure.delete(key: _groupKey(groupId));
  }
}
