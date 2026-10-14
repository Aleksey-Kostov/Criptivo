import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class KeyManager {
  static const _privateKeyKey = 'criptivo_private_key';
  static const _publicKeyKey = 'criptivo_public_key';

  static final _storage = FlutterSecureStorage(
    webOptions: const WebOptions(
      dbName: 'criptivo_secure_db',
      publicKey: 'criptivo_public_key_store',
    ),
  );

  static final _x25519 = X25519();

  /// Има ли валидни ключове локално
  static Future<bool> hasKeys() async {
    final priv = await _storage.read(key: _privateKeyKey);
    final pub = await _storage.read(key: _publicKeyKey);
    return priv != null && priv.isNotEmpty && pub != null && pub.isNotEmpty;
  }

  /// Генерира нова двойка. Викай САМО през ensureKeys()
  /// или ръчно при debug reset.
  static Future<void> generateAndStoreKeys() async {
    final keyPair = await _x25519.newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();

    await _storage.write(
      key: _privateKeyKey,
      value: base64Encode(privateBytes),
    );
    await _storage.write(
      key: _publicKeyKey,
      value: base64Encode(publicKey.bytes),
    );

    print('KeyManager: NEW keys generated');
    print('Public key: ${base64Encode(publicKey.bytes)}');
  }

  /// Ако има ключове → не пипа.
  /// Ако няма → генерира веднъж.
  static Future<void> ensureKeys() async {
    if (await hasKeys()) {
      print('KeyManager: existing keys kept');
      return;
    }
    await generateAndStoreKeys();
  }

  static Future<String?> getPublicKeyBase64() async {
    return _storage.read(key: _publicKeyKey);
  }

  static Future<List<int>?> getPrivateKeyBytes() async {
    final b64 = await _storage.read(key: _privateKeyKey);
    if (b64 == null || b64.isEmpty) return null;
    return base64Decode(b64);
  }

  /// Само за debug / ръчен reset — НЕ в login/home/chat
  static Future<void> clearKeys() async {
    await _storage.delete(key: _privateKeyKey);
    await _storage.delete(key: _publicKeyKey);
    print('KeyManager: keys cleared');
  }
}
