import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../cloudinary_config.dart';
import '../crypto/media_crypto.dart';

/// Резултат след pick → encrypt → upload.
class UploadedMedia {
  final String envelopeJson;
  final String type;
  final String url;
  final String mime;
  final String name;
  final int size;

  UploadedMedia({
    required this.envelopeJson,
    required this.type,
    required this.url,
    required this.mime,
    required this.name,
    required this.size,
  });
}

/// Локално избрана медия (без upload) — за attach preview.
class PickedMediaLocal {
  final List<int> bytes;
  final String name;
  final String mime;

  const PickedMediaLocal({
    required this.bytes,
    required this.name,
    required this.mime,
  });
}

class MediaService {
  static final _imagePicker = ImagePicker();

  static const int maxBytes = 25 * 1024 * 1024; // 25 MB
  static const int maxVoiceBytes = 5 * 1024 * 1024; // 5 MB глас

  // ── Локален pick (preview, без Cloudinary) ──

  /// Снимка от галерията — само байтове.
  static Future<PickedMediaLocal?> pickImageLocal() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    _assertSize(bytes.length);

    return PickedMediaLocal(
      bytes: bytes,
      name: file.name,
      mime: file.mimeType ?? _mimeFromName(file.name) ?? 'image/jpeg',
    );
  }

  /// Видео от галерията — само байтове.
  static Future<PickedMediaLocal?> pickVideoLocal() async {
    final file = await _imagePicker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 3),
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    _assertSize(bytes.length);

    return PickedMediaLocal(
      bytes: bytes,
      name: file.name,
      mime: file.mimeType ?? _mimeFromName(file.name) ?? 'video/mp4',
    );
  }

  /// Произволен файл — само байтове.
  static Future<PickedMediaLocal?> pickFileLocal() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return null;

    final f = result.files.first;
    final bytes = f.bytes;
    if (bytes == null) {
      throw Exception(
        'Не могат да се прочетат байтовете на файла (web/mobile)',
      );
    }
    if (bytes.isEmpty) return null;
    _assertSize(bytes.length);

    return PickedMediaLocal(
      bytes: bytes,
      name: f.name,
      mime: _mimeFromName(f.name) ?? 'application/octet-stream',
    );
  }

  // ── Pick + веднага upload (стар API) ──

  static Future<UploadedMedia?> pickAndUploadImage() async {
    final local = await pickImageLocal();
    if (local == null) return null;
    return uploadBytes(bytes: local.bytes, name: local.name, mime: local.mime);
  }

  static Future<UploadedMedia?> captureAndUploadImage() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
    if (file == null) return null;
    return _encryptAndUpload(
      bytes: await file.readAsBytes(),
      name: file.name,
      mime: file.mimeType ?? 'image/jpeg',
    );
  }

  static Future<UploadedMedia?> pickAndUploadVideo() async {
    final local = await pickVideoLocal();
    if (local == null) return null;
    return uploadBytes(bytes: local.bytes, name: local.name, mime: local.mime);
  }

  static Future<UploadedMedia?> pickAndUploadFile() async {
    final local = await pickFileLocal();
    if (local == null) return null;
    return uploadBytes(bytes: local.bytes, name: local.name, mime: local.mime);
  }

  /// Вече избрани байтове → encrypt → Cloudinary.
  static Future<UploadedMedia> uploadBytes({
    required List<int> bytes,
    required String name,
    required String mime,
  }) {
    return _encryptAndUpload(bytes: bytes, name: name, mime: mime);
  }

  /// Гласово от локален m4a запис.
  static Future<UploadedMedia?> uploadVoiceFile({
    required String filePath,
    required int durationMs,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Гласовият файл липсва');
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Празно гласово съобщение');
    }
    if (bytes.length > maxVoiceBytes) {
      throw Exception(
        'Гласовото е твърде голямо '
        '(${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB). '
        'Максимум ${maxVoiceBytes ~/ (1024 * 1024)} MB.',
      );
    }

    final sec = (durationMs / 1000).ceil().clamp(1, 9999);
    final name = 'voice_${sec}s.m4a';

    final uploaded = await _encryptAndUpload(
      bytes: bytes,
      name: name,
      mime: 'audio/mp4',
    );

    try {
      await file.delete();
    } catch (_) {}

    return uploaded;
  }

  static void _assertSize(int length) {
    if (length > maxBytes) {
      throw Exception(
        'Файлът е твърде голям '
        '(${(length / (1024 * 1024)).toStringAsFixed(1)} MB). '
        'Максимум ${maxBytes ~/ (1024 * 1024)} MB.',
      );
    }
  }

  static Future<UploadedMedia> _encryptAndUpload({
    required List<int> bytes,
    required String name,
    required String mime,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('Празна медия');
    }
    _assertSize(bytes.length);

    final encrypted = await MediaCrypto.encryptBytes(bytes);
    final url = await _uploadCiphertextToCloudinary(
      ciphertext: encrypted.ciphertextBytes,
      filename: '$name.enc',
    );

    final type = MediaCrypto.typeFromMime(mime);
    final envelope = MediaCrypto.buildEnvelope(
      type: type,
      url: url,
      keyBase64: encrypted.keyBase64,
      nonceBase64: encrypted.nonceBase64,
      mime: mime,
      name: name,
      size: bytes.length,
    );

    return UploadedMedia(
      envelopeJson: envelope,
      type: type,
      url: url,
      mime: mime,
      name: name,
      size: bytes.length,
    );
  }

  static Future<String> _uploadCiphertextToCloudinary({
    required List<int> ciphertext,
    required String filename,
  }) async {
    final uri = Uri.parse(CloudinaryConfig.uploadUrl);
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = CloudinaryConfig.mediaUploadPreset
      ..fields['folder'] = 'criptivo/media'
      ..files.add(
        http.MultipartFile.fromBytes('file', ciphertext, filename: filename),
      );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Cloudinary media upload failed: ${response.body}');
    }

    final body = response.body;
    final match = RegExp(r'"secure_url"\s*:\s*"([^"]+)"').firstMatch(body);
    if (match == null) {
      throw Exception('No secure_url in Cloudinary response');
    }
    return match.group(1)!.replaceAll(r'\/', '/');
  }

  static Future<List<int>> downloadAndDecrypt({
    required String url,
    required String keyBase64,
    required String nonceBase64,
  }) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Download failed: ${response.statusCode}');
    }

    return MediaCrypto.decryptBytes(
      ciphertextBytes: response.bodyBytes,
      keyBase64: keyBase64,
      nonceBase64: nonceBase64,
    );
  }

  static String? _mimeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.zip')) return 'application/zip';
    return null;
  }
}
