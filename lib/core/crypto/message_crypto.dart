import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'key_manager.dart';

class EncryptedPayload {
  final String ciphertext; // base64(cipherText + mac)
  final String nonce; // base64

  EncryptedPayload({required this.ciphertext, required this.nonce});
}

class MessageCrypto {
  static final _x25519 = X25519();
  static final _aes = AesGcm.with256bits();

  static Future<SecretKey> _aesKeyFromPair({
    required List<int> myPrivateKeyBytes,
    required List<int> theirPublicKeyBytes,
  }) async {
    if (myPrivateKeyBytes.length != 32) {
      throw StateError(
        'Private key трябва да е 32 байта (получени: ${myPrivateKeyBytes.length})',
      );
    }
    if (theirPublicKeyBytes.length != 32) {
      throw StateError(
        'Public key трябва да е 32 байта (получени: ${theirPublicKeyBytes.length})',
      );
    }

    final myKeyPair = await _x25519.newKeyPairFromSeed(myPrivateKeyBytes);
    final theirPublic = SimplePublicKey(
      theirPublicKeyBytes,
      type: KeyPairType.x25519,
    );

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: theirPublic,
    );

    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode('Criptivo-salt-v1'),
      info: utf8.encode('Criptivo-msg-v1'),
    );
  }

  /// Session secret (32 bytes) — за глаголическия печат
  static Future<List<int>> sessionSecretBytes({
    required String theirPublicKeyBase64,
  }) async {
    final myPrivate = await KeyManager.getPrivateKeyBytes();
    if (myPrivate == null) {
      throw Exception('Липсва private key');
    }

    final theirBytes = base64Decode(theirPublicKeyBase64);
    if (theirBytes.length != 32) {
      throw StateError('Невалиден public key (дължина ${theirBytes.length})');
    }

    final myKeyPair = await _x25519.newKeyPairFromSeed(myPrivate);
    final theirPublic = SimplePublicKey(theirBytes, type: KeyPairType.x25519);

    final shared = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: theirPublic,
    );

    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derived = await hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('Criptivo-salt-v1'),
      info: utf8.encode('Criptivo-session-v1'),
    );

    return derived.extractBytes();
  }

  static Future<EncryptedPayload> encrypt({
    required String plaintext,
    required String theirPublicKeyBase64,
  }) async {
    final myPrivate = await KeyManager.getPrivateKeyBytes();
    if (myPrivate == null) {
      throw Exception('Липсва private key');
    }

    final theirBytes = base64Decode(theirPublicKeyBase64);
    if (theirBytes.length != 32) {
      throw StateError(
        'Невалиден public key на получателя (дължина ${theirBytes.length}). '
        'Увери се, че другият потребител е публикувал ключа си.',
      );
    }

    final aesKey = await _aesKeyFromPair(
      myPrivateKeyBytes: myPrivate,
      theirPublicKeyBytes: theirBytes,
    );

    final secretBox = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: aesKey,
    );

    // cipherText + 16-byte MAC
    final combined = <int>[...secretBox.cipherText, ...secretBox.mac.bytes];

    return EncryptedPayload(
      ciphertext: base64Encode(combined),
      nonce: base64Encode(secretBox.nonce),
    );
  }

  static Future<String> decrypt({
    required String ciphertextBase64,
    required String nonceBase64,
    required String theirPublicKeyBase64,
  }) async {
    final myPrivate = await KeyManager.getPrivateKeyBytes();
    if (myPrivate == null) {
      throw Exception('Липсва private key на това устройство');
    }

    final theirBytes = base64Decode(theirPublicKeyBase64);
    if (theirBytes.length != 32) {
      throw StateError('Невалиден public key (дължина ${theirBytes.length})');
    }

    final aesKey = await _aesKeyFromPair(
      myPrivateKeyBytes: myPrivate,
      theirPublicKeyBytes: theirBytes,
    );

    final combined = base64Decode(ciphertextBase64);
    final nonce = base64Decode(nonceBase64);

    if (combined.length < 17) {
      throw Exception('Ciphertext твърде къс (${combined.length} байта)');
    }

    final cipherText = combined.sublist(0, combined.length - 16);
    final macBytes = combined.sublist(combined.length - 16);

    try {
      final clear = await _aes.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: aesKey,
      );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      // Най-честата причина: грешен ключ (сменен private/public key)
      throw Exception(
        'Грешка при автентикация (MAC). '
        'Най-вероятно ключовете са се сменили след изпращането на съобщението.',
      );
    }
  }
}
