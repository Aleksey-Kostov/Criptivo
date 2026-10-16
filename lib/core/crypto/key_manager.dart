import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Управление на X25519 ключове.
///
/// - Mobile: flutter_secure_storage (Keychain / Keystore)
/// - Web: shared_preferences като primary + secure_storage като secondary
///   (на web secure storage често се губи при reload)
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

  // ─── low-level read/write ───────────────────────────────────

  static Future<String?> _read(String key) async {
    // 1) Опитваме secure storage
    try {
      final v = await _secure.read(key: key);
      if (v != null && v.isNotEmpty) return v;
    } catch (e) {
      debugPrint('KeyManager secure read error: $e');
    }

    // 2) Fallback: shared_preferences (особено важно за web)
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
    // Пишем и на двете места
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

  // ─── public API ─────────────────────────────────────────────

  static Future<bool> hasKeys() async {
    final priv = await _read(_privateKeyKey);
    final pub = await _read(_publicKeyKey);
    return priv != null && priv.isNotEmpty && pub != null && pub.isNotEmpty;
  }

  /// Генерира нова двойка. Викай САМО през ensureKeys() или debug reset.
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

  /// Ако има ключове → не пипа. Ако няма → генерира веднъж.
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

  /// Само за debug / ръчен reset
  static Future<void> clearKeys() async {
    await _delete(_privateKeyKey);
    await _delete(_publicKeyKey);
    debugPrint('KeyManager: keys cleared');
  }
}
