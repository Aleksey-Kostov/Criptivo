import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Резултат от криптиране на файл/медия.
class EncryptedMedia {
  /// cipherText + 16-byte MAC
  final Uint8List ciphertextBytes;

  /// 32-byte AES ключ (base64) — влиза в E2EE envelope на съобщението
  final String keyBase64;

  /// 12-byte nonce (base64)
  final String nonceBase64;

  EncryptedMedia({
    required this.ciphertextBytes,
    required this.keyBase64,
    required this.nonceBase64,
  });
}

/// AES-GCM криптиране на медия с **отделен random ключ** на файл.
///
/// Ключът НЕ се качва в Cloudinary — само в криптираното чат-съобщение.
class MediaCrypto {
  static final _aes = AesGcm.with256bits();
  static final _random = Random.secure();

  static List<int> _randomBytes(int length) {
    return List<int>.generate(length, (_) => _random.nextInt(256));
  }

  /// Криптира сурови байтове (снимка, видео, файл).
  static Future<EncryptedMedia> encryptBytes(List<int> plainBytes) async {
    if (plainBytes.isEmpty) {
      throw ArgumentError('Не може да се криптира празен файл');
    }

    final keyBytes = _randomBytes(32);
    final secretKey = SecretKey(keyBytes);

    final secretBox = await _aes.encrypt(
      plainBytes,
      secretKey: secretKey,
    );

    final combined = Uint8List.fromList([
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);

    return EncryptedMedia(
      ciphertextBytes: combined,
      keyBase64: base64Encode(keyBytes),
      nonceBase64: base64Encode(secretBox.nonce),
    );
  }

  /// Декриптира байтове, свалени от Cloudinary.
  static Future<Uint8List> decryptBytes({
    required List<int> ciphertextBytes,
    required String keyBase64,
    required String nonceBase64,
  }) async {
    if (ciphertextBytes.length < 17) {
      throw Exception(
        'Ciphertext твърде къс (${ciphertextBytes.length} байта)',
      );
    }

    final keyBytes = base64Decode(keyBase64);
    if (keyBytes.length != 32) {
      throw StateError('Невалиден media key (очаквани 32 байта)');
    }

    final nonce = base64Decode(nonceBase64);
    final cipherText =
        ciphertextBytes.sublist(0, ciphertextBytes.length - 16);
    final macBytes =
        ciphertextBytes.sublist(ciphertextBytes.length - 16);

    try {
      final clear = await _aes.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: SecretKey(keyBytes),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw Exception(
        'Грешка при декриптиране на медия (MAC). '
        'Файлът е повреден или ключът е грешен.',
      );
    }
  }

  /// JSON envelope, който се криптира с MessageCrypto и се праща в чата.
  static String buildEnvelope({
    required String type, // image | video | audio | file
    required String url,
    required String keyBase64,
    required String nonceBase64,
    required String mime,
    required String name,
    required int size,
  }) {
    return jsonEncode({
      'v': 1,
      'type': type,
      'url': url,
      'key': keyBase64,
      'nonce': nonceBase64,
      'mime': mime,
      'name': name,
      'size': size,
    });
  }

  /// Parse на декриптирания текст — media envelope или обикновен текст.
  static Map<String, dynamic>? tryParseEnvelope(String plaintext) {
    final t = plaintext.trim();
    if (!t.startsWith('{')) return null;
    try {
      final map = jsonDecode(t);
      if (map is Map<String, dynamic> &&
          map['v'] == 1 &&
          map['type'] is String &&
          map['url'] is String &&
          map['key'] is String &&
          map['nonce'] is String) {
        return map;
      }
    } catch (_) {}
    return null;
  }

  static String typeFromMime(String mime) {
    final m = mime.toLowerCase();
    if (m.startsWith('image/')) return 'image';
    if (m.startsWith('video/')) return 'video';
    if (m.startsWith('audio/')) return 'audio';
    return 'file';
  }
}
