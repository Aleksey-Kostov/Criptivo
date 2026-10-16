import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Генерира Safety Number (fingerprint) между двама потребители.
///
/// Алгоритъм (вдъхновен от Signal):
/// 1. Вземаме двата public key-а (base64 → bytes)
/// 2. Сортираме ги лексикографски (редът няма значение)
/// 3. SHA-256 върху (sortedKeyA || sortedKeyB)
/// 4. Превръщаме hash-а в 60-цифрен номер, групиран по 5 цифри
///
/// Резултатът е еднакъв и за двамата участници.
class SafetyNumber {
  SafetyNumber._();

  /// Генерира 60-цифрен safety number.
  ///
  /// [myPublicKeyBase64] и [theirPublicKeyBase64] трябва да са
  /// валидни base64-кодирани X25519 public keys.
  static Future<String> generate({
    required String myPublicKeyBase64,
    required String theirPublicKeyBase64,
  }) async {
    final myBytes = base64Decode(myPublicKeyBase64);
    final theirBytes = base64Decode(theirPublicKeyBase64);

    // Сортираме ключовете, за да е редът независим
    final List<int> first;
    final List<int> second;

    if (_compareBytes(myBytes, theirBytes) <= 0) {
      first = myBytes;
      second = theirBytes;
    } else {
      first = theirBytes;
      second = myBytes;
    }

    final combined = <int>[...first, ...second];

    final hash = await Sha256().hash(combined);
    final digest = hash.bytes; // 32 bytes

    // Превръщаме 32 байта в 60 цифри (използваме първите 30 байта → 60 hex цифри,
    // после ги мапваме към decimal групи за по-лесно четене)
    return _bytesToSafetyNumber(digest);
  }

  /// Форматира safety number-а в групи от 5 цифри (както Signal).
  /// Пример: "12345 67890 12345 67890 ..."
  static String format(String number) {
    final buffer = StringBuffer();
    for (var i = 0; i < number.length; i++) {
      if (i > 0 && i % 5 == 0) buffer.write(' ');
      buffer.write(number[i]);
    }
    return buffer.toString();
  }

  /// Сравнение на два байтови масива (лексикографско).
  static int _compareBytes(List<int> a, List<int> b) {
    final len = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final diff = a[i] - b[i];
      if (diff != 0) return diff;
    }
    return a.length - b.length;
  }

  /// Превръща SHA-256 digest в 60-цифрен decimal string.
  static String _bytesToSafetyNumber(List<int> digest) {
    // Вземаме 30 байта → 60 hex цифри, после ги конвертираме
    // в decimal чрез модуло аритметика за равномерно разпределение.
    final sb = StringBuffer();

    // Обработваме по 5 байта наведнъж → ~12-13 цифри, после взимаме 10
    for (var i = 0; i < 30; i += 5) {
      // 5 байта = 40 бита → число до ~1 трилион
      var value = 0;
      for (var j = 0; j < 5; j++) {
        value = (value << 8) | digest[i + j];
      }

      // Взимаме 10 цифри от това число
      final part = (value % 10000000000).toString().padLeft(10, '0');
      sb.write(part);
    }

    return sb.toString(); // точно 60 цифри
  }

  /// Кратък fingerprint (първите 12 цифри) – за UI badges.
  static Future<String> shortFingerprint({
    required String myPublicKeyBase64,
    required String theirPublicKeyBase64,
  }) async {
    final full = await generate(
      myPublicKeyBase64: myPublicKeyBase64,
      theirPublicKeyBase64: theirPublicKeyBase64,
    );
    return format(full.substring(0, 12));
  }
}
