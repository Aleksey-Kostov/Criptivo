import 'dart:convert';

import 'package:criptivo/core/crypto/key_backup_service.dart';
import 'package:criptivo/core/crypto/key_manager.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KeyBackupService — входна валидация', () {
    test('отхвърля празен backup', () async {
      await expectLater(
        KeyBackupService.importBackup(
          backupString: '',
          password: 'correct horse battery',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('отхвърля невалиден Base64 backup', () async {
      await expectLater(
        KeyBackupService.importBackup(
          backupString: '!!!not-base64!!!',
          password: 'correct horse battery',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('отхвърля неподдържана версия', () async {
      final backup = base64Encode(
        utf8.encode(
          jsonEncode({
            'v': 999,
            'salt': base64Encode(List<int>.filled(16, 1)),
            'nonce': base64Encode(List<int>.filled(12, 2)),
            'ciphertext': base64Encode(List<int>.filled(32, 3)),
          }),
        ),
      );

      await expectLater(
        KeyBackupService.importBackup(
          backupString: backup,
          password: 'correct horse battery',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('отхвърля невалидна дължина на salt', () async {
      final backup = _encodePayload({
        'v': 1,
        'salt': base64Encode(List<int>.filled(8, 1)),
        'nonce': base64Encode(List<int>.filled(12, 2)),
        'ciphertext': base64Encode(List<int>.filled(32, 3)),
      });

      await expectLater(
        KeyBackupService.importBackup(
          backupString: backup,
          password: 'correct horse battery',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('отхвърля липсващи полета', () async {
      final backup = _encodePayload({
        'v': 1,
        'salt': base64Encode(List<int>.filled(16, 1)),
      });

      await expectLater(
        KeyBackupService.importBackup(
          backupString: backup,
          password: 'correct horse battery',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('отхвърля ciphertext, който е твърде кратък', () async {
      final backup = _encodePayload({
        'v': 1,
        'salt': base64Encode(List<int>.filled(16, 1)),
        'nonce': base64Encode(List<int>.filled(12, 2)),
        'ciphertext': base64Encode(List<int>.filled(16, 3)),
      });

      await expectLater(
        KeyBackupService.importBackup(
          backupString: backup,
          password: 'correct horse battery',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('грешната парола се отхвърля преди запис на ключове', () async {
      final backup = await _createEncryptedBackup(
        password: 'original backup password',
      );

      await expectLater(
        KeyBackupService.importBackup(
          backupString: backup,
          password: 'different backup password',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('KeyManager — валидация на ключовете', () {
    test('отхвърля невалиден Base64 частен ключ', () async {
      await expectLater(
        KeyManager.importKeyPair(
          privateKeyBase64: 'not-base64!!!',
          publicKeyBase64: base64Encode(List<int>.filled(32, 1)),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('отхвърля частен ключ с грешна дължина', () async {
      await expectLater(
        KeyManager.importKeyPair(
          privateKeyBase64: base64Encode(List<int>.filled(16, 1)),
          publicKeyBase64: base64Encode(List<int>.filled(32, 2)),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('отхвърля публичен ключ с грешна дължина', () async {
      await expectLater(
        KeyManager.importKeyPair(
          privateKeyBase64: base64Encode(List<int>.filled(32, 1)),
          publicKeyBase64: base64Encode(List<int>.filled(16, 2)),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('отхвърля публичен ключ, който не съответства на частния', () async {
      final x25519 = X25519();

      final privatePair = await x25519.newKeyPair();
      final unrelatedPair = await x25519.newKeyPair();

      final privateBytes = await privatePair.extractPrivateKeyBytes();
      final unrelatedPublic = await unrelatedPair.extractPublicKey();

      await expectLater(
        KeyManager.importKeyPair(
          privateKeyBase64: base64Encode(privateBytes),
          publicKeyBase64: base64Encode(unrelatedPublic.bytes),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

String _encodePayload(Map<String, dynamic> payload) {
  return base64Encode(utf8.encode(jsonEncode(payload)));
}

/// Създава истински криптиран архив за теста.
///
/// Импортът с грешна парола трябва да се провали при AES-GCM
/// удостоверяването, преди да се стигне до запис в KeyManager.
Future<String> _createEncryptedBackup({required String password}) async {
  final x25519 = X25519();
  final pair = await x25519.newKeyPair();

  final privateBytes = await pair.extractPrivateKeyBytes();
  final publicKey = await pair.extractPublicKey();

  final plaintext = utf8.encode(
    '${base64Encode(privateBytes)}\n${base64Encode(publicKey.bytes)}',
  );

  final salt = List<int>.generate(16, (index) => index + 1);

  final key = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 120000,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

  final box = await AesGcm.with256bits().encrypt(plaintext, secretKey: key);

  final combined = <int>[...box.cipherText, ...box.mac.bytes];

  return _encodePayload({
    'v': 1,
    'salt': base64Encode(salt),
    'nonce': base64Encode(box.nonce),
    'ciphertext': base64Encode(combined),
  });
}
