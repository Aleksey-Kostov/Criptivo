import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cloudinary_config.dart';

class AvatarService {
  static final _supabase = Supabase.instance.client;
  static final _picker = ImagePicker();

  /// Избира снимка от галерията.
  static Future<XFile?> pickImage() async {
    return _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
  }

  /// Качва към Cloudinary и връща secure_url.
  static Future<String> uploadToCloudinary(XFile file) async {
    final uri = Uri.parse(CloudinaryConfig.uploadUrl);
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = CloudinaryConfig.avatarUploadPreset
      ..fields['folder'] = 'criptivo/avatars';

    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name,
        ),
      );
    } else {
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Cloudinary upload failed: ${response.body}');
    }

    // Прост parse без json package dependency conflict
    final body = response.body;
    final match = RegExp(r'"secure_url"\s*:\s*"([^"]+)"').firstMatch(body);
    if (match == null) {
      throw Exception('No secure_url in Cloudinary response');
    }
    return match.group(1)!.replaceAll(r'\/', '/');
  }

  /// Качва avatar и записва URL в profiles.
  static Future<String> updateMyAvatar(XFile file) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Не си влязъл');

    final url = await uploadToCloudinary(file);

    await _supabase
        .from('profiles')
        .update({
          'avatar_url': url,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', user.id);

    return url;
  }

  /// Зарежда текущия профил.
  static Future<Map<String, dynamic>?> getMyProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final row = await _supabase
        .from('profiles')
        .select('id, username, display_name, avatar_url, public_key')
        .eq('id', user.id)
        .maybeSingle();

    return row == null ? null : Map<String, dynamic>.from(row);
  }

  /// Обновява display_name.
  static Future<void> updateDisplayName(String name) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    await _supabase
        .from('profiles')
        .update({
          'display_name': trimmed,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', user.id);
  }
}
