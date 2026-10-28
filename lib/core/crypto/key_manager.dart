import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// X25519 ключове — локална криптографска идентичност на устройството.
///
/// Ключовете не се синхронизират автоматично между устройства.
/// За възстановяване използвай KeyBackupService.
class KeyManager {
  static const _privateKeyKey = 'criptivo_private_key';
  static const _publicKeyKey = 'criptivo_public_key';

  static final FlutterSecureStorage _secure = FlutterSecureStorage(
    webOptions: const WebOptions(
      dbName: 'criptivo_secure_db',
      publicKey: 'criptivo_public_key_store',
    ),
  );

  static final X25519 _x25519 = X25519();

  /// Чете ключ от защитеното хранилище.
  ///
  /// Ако липсва, мигрира старата стойност от SharedPreferences.
  /// При грешка не използва старата стойност като резервен вариант.
  static Future<String?> _read(String key) async {
    final String? secureValue;

    try {
      secureValue = await _secure.read(key: key);
    } catch (_) {
      throw StateError(
        'Защитеното хранилище е недостъпно. '
        'Операцията е спряна, за да се запази криптографската идентичност.',
      );
    }

    if (secureValue != null && secureValue.isNotEmpty) {
      await _removeLegacyCopy(key);
      return secureValue;
    }

    final prefs = await SharedPreferences.getInstance();
    final legacyValue = prefs.getString(key);

    if (legacyValue == null || legacyValue.isEmpty) {
      return null;
    }

    try {
      await _secure.write(key: key, value: legacyValue);

      final verifiedValue = await _secure.read(key: key);

      if (verifiedValue != legacyValue) {
        throw StateError('Проверката на мигрирания ключ е неуспешна.');
      }

      final removed = await prefs.remove(key);

      if (!removed || prefs.containsKey(key)) {
        throw StateError('Старата стойност не беше премахната.');
      }

      return verifiedValue;
    } catch (_) {
      throw StateError(
        'Миграцията на ключа не беше завършена. '
        'Не изтривай данните на приложението и опитай отново.',
      );
    }
  }

  /// Записва ключ само в защитеното хранилище.
  static Future<void> _write(String key, String value) async {
    try {
      await _secure.write(key: key, value: value);

      final verifiedValue = await _secure.read(key: key);

      if (verifiedValue != value) {
        throw StateError('Проверката на записания ключ е неуспешна.');
      }

      await _removeLegacyCopy(key);
    } catch (_) {
      throw StateError(
        'Ключът не беше записан надеждно в защитеното хранилище. '
        'Операцията е спряна.',
      );
    }
  }

  /// Премахва старо копие само след потвърждение на защитеното копие.
  static Future<void> _removeLegacyCopy(String key) async {
    final prefs = await SharedPreferences.getInstance();

    if (!prefs.containsKey(key)) {
      return;
    }

    final removed = await prefs.remove(key);

    if (!removed || prefs.containsKey(key)) {
      throw StateError('Старата стойност не беше премахната.');
    }
  }

