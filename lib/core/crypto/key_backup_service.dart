import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'key_manager.dart';

/// Backup на identity ключовете, криптиран с парола на потребителя.
///
/// Формат (JSON, base64 payload):
/// {
///   "v": 1,
///   "salt": "...",
///   "nonce": "...",
///   "ciphertext": "..."  // AES-GCM( private_b64 || "\n" || public_b64 )
/// }
class KeyBackupService {
  static const _version = 1;
  static const _pbkdfIterations = 120000;

  /// Експорт: низ, който потребителят пази / прехвърля на другото устройство.
  static Future<String> exportBackup({required String password}) async {
    if (password.length < 8) {
      throw ArgumentError('Паролата за backup трябва да е поне 8 символа');
    }

    final priv = await KeyManager.getPrivateKeyBytes();
    final pub = await KeyManager.getPublicKeyBase64();
    if (priv == null || pub == null || pub.isEmpty) {
      throw StateError('Няма локални ключове за export');
    }

    final plaintext = utf8.encode('${base64Encode(priv)}\n$pub');

    final salt = _randomBytes(16);
    final secretKey = await _deriveKey(password, salt);

    final box = await AesGcm.with256bits().encrypt(
      plaintext,
      secretKey: secretKey,
    );

    final combined = <int>[...box.cipherText, ...box.mac.bytes];

    final payload = {
      'v': _version,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(combined),
    };

    return base64Encode(utf8.encode(jsonEncode(payload)));
  }

  /// Import + запис в KeyManager. След това sync на public key към профила.
  static Future<void> importBackup({
    required String backupString,
    required String password,
  }) async {
    if (password.isEmpty) {
      throw ArgumentError('Въведи паролата за backup');
    }

    late final Map<String, dynamic> payload;
    try {
      final jsonStr = utf8.decode(base64Decode(backupString.trim()));
      payload = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      throw StateError('Невалиден backup низ');
    }

    if (payload['v'] != _version) {
      throw StateError('Неподдържана версия на backup');
    }

    final salt = base64Decode(payload['salt'] as String);
    final nonce = base64Decode(payload['nonce'] as String);
    final combined = base64Decode(payload['ciphertext'] as String);

    if (combined.length < 17) {
      throw StateError('Повреден backup (ciphertext)');
    }

    final cipherText = combined.sublist(0, combined.length - 16);
    final mac = combined.sublist(combined.length - 16);

    final secretKey = await _deriveKey(password, salt);

    try {
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: secretKey,
      );
      final text = utf8.decode(clear);
      final parts = text.split('\n');
      if (parts.length != 2) {
        throw StateError('Повреден backup (payload)');
      }
      await KeyManager.importKeyPair(
        privateKeyBase64: parts[0].trim(),
        publicKeyBase64: parts[1].trim(),
      );
    } on SecretBoxAuthenticationError {
      throw StateError('Грешна парола или повреден backup');
    }
  }

  static Future<SecretKey> _deriveKey(String password, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdfIterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  static List<int> _randomBytes(int n) {
    final rnd = Random.secure();
    return List<int>.generate(n, (_) => rnd.nextInt(256));
  }
}
