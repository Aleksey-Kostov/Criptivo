import 'package:supabase_flutter/supabase_flutter.dart';

import '../crypto/message_crypto.dart';

class ChatService {
  static final _supabase = Supabase.instance.client;

  static String? get _myId => _supabase.auth.currentUser?.id;

  /// Търсене на потребители по username
  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];

    final result = await _supabase
        .from('profiles')
        .select('id, username, display_name, public_key, avatar_url')
        .ilike('username', '%${query.trim()}%')
        .neq('id', _myId ?? '')
        .limit(20);

    return List<Map<String, dynamic>>.from(result);
  }

  /// Намира или създава 1:1 разговор
  static Future<String> getOrCreateConversation(String otherUserId) async {
    final myId = _myId;
    if (myId == null) throw Exception('Не си влязъл');

    final existing = await _supabase
        .from('conversations')
        .select('id')
        .or(
          'and(participant_1.eq.$myId,participant_2.eq.$otherUserId),'
          'and(participant_1.eq.$otherUserId,participant_2.eq.$myId)',
        )
        .maybeSingle();

    if (existing != null) {
      return existing['id'] as String;
    }

    final created = await _supabase
        .from('conversations')
        .insert({'participant_1': myId, 'participant_2': otherUserId})
        .select('id')
        .single();

    return created['id'] as String;
  }

  /// Списък с моите разговори
  static Future<List<Map<String, dynamic>>> getMyConversations() async {
    final myId = _myId;
    if (myId == null) return [];

    final result = await _supabase
        .from('conversations')
        .select('''
          id,
          created_at,
          last_message_at,
          participant_1,
          participant_2
        ''')
        .or('participant_1.eq.$myId,participant_2.eq.$myId')
        .order('last_message_at', ascending: false);

    final list = <Map<String, dynamic>>[];
    for (final row in result) {
      final p1 = row['participant_1'] as String;
      final otherId = p1 == myId ? row['participant_2'] : row['participant_1'];

      list.add({
        'conversation_id': row['id'],
        'other_user_id': otherId,
        'last_message_at': row['last_message_at'],
        'created_at': row['created_at'],
      });
    }

    if (list.isEmpty) return list;

    final otherIds = list.map((e) => e['other_user_id'] as String).toList();
    final profiles = await _supabase
        .from('profiles')
        .select('id, username, display_name, avatar_url, public_key')
        .inFilter('id', otherIds);

    final profileMap = {for (final p in profiles) p['id'] as String: p};

    for (final item in list) {
      item['other_user'] = profileMap[item['other_user_id']];
    }

    return list;
  }

  /// Изпраща криптирано съобщение.
  /// Връща записания ред, за да може UI-то да го покаже веднага.
  static Future<Map<String, dynamic>> sendEncryptedMessage({
    required String conversationId,
    required String plaintext,
    required String theirPublicKeyBase64,
  }) async {
    final myId = _myId;
    if (myId == null) throw Exception('Не си влязъл');

    final encrypted = await MessageCrypto.encrypt(
      plaintext: plaintext,
      theirPublicKeyBase64: theirPublicKeyBase64,
    );

    final inserted = await _supabase
        .from('messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': myId,
          'ciphertext': encrypted.ciphertext,
          'nonce': encrypted.nonce,
          'is_deleted': false,
        })
        .select('id, sender_id, ciphertext, nonce, created_at, read_at')
        .single();

    await _supabase
        .from('conversations')
        .update({'last_message_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', conversationId);

    return Map<String, dynamic>.from(inserted);
  }

  /// Зарежда съобщенията (криптирани).
  /// Включва и редове с is_deleted = NULL (стари записи).
  static Future<List<Map<String, dynamic>>> getMessages(
    String conversationId,
  ) async {
    final result = await _supabase
        .from('messages')
        .select('id, sender_id, ciphertext, nonce, created_at, read_at')
        .eq('conversation_id', conversationId)
        .or('is_deleted.eq.false,is_deleted.is.null')
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(result);
  }

  /// Маркира всички непрочетени съобщения от другия като прочетени.
  static Future<void> markMessagesAsRead(String conversationId) async {
    final myId = _myId;
    if (myId == null) return;

    try {
      await _supabase
          .from('messages')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('conversation_id', conversationId)
          .neq('sender_id', myId)
          .filter('read_at', 'is', null);
    } catch (e) {
      // Не чупим UI-то ако колоната още липсва
      // ignore: avoid_print
      print('markMessagesAsRead error: $e');
    }
  }
}