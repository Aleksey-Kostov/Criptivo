import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'key_manager.dart';

/// Криптиран backup на локалната X25519 идентичност.
///
/// Версия 1 остава съвместима със съществуващите архиви.
/// Форматът съдържа JSON, кодиран в Base64:
/// v, salt, nonce, ciphertext.
///
/// ciphertext съдържа AES-GCM ciphertext, следван от 16-байтовия MAC.
class KeyBackupService {
  static const _version = 1;
  static const _pbkdfIterations = 120000;

  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _macLength = 16;

  // Предпазва от прекомерно големи входни низове.
  static const _maxBackupLength = 1024 * 1024;

  /// Експортира проверена двойка ключове в криптиран архив.
  static Future<String> exportBackup({required String password}) async {
    if (password.length < 8) {
      throw ArgumentError('Паролата за backup трябва да е поне 8 символа.');
    }

    // Не експортираме частична или несъответстваща идентичност.
    final hasKeys = await KeyManager.hasKeys();

    if (!hasKeys) {
      throw StateError('Няма локални ключове за export.');
    }

    final privateBytes = await KeyManager.getPrivateKeyBytes();
    final publicBase64 = await KeyManager.getPublicKeyBase64();

    if (privateBytes == null ||
        privateBytes.length != 32 ||
        publicBase64 == null ||
        publicBase64.isEmpty) {
      throw StateError('Локалната идентичност е непълна.');
    }

    final plaintext = utf8.encode(
      '${base64Encode(privateBytes)}\n$publicBase64',
    );

    final salt = _randomBytes(_saltLength);
    final secretKey = await _deriveKey(password, salt);

    final box = await AesGcm.with256bits().encrypt(
      plaintext,
      secretKey: secretKey,
    );

    if (box.nonce.length != _nonceLength ||
        box.mac.bytes.length != _macLength) {
      throw StateError('Криптографската библиотека върна неочакван формат.');
    }

    final combined = <int>[...box.cipherText, ...box.mac.bytes];

    final payload = <String, dynamic>{
      'v': _version,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(combined),
    };

    final result = base64Encode(utf8.encode(jsonEncode(payload)));

    if (result.length > _maxBackupLength) {
      throw StateError('Генерираният backup е прекалено голям.');
    }

    return result;
  }

  /// Декриптира и валидира backup, след което възстановява ключовете.
  ///
  /// Преди извикване интерфейсът трябва да поиска изрично потвърждение,
  /// ако възстановяването ще замени съществуваща идентичност.
  static Future<void> importBackup({
    required String backupString,
    required String password,
  }) async {
    if (password.isEmpty) {
      throw ArgumentError('Въведи паролата за backup.');
    }

    final input = backupString.trim();

    if (input.isEmpty || input.length > _maxBackupLength) {
      throw StateError('Невалиден размер на backup.');
    }

    final Map<String, dynamic> payload;

    try {
      final decodedJson = utf8.decode(base64Decode(input));
      final decoded = jsonDecode(decodedJson);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Очаква се JSON обект.');
      }

      payload = decoded;
    } catch (_) {
      throw StateError('Невалиден backup низ.');
    }

    if (payload['v'] != _version) {
      throw StateError('Неподдържана версия на backup.');
    }

    final String saltBase64;
    final String nonceBase64;
    final String ciphertextBase64;

    try {
      final saltValue = payload['salt'];
      final nonceValue = payload['nonce'];
      final ciphertextValue = payload['ciphertext'];

      if (saltValue is! String ||
          nonceValue is! String ||
          ciphertextValue is! String) {
        throw const FormatException('Невалидни полета.');
      }

      saltBase64 = saltValue;
      nonceBase64 = nonceValue;
      ciphertextBase64 = ciphertextValue;
    } catch (_) {
      throw StateError('Backup форматът е невалиден или непълен.');
    }

    final List<int> salt;
    final List<int> nonce;
    final List<int> combined;

    try {
      salt = base64Decode(saltBase64);
      nonce = base64Decode(nonceBase64);
      combined = base64Decode(ciphertextBase64);
    } catch (_) {
      throw StateError('Backup съдържа невалидни Base64 данни.');
    }

    if (salt.length != _saltLength) {
      throw StateError('Backup съдържа невалидна salt стойност.');
    }

    if (nonce.length != _nonceLength) {
      throw StateError('Backup съдържа невалиден nonce.');
    }

    if (combined.length < _macLength + 1) {
      throw StateError('Повреден backup: ciphertext е прекалено кратък.');
    }

    final cipherText = combined.sublist(0, combined.length - _macLength);

    final macBytes = combined.sublist(combined.length - _macLength);

    final secretKey = await _deriveKey(password, salt);

    final List<int> clear;

    try {
      clear = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: secretKey,
      );
    } on SecretBoxAuthenticationError {
      throw StateError('Грешна парола или повреден backup.');
    } catch (_) {
      throw StateError('Backup не можа да бъде декриптиран.');
    }

    final String privateKeyBase64;
    final String publicKeyBase64;

    try {
      final text = utf8.decode(clear);
      final parts = text.split('\n');

      if (parts.length != 2) {
        throw const FormatException('Невалиден payload.');
      }

      privateKeyBase64 = parts[0].trim();
      publicKeyBase64 = parts[1].trim();

      // Предварителна проверка на декодирането и дължините.
      if (base64Decode(privateKeyBase64).length != 32 ||
          base64Decode(publicKeyBase64).length != 32) {
        throw const FormatException('Невалидна дължина на ключ.');
      }
    } catch (_) {
      throw StateError('Backup съдържа невалидни данни за ключовете.');
    }

    // KeyManager проверява дали двата ключа съвпадат и се опитва
    // да възстанови предишното състояние при неуспешен запис.
    await KeyManager.importKeyPair(
      privateKeyBase64: privateKeyBase64,
      publicKeyBase64: publicKeyBase64,
    );
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

  static List<int> _randomBytes(int length) {
    final random = Random.secure();

    return List<int>.generate(
      length,
      (_) => random.nextInt(256),
      growable: false,
    );
  }
}
