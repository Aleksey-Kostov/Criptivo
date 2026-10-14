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

    final myKeyPair = await _x25519.newKeyPairFromSeed(myPrivate);
    final theirPublic = SimplePublicKey(
      base64Decode(theirPublicKeyBase64),
      type: KeyPairType.x25519,
    );

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

    final aesKey = await _aesKeyFromPair(
      myPrivateKeyBytes: myPrivate,
      theirPublicKeyBytes: base64Decode(theirPublicKeyBase64),
    );

    final secretBox = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: aesKey,
    );

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
      throw Exception('Липсва private key');
    }

    final aesKey = await _aesKeyFromPair(
      myPrivateKeyBytes: myPrivate,
      theirPublicKeyBytes: base64Decode(theirPublicKeyBase64),
    );

    final combined = base64Decode(ciphertextBase64);
    final nonce = base64Decode(nonceBase64);

    if (combined.length < 17) {
      throw Exception('Ciphertext твърде къс');
    }

    final cipherText = combined.sublist(0, combined.length - 16);
    final macBytes = combined.sublist(combined.length - 16);

    final clear = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
      secretKey: aesKey,
    );

    return utf8.decode(clear);
  }
}
