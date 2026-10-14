import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Жив печат на разговора — детерминиран от session secret.
/// И двамата с един и същ secret виждат еднакъв глиф в даден epoch.
class GlagoliticSeal {
  GlagoliticSeal({
    required List<int> sessionSecret,
    required this.conversationId,
    this.minSeconds = 30,
    this.maxSeconds = 120,
  }) : _sessionSecret = List<int>.unmodifiable(sessionSecret) {
    if (_sessionSecret.length < 32) {
      throw ArgumentError('sessionSecret must be at least 32 bytes');
    }
  }

  final List<int> _sessionSecret;
  final String conversationId;
  final int minSeconds;
  final int maxSeconds;

  static const List<String> glyphs = [
    'Ⰰ', // Az
    'Ⰱ', // Buky
    'Ⰲ', // Vede
    'Ⰳ', // Glagoli
    'Ⰴ', // Dobro
    'Ⰵ', // Jest
    'Ⰶ', // Zhivete
    'Ⰸ', // Izhe
  ];

  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  Future<List<int>> _derive(String purpose) async {
    final key = await _hkdf.deriveKey(
      secretKey: SecretKey(_sessionSecret),
      nonce: utf8.encode('Criptivo-Seal-v1'),
      info: utf8.encode('seal/$purpose/$conversationId'),
    );
    return key.extractBytes();
  }

  /// Epoch от време (секунди от fixed anchor) + interval
  Future<int> epochAt(
    DateTime now, {
    required DateTime conversationCreatedAt,
  }) async {
    final elapsed = now
        .toUtc()
        .difference(conversationCreatedAt.toUtc())
        .inSeconds;
    if (elapsed < 0) return 0;

    // Прост стабилен epoch: делим изминалото време на interval за epoch 0
    // За MVP ползваме fixed average interval, за да няма drift
    const avgInterval = 60; // секунди — стабилен seal, без сложна ротация още
    return elapsed ~/ avgInterval;
  }

  Future<String> glyphForEpoch(int epoch) async {
    final key = await _derive('glyph');
    final stream = _HmacStream(key, utf8.encode('epoch/$epoch'));
    final index = await stream.nextInt(glyphs.length);
    return glyphs[index];
  }

  /// Текущ глиф за UI
  Future<String> currentGlyph({required DateTime conversationCreatedAt}) async {
    final epoch = await epochAt(
      DateTime.now(),
      conversationCreatedAt: conversationCreatedAt,
    );
    return glyphForEpoch(epoch);
  }
}

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
    const range = 0x100000000;
    final limit = range - (range % upperExclusive);
    while (true) {
      final value = await _nextUint32();
      if (value < limit) return value % upperExclusive;
    }
  }
}
