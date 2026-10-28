import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/media_crypto.dart';

class ConversationPreview {
  final String conversationId;
  final String preview;
  final bool isMe;
  final DateTime? at;
  final String? messageId;

  const ConversationPreview({
    required this.conversationId,
    required this.preview,
    required this.isMe,
    this.at,
    this.messageId,
  });

  Map<String, dynamic> toJson() => {
        'conversation_id': conversationId,
        'preview': preview,
        'is_me': isMe,
        'at': at?.toUtc().toIso8601String(),
        'message_id': messageId,
      };

  factory ConversationPreview.fromJson(Map<String, dynamic> j) {
    DateTime? at;
    final raw = j['at'];
    if (raw is String) {
      try {
        at = DateTime.parse(raw).toUtc();
      } catch (_) {}
    }
    return ConversationPreview(
      conversationId: j['conversation_id'] as String? ?? '',
      preview: j['preview'] as String? ?? '',
      isMe: j['is_me'] == true,
      at: at,
      messageId: j['message_id'] as String?,
    );
  }
}

/// Локален cache: conversationId → preview (без plaintext в Supabase).
class ConversationPreviewStore {
  ConversationPreviewStore._();

  static const _prefsKey = 'criptivo_conv_previews_v1';
  static Map<String, ConversationPreview> _cache = {};
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _cache = map.map((k, v) {
          return MapEntry(
            k,
            ConversationPreview.fromJson(
              Map<String, dynamic>.from(v as Map),
            ),
          );
        });
      }
    } catch (_) {
      _cache = {};
    }
    _loaded = true;
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = _cache.map((k, v) => MapEntry(k, v.toJson()));
    await prefs.setString(_prefsKey, jsonEncode(encoded));
  }

  static ConversationPreview? get(String conversationId) =>
      _cache[conversationId];

  static Map<String, ConversationPreview> get all =>
      Map.unmodifiable(_cache);

  /// Запис след send / receive / decrypt в чата.
  static Future<void> save({
    required String conversationId,
    required String plaintext,
    required bool isMe,
    String? messageId,
    DateTime? at,
  }) async {
    await load();
    final preview = formatPreview(plaintext, isMe: isMe);
    _cache[conversationId] = ConversationPreview(
      conversationId: conversationId,
      preview: preview,
      isMe: isMe,
      at: at ?? DateTime.now().toUtc(),
      messageId: messageId,
    );
    await _persist();
  }

  static Future<void> clear(String conversationId) async {
    await load();
    _cache.remove(conversationId);
    await _persist();
  }

  /// Кратък UI текст от plaintext / media envelope / reply JSON.
  static String formatPreview(String plaintext, {required bool isMe}) {
    final media = MediaCrypto.tryParseEnvelope(plaintext);
    String body;
    if (media != null) {
      final name = media['name'] as String? ?? '';
      final type = media['type'] as String? ?? 'file';
      if (media['view_once'] == true) {
        body = '👁 Покажи веднъж';
      } else {
        body = switch (type) {
          'image' => '🖼️ Снимка',
          'video' => '🎬 Видео',
          'audio' => '🎵 Гласово',
          'gif' => 'GIF',
          _ => name.isEmpty ? '📎 Файл' : '📎 $name',
        };
      }
    } else {
      try {
        final map = jsonDecode(plaintext);
        if (map is Map && map['t'] == 'text' && map['body'] is String) {
          body = map['body'] as String;
        } else {
          body = plaintext;
        }
      } catch (_) {
        body = plaintext;
      }
    }

    body = body.replaceAll('\n', ' ').trim();
    if (body.startsWith('[')) {
      // [не може да се декриптира] / [липсва ключ]
      body = '🔒 Криптирано съобщение';
    }
    if (body.length > 60) {
      body = '${body.substring(0, 57)}…';
    }
    if (body.isEmpty) body = 'Съобщение';

    return isMe ? 'Ти: $body' : body;
  }
}