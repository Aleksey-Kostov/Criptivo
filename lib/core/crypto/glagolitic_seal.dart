import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Жив печат на разговора (Glagolitic Seal).
///
/// Детерминиран глиф, който и двамата участници виждат еднакъв
/// в даден epoch. Използва се като визуална проверка, че
/// session secret-ът е синхронизиран (E2EE integrity indicator).
///
/// - Използва всички 48 capital Glagolitic букви (U+2C00–U+2C2F).
/// - Epoch-ите са стабилни и не drift-ват.
/// - Деривацията е през HKDF-SHA256 + HMAC stream (uniform distribution).
class GlagoliticSeal {
  GlagoliticSeal({
    required List<int> sessionSecret,
    required this.conversationId,
    this.epochSeconds = 60,
  }) : _sessionSecret = List<int>.unmodifiable(sessionSecret) {
    if (_sessionSecret.length < 32) {
      throw ArgumentError(
        'sessionSecret must be at least 32 bytes (got ${_sessionSecret.length})',
      );
    }
    if (epochSeconds < 10) {
      throw ArgumentError('epochSeconds must be >= 10');
    }
  }

  final List<int> _sessionSecret;
  final String conversationId;

  /// Продължителност на един epoch в секунди (по подразбиране 60).
  final int epochSeconds;

  /// Всички capital Glagolitic букви (Unicode block U+2C00–U+2C2F).
  /// Максимална визуална ентропия и автентичен вид.
  static const List<String> glyphs = [
    // Основни букви
    'Ⰰ', // Azu
    'Ⰱ', // Buky
    'Ⰲ', // Vede
    'Ⰳ', // Glagoli
    'Ⰴ', // Dobro
    'Ⰵ', // Yestu
    'Ⰶ', // Zhivete
    'Ⰷ', // Dzelo
    'Ⰸ', // Zemlja
    'Ⰹ', // Izhe
    'Ⰺ', // Initial Izhe
    'Ⰻ', // I
    'Ⰼ', // Djervi
    'Ⰽ', // Kako
    'Ⰾ', // Ljudije
    'Ⰿ', // Myslite
    'Ⱀ', // Nashi
    'Ⱁ', // Onu
    'Ⱂ', // Pokoji
    'Ⱃ', // Ritsi
    'Ⱄ', // Slovo
    'Ⱅ', // Tvrido
    'Ⱆ', // Uku
    'Ⱇ', // Fritu
    'Ⱈ', // Heru
    'Ⱉ', // Otu
    'Ⱊ', // Pe
    'Ⱋ', // Shta
    'Ⱌ', // Tsi
    'Ⱍ', // Chrivi
    'Ⱎ', // Sha
    'Ⱏ', // Yeru
    'Ⱐ', // Yeri
    'Ⱑ', // Yati
    'Ⱒ', // Spidery Ha
    'Ⱓ', // Yu
    'Ⱔ', // Small Yus
    'Ⱕ', // Small Yus with Tail
    'Ⱖ', // Yo
    'Ⱗ', // Iotated Small Yus
    'Ⱘ', // Big Yus
    'Ⱙ', // Iotated Big Yus
    'Ⱚ', // Fita
    'Ⱛ', // Izhitsa
    'Ⱜ', // Shtapic
    'Ⱝ', // Trokutasti A
    'Ⱞ', // Latinate Myslite
    'Ⱟ', // Caudate Chrivi
  ];

  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// Деривира 32-байтов ключ за конкретна цел.
  Future<List<int>> _derive(String purpose) async {
    final key = await _hkdf.deriveKey(
      secretKey: SecretKey(_sessionSecret),
      nonce: utf8.encode('Criptivo-Seal-v2'),
      info: utf8.encode('seal/$purpose/$conversationId'),
    );
    return key.extractBytes();
  }

  /// Изчислява текущия epoch от времето на създаване на разговора.
  /// Epoch 0 започва точно при createdAt.
  int epochAt({
    required DateTime now,
    required DateTime conversationCreatedAt,
  }) {
    final elapsed = now
        .toUtc()
        .difference(conversationCreatedAt.toUtc())
        .inSeconds;

    if (elapsed < 0) return 0;
    return elapsed ~/ epochSeconds;
  }

  /// Връща глифа за даден epoch (детерминиран).
  Future<String> glyphForEpoch(int epoch) async {
    final key = await _derive('glyph');
    final stream = _HmacStream(key, utf8.encode('epoch/$epoch'));
    final index = await stream.nextInt(glyphs.length);
    return glyphs[index];
  }

  /// Текущ глиф за UI.
  Future<String> currentGlyph({required DateTime conversationCreatedAt}) async {
    final epoch = epochAt(
      now: DateTime.now(),
      conversationCreatedAt: conversationCreatedAt,
    );
    return glyphForEpoch(epoch);
  }

  /// Опционално: връща и epoch + glyph заедно (полезно за debug / UI).
  Future<({int epoch, String glyph})> currentSeal({
    required DateTime conversationCreatedAt,
  }) async {
    final epoch = epochAt(
      now: DateTime.now(),
      conversationCreatedAt: conversationCreatedAt,
    );
    final glyph = await glyphForEpoch(epoch);
    return (epoch: epoch, glyph: glyph);
  }
}

/// Криптографски сигурен stream от цели числа (rejection sampling).
/// Гарантира равномерно разпределение без bias.
class _HmacStream {
  _HmacStream(this._key, this._prefix);

  final List<int> _key;
  final List<int> _prefix;
  int _counter = 0;

  Future<int> _nextUint32() async {
    final counterBytes = ByteData(4)..setUint32(0, _counter++, Endian.big);
    final mac = await Hmac.sha256().calculateMac([
      ..._prefix,
      ...counterBytes.buffer.asUint8List(),
    ], secretKey: SecretKey(_key));
    final bytes = ByteData.sublistView(Uint8List.fromList(mac.bytes));
    return bytes.getUint32(0, Endian.big);
  }

  Future<int> nextInt(int upperExclusive) async {
    if (upperExclusive <= 0) {
      throw ArgumentError.value(upperExclusive, 'upperExclusive');
    }
    const range = 0x100000000; // 2^32
    final limit = range - (range % upperExclusive);

    while (true) {
      final value = await _nextUint32();
      if (value < limit) {
        return value % upperExclusive;
      }
    }
  }
}