  static Future<void> _delete(String key) async {
    await _secure.delete(key: key);

    final remaining = await _secure.read(key: key);

    if (remaining != null) {
      throw StateError('Изтриването на защитения ключ не беше потвърдено.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);

    if (prefs.containsKey(key)) {
      throw StateError('Старото копие на ключа не беше изтрито.');
    }
  }

  /// Проверява дали съществува валидна, пълна двойка X25519 ключове.
  ///
  /// Връща false само когато и двата ключа липсват.
  /// При частична или несъответстваща двойка хвърля StateError.
  static Future<bool> hasKeys() async {
    final priv = await _read(_privateKeyKey);
    final pub = await _read(_publicKeyKey);

    final hasPrivate = priv != null && priv.isNotEmpty;
    final hasPublic = pub != null && pub.isNotEmpty;

    if (!hasPrivate && !hasPublic) {
      return false;
    }

    if (!hasPrivate || !hasPublic) {
      throw StateError(
        'Непълна криптографска идентичност: липсва частен или публичен ключ. '
        'Възстанови правилната двойка от архив. '
        'Не създавай нова идентичност автоматично.',
      );
    }

    try {
      final privateBytes = base64Decode(priv);
      final publicBytes = base64Decode(pub);

      if (privateBytes.length != 32 || publicBytes.length != 32) {
        throw const FormatException('Невалидна дължина на X25519 ключ.');
      }

      final pair = await _x25519.newKeyPairFromSeed(privateBytes);
      final derivedPublic = await pair.extractPublicKey();

      if (!_bytesEqual(derivedPublic.bytes, publicBytes)) {
        throw StateError(
          'Локалните публичен и частен ключ не съвпадат. '
          'Възстанови правилната двойка от архив.',
        );
      }
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError(
        'Локалните криптографски ключове са невалидни. '
        'Възстанови правилната двойка от архив.',
      );
    }

    return true;
  }

  /// Генерира нова двойка ключове само ако няма записани ключове.
  ///
  /// Не използвай този метод за смяна на съществуваща идентичност.
  static Future<void> generateAndStoreKeys() async {
    final existingPrivate = await _read(_privateKeyKey);
    final existingPublic = await _read(_publicKeyKey);

    final hasPrivate = existingPrivate != null && existingPrivate.isNotEmpty;
    final hasPublic = existingPublic != null && existingPublic.isNotEmpty;

    if (hasPrivate || hasPublic) {
      throw StateError(
        'Вече има запазени криптографски ключове. '
        'Те няма да бъдат презаписани автоматично. '
        'Провери или възстанови идентичността.',
      );
    }

    final keyPair = await _x25519.newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();

    final privateBase64 = base64Encode(privateBytes);
    final publicBase64 = base64Encode(publicKey.bytes);

    await _write(_privateKeyKey, privateBase64);

    try {
      await _write(_publicKeyKey, publicBase64);
    } catch (_) {
      // Не оставяме частично създадена идентичност да се използва.
      try {
        await _delete(_privateKeyKey);
      } catch (_) {
        // Запазваме първоначалната грешка.
      }
      rethrow;
    }

    debugPrint('KeyManager: новата двойка ключове е записана.');
  }

  /// Запазва съществуващата валидна идентичност.
  ///
  /// Генерира ключове само ако и двата ключа липсват.
  /// При частична или невалидна идентичност спира.
  static Future<void> ensureKeys() async {
    final exists = await hasKeys();

    if (exists) {
      return;
    }

    await generateAndStoreKeys();
  }

  static Future<String?> getPublicKeyBase64() async {
    return _read(_publicKeyKey);
  }

  static Future<List<int>?> getPrivateKeyBytes() async {
    final value = await _read(_privateKeyKey);

    if (value == null || value.isEmpty) {
      return null;
    }

    return base64Decode(value);
  }

  /// Възстановява двойка ключове от архив.
  /// Проверява, че публичният ключ съответства на частния.
  ///
  /// Внимание: този метод може да замени съществуваща двойка.
  /// Извиквай го само след изрично потвърждение от потребителя.
  static Future<void> importKeyPair({
    required String privateKeyBase64,
    required String publicKeyBase64,
  }) async {
    final List<int> privateBytes;
    final List<int> publicBytes;

    try {
      privateBytes = base64Decode(privateKeyBase64);
      publicBytes = base64Decode(publicKeyBase64);
    } catch (_) {
      throw ArgumentError('Архивът съдържа невалиден Base64 ключ.');
    }

    if (privateBytes.length != 32) {
      throw ArgumentError('Частният ключ трябва да е 32 байта.');
    }

    if (publicBytes.length != 32) {
      throw ArgumentError('Публичният ключ трябва да е 32 байта.');
    }

    final pair = await _x25519.newKeyPairFromSeed(privateBytes);
    final derivedPublic = await pair.extractPublicKey();

    if (!_bytesEqual(derivedPublic.bytes, publicBytes)) {
      throw StateError(
        'Публичният ключ не съответства на частния. Архивът може да е повреден.',
      );
    }

    // Не изтриваме старите ключове автоматично при грешка.
    await _write(_privateKeyKey, privateKeyBase64);
    await _write(_publicKeyKey, publicKeyBase64);

    debugPrint('KeyManager: ключовете са възстановени от архив.');
  }

  /// Кратък fingerprint за показване в интерфейса.
  static Future<String?> publicKeyFingerprint() async {
    final publicKey = await getPublicKeyBase64();

    if (publicKey == null || publicKey.isEmpty) {
      return null;
    }

    final List<int> bytes;

    try {
      bytes = base64Decode(publicKey);
    } catch (_) {
      throw StateError('Записаният публичен ключ е невалиден.');
    }

    if (bytes.length != 32) {
      throw StateError('Записаният публичен ключ е с невалидна дължина.');
    }

    final hash = await Sha256().hash(bytes);

    return hash.bytes
        .take(6)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
  }

  /// Изтрива ключовете.
  ///
  /// Използвай само при изрично потвърдено действие на потребителя.
  static Future<void> clearKeys() async {
    await _delete(_privateKeyKey);
    await _delete(_publicKeyKey);

    debugPrint('KeyManager: ключовете са изтрити.');
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }

    var difference = 0;

    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }

    return difference == 0;
  }
}
