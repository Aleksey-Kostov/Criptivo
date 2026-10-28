import 'package:supabase_flutter/supabase_flutter.dart';

class ReactionService {
  static final _supabase = Supabase.instance.client;

  static String? get _myId => _supabase.auth.currentUser?.id;

  /// Зарежда реакции за списък от message ids.
  /// Връща: messageId → List<{emoji, user_id, count aggregated later in UI}>
  static Future<Map<String, List<Map<String, dynamic>>>> getForMessages(
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) return {};

    final result = await _supabase
        .from('message_reactions')
        .select('id, message_id, user_id, emoji, created_at')
        .inFilter('message_id', messageIds);

    final map = <String, List<Map<String, dynamic>>>{};
    for (final row in result) {
      final mid = row['message_id'] as String;
      map.putIfAbsent(mid, () => []).add(Map<String, dynamic>.from(row));
    }
    return map;
  }

  /// Toggle: ако вече имаш същия emoji → маха; иначе добавя.
  /// (Един user може да има няколко различни emoji на съобщение.)
  static Future<void> toggle({
    required String messageId,
    required String emoji,
  }) async {
    final myId = _myId;
    if (myId == null) throw Exception('Не си влязъл');

    final existing = await _supabase
        .from('message_reactions')
        .select('id')
        .eq('message_id', messageId)
        .eq('user_id', myId)
        .eq('emoji', emoji)
        .maybeSingle();

    if (existing != null) {
      await _supabase
          .from('message_reactions')
          .delete()
          .eq('id', existing['id']);
    } else {
      await _supabase.from('message_reactions').insert({
        'message_id': messageId,
        'user_id': myId,
        'emoji': emoji,
      });
    }
  }

  /// Агрегира сурови редове → [{emoji, count, mine}]
  static List<Map<String, dynamic>> aggregate(List<Map<String, dynamic>> rows) {
    final myId = _myId;
    final byEmoji = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final e = r['emoji'] as String;
      byEmoji.putIfAbsent(e, () => []).add(r);
    }
    return byEmoji.entries.map((e) {
        final mine = e.value.any((r) => r['user_id'] == myId);
        return {'emoji': e.key, 'count': e.value.length, 'mine': mine};
      }).toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
  }
}
