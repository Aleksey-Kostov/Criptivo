import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import 'media_service.dart';

/// Сваля + декриптира медия веднъж, пази temp файл за video_player / open_filex.
class MediaLocalCache {
  MediaLocalCache._();

  static final _inFlight = <String, Future<File>>{};

  static Future<String> _cacheKey({
    required String url,
    required String keyBase64,
    required String nonceBase64,
  }) async {
    final material = utf8.encode('$url|$keyBase64|$nonceBase64');
    final hash = await Sha256().hash(material);
    return base64Url.encode(hash.bytes).replaceAll('=', '');
  }

  /// Връща локален файл с plaintext байтове.
  static Future<File> getDecryptedFile({
    required String url,
    required String keyBase64,
    required String nonceBase64,
    String? preferredName,
  }) async {
    final id = await _cacheKey(
      url: url,
      keyBase64: keyBase64,
      nonceBase64: nonceBase64,
    );

    if (_inFlight.containsKey(id)) {
      return _inFlight[id]!;
    }

    final future = _load(
      id: id,
      url: url,
      keyBase64: keyBase64,
      nonceBase64: nonceBase64,
      preferredName: preferredName,
    );
    _inFlight[id] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(id);
    }
  }

  static Future<File> _load({
    required String id,
    required String url,
    required String keyBase64,
    required String nonceBase64,
    String? preferredName,
  }) async {
    final dir = await getTemporaryDirectory();
    final safeName = (preferredName ?? 'media').replaceAll(
      RegExp(r'[^\w\.\-]'),
      '_',
    );
    final file = File('${dir.path}/criptivo_${id}_$safeName');

    if (await file.exists() && await file.length() > 0) {
      return file;
    }

    final bytes = await MediaService.downloadAndDecrypt(
      url: url,
      keyBase64: keyBase64,
      nonceBase64: nonceBase64,
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
