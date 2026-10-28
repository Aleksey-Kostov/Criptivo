import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// X25519 ключове — локална крипто-идентичност на устройството.
///
/// ВАЖНО: ключовете НЕ се синхронизират автоматично между устройства.
/// За второ устройство ползвай [KeyBackupService] (export/import).
class KeyManager {
  static const _privateKeyKey = 'criptivo_private_key';
  static const _publicKeyKey = 'criptivo_public_key';

  static final _secure = FlutterSecureStorage(
    webOptions: const WebOptions(
      dbName: 'criptivo_secure_db',
      publicKey: 'criptivo_public_key_store',
    ),
  );

  static final _x25519 = X25519();

  static Future<String?> _read(String key) async {
    try {
      final v = await _secure.read(key: key);
      if (v != null && v.isNotEmpty) return v;
    } catch (e) {
      debugPrint('KeyManager secure read error: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(key);
      if (v != null && v.isNotEmpty) return v;
    } catch (e) {
      debugPrint('KeyManager prefs read error: $e');
    }
    return null;
  }

  static Future<void> _write(String key, String value) async {
    try {
      await _secure.write(key: key, value: value);
    } catch (e) {
      debugPrint('KeyManager secure write error: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (e) {
      debugPrint('KeyManager prefs write error: $e');
    }
  }

  static Future<void> _delete(String key) async {
    try {
      await _secure.delete(key: key);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }

  static Future<bool> hasKeys() async {
    final priv = await _read(_privateKeyKey);
    final pub = await _read(_publicKeyKey);
    return priv != null &&
        priv.isNotEmpty &&
        pub != null &&
        pub.isNotEmpty;
  }

  /// Нова двойка. Само при първа регистрация / след explicit clear + import fail.
  static Future<void> generateAndStoreKeys() async {
    final keyPair = await _x25519.newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();

    final privB64 = base64Encode(privateBytes);
    final pubB64 = base64Encode(publicKey.bytes);

    await _write(_privateKeyKey, privB64);
    await _write(_publicKeyKey, pubB64);

    debugPrint('KeyManager: NEW keys generated');
    debugPrint('Public key: $pubB64');
  }

  /// Ако има ключове → не пипа. Ако няма → генерира.
  /// На ново устройство това създава НОВА идентичност —
  /// без restore старите съобщения няма да се четат.
  static Future<void> ensureKeys() async {
    if (await hasKeys()) {
      debugPrint('KeyManager: existing keys kept');
      return;
    }
    await generateAndStoreKeys();
  }

  static Future<String?> getPublicKeyBase64() async {
    return _read(_publicKeyKey);
  }

  static Future<List<int>?> getPrivateKeyBytes() async {
    final b64 = await _read(_privateKeyKey);
    if (b64 == null || b64.isEmpty) return null;
    return base64Decode(b64);
  }

  /// Възстановява ключове от backup (overwrite локалните).
  static Future<void> importKeyPair({
    required String privateKeyBase64,
    required String publicKeyBase64,
  }) async {
    final priv = base64Decode(privateKeyBase64);
    final pub = base64Decode(publicKeyBase64);
    if (priv.length != 32) {
      throw ArgumentError('private key must be 32 bytes');
    }
    if (pub.length != 32) {
      throw ArgumentError('public key must be 32 bytes');
    }

    // Проверка: public отговаря на private
    final pair = await _x25519.newKeyPairFromSeed(priv);
    final derived = await pair.extractPublicKey();
    if (!_bytesEqual(derived.bytes, pub)) {
      throw StateError(
        'Public key не съответства на private key. Backup-ът е повреден.',
      );
    }

    await _write(_privateKeyKey, privateKeyBase64);
    await _write(_publicKeyKey, publicKeyBase64);
    debugPrint('KeyManager: keys imported from backup');
    debugPrint('Public key: $publicKeyBase64');
  }

  /// Кратък fingerprint за UI (сравнение между устройства).
  static Future<String?> publicKeyFingerprint() async {
    final pub = await getPublicKeyBase64();
    if (pub == null || pub.isEmpty) return null;
    final bytes = base64Decode(pub);
    final hash = await Sha256().hash(bytes);
    final hex = hash.bytes
        .take(6)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':');
    return hex.toUpperCase();
  }

  static Future<void> clearKeys() async {
    await _delete(_privateKeyKey);
    await _delete(_publicKeyKey);
    debugPrint('KeyManager: keys cleared');
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
