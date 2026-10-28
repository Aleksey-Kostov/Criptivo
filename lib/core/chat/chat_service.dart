import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';
import '../crypto/message_crypto.dart';

class ChatService {
  static final _supabase = Supabase.instance.client;

  static String? get _myId => _supabase.auth.currentUser?.id;

  /// Проверява локалната идентичност и публичния ключ на получателя.
  /// Връща потвърдения публичен ключ или прекратява операцията с грешка.
  static Future<String> verifySendingIdentity({
    required String conversationId,
    required String theirPublicKeyBase64,
  }) async {
    final myId = _myId;

    if (myId == null) {
      throw StateError('Не си влязъл в акаунта.');
    }

    final keyStatus = await AuthService.syncPublicKeyToProfile();

    if (keyStatus != KeySyncStatus.ok) {
      throw StateError(
        'Криптографската идентичност не е потвърдена '
        '(статус: ${keyStatus.name}). Изпращането е спряно.',
      );
    }

    final conversation = await _supabase
        .from('conversations')
        .select('participant_1, participant_2')
        .eq('id', conversationId)
        .maybeSingle();

    if (conversation == null) {
      throw StateError('Разговорът не беше намерен.');
    }

    final participant1 = conversation['participant_1'] as String?;
    final participant2 = conversation['participant_2'] as String?;

    if (participant1 != myId && participant2 != myId) {
      throw StateError('Нямаш достъп до този разговор.');
    }

    final otherId = participant1 == myId ? participant2 : participant1;

    if (otherId == null || otherId.isEmpty || otherId == myId) {
      throw StateError('Невалиден получател.');
    }

    final profile = await _supabase
        .from('profiles')
        .select('public_key')
        .eq('id', otherId)
        .maybeSingle();

    final serverKey = profile?['public_key'] as String?;

    if (serverKey == null || serverKey.trim().isEmpty) {
      throw StateError('Получателят няма публикуван публичен ключ.');
    }

    if (serverKey != theirPublicKeyBase64) {
      throw StateError(
        'Публичният ключ на получателя се е променил. '
        'Обнови чата и провери идентичността му.',
      );
    }

    return serverKey;
  }

  /// Търсене на потребители по username.
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

  /// Намира или създава 1:1 разговор.
  static Future<String> getOrCreateConversation(String otherUserId) async {
    final myId = _myId;
    if (myId == null) throw StateError('Не си влязъл.');

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

  /// Списък с моите разговори.
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
          participant_2,
          disappear_seconds
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
        'disappear_seconds': row['disappear_seconds'],
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

  /// null = изключено; иначе секунди (30, 300, 3600, ...).
  static Future<void> setDisappearSeconds({
    required String conversationId,
    required int? seconds,
  }) async {
    await _supabase
        .from('conversations')
        .update({'disappear_seconds': seconds})
        .eq('id', conversationId);
  }

  static Future<int?> getDisappearSeconds(String conversationId) async {
    final row = await _supabase
        .from('conversations')
        .select('disappear_seconds')
        .eq('id', conversationId)
        .maybeSingle();

    return row?['disappear_seconds'] as int?;
  }

  /// Изпраща криптирано съобщение след проверки на идентичността
  /// и участниците в разговора.
  static Future<Map<String, dynamic>> sendEncryptedMessage({
    required String conversationId,
    required String plaintext,
    required String theirPublicKeyBase64,
  }) async {
    final myId = _myId;
    if (myId == null) throw StateError('Не си влязъл.');

    final verifiedPeerKey = await verifySendingIdentity(
      conversationId: conversationId,
      theirPublicKeyBase64: theirPublicKeyBase64,
    );

    final encrypted = await MessageCrypto.encrypt(
      plaintext: plaintext,
      theirPublicKeyBase64: verifiedPeerKey,
    );

    int? disappearSeconds;

    try {
      disappearSeconds = await getDisappearSeconds(conversationId);
    } catch (_) {
      // Запазва досегашното поведение при недостъпна настройка.
      disappearSeconds = null;
    }

    final expiresAt = disappearSeconds != null
        ? DateTime.now()
              .toUtc()
              .add(Duration(seconds: disappearSeconds))
              .toIso8601String()
        : null;

    final inserted = await _supabase
        .from('messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': myId,
          'ciphertext': encrypted.ciphertext,
          'nonce': encrypted.nonce,
          'is_deleted': false,
          'expires_at': expiresAt,
        })
        .select(
          'id, sender_id, ciphertext, nonce, created_at, read_at, expires_at',
        )
        .single();

    await _supabase
        .from('conversations')
        .update({'last_message_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', conversationId);

    return Map<String, dynamic>.from(inserted);
  }

  /// Зарежда криптираните съобщения, без изтрити и изтекли.
  static Future<List<Map<String, dynamic>>> getMessages(
    String conversationId,
  ) async {
    final result = await _supabase
        .from('messages')
        .select(
          'id, sender_id, ciphertext, nonce, created_at, read_at, expires_at',
        )
        .eq('conversation_id', conversationId)
        .or('is_deleted.eq.false,is_deleted.is.null')
        .order('created_at', ascending: true);

    final now = DateTime.now().toUtc();
    final list = <Map<String, dynamic>>[];

    for (final row in result) {
      final map = Map<String, dynamic>.from(row);
      final exp = map['expires_at'];

      if (exp != null) {
        try {
          final expires = DateTime.parse(exp.toString()).toUtc();
          if (!expires.isAfter(now)) continue;
        } catch (_) {
          // Запазва съществуващото поведение при невалидна дата.
        }
      }

      list.add(map);
    }

    return list;
  }

  /// Маркира непрочетените съобщения от другия участник като прочетени.
  static Future<void> markMessagesAsRead(String conversationId) async {
    final myId = _myId;
    if (myId == null) return;

    try {
      await _supabase
          .from('messages')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('conversation_id', conversationId)
          .neq('sender_id', myId)
          .isFilter('read_at', null);
    } catch (e) {
      // ignore: avoid_print
      print('markMessagesAsRead error: $e');
    }
  }

  /// Soft-delete на изтеклите съобщения.
  static Future<void> purgeExpiredMessages(String conversationId) async {
    try {
      await _supabase
          .from('messages')
          .update({'is_deleted': true, 'ciphertext': '', 'nonce': ''})
          .eq('conversation_id', conversationId)
          .lt('expires_at', DateTime.now().toUtc().toIso8601String())
          .or('is_deleted.eq.false,is_deleted.is.null');
    } catch (e) {
      // ignore: avoid_print
      print('purgeExpiredMessages error: $e');
    }
  }
}
