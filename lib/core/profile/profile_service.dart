import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';
import 'profile_privacy.dart';

class ProfileService {
  static final _supabase = Supabase.instance.client;

  static String? get _myId => _supabase.auth.currentUser?.id;

  static const _fullSelect =
      'id, username, display_name, avatar_url, public_key, '
      'phone, phone_visibility, phone_searchable, '
      'email_visibility, bio, bio_visibility, updated_at';

  /// Собствен пълен профил (+ auth email).
  static Future<Map<String, dynamic>?> getMyProfile() async {
    final user = AuthService.currentUser;
    if (user == null) return null;

    final row = await _supabase
        .from('profiles')
        .select(_fullSelect)
        .eq('id', user.id)
        .maybeSingle();

    if (row == null) return null;

    final map = Map<String, dynamic>.from(row);
    map['email'] = user.email;
    map['email_confirmed'] = user.emailConfirmedAt != null;
    return map;
  }

  /// Публичен изглед според privacy на собственика.
  /// [viewerId] = текущ потребител (за „това съм аз“ → всичко).
  static Future<Map<String, dynamic>?> getPublicProfile(String userId) async {
    final row = await _supabase
        .from('profiles')
        .select(_fullSelect)
        .eq('id', userId)
        .maybeSingle();

    if (row == null) return null;
    return filterForViewer(Map<String, dynamic>.from(row), viewerId: _myId);
  }

  /// Маскира phone / email / bio според visibility.
  static Map<String, dynamic> filterForViewer(
    Map<String, dynamic> raw, {
    String? viewerId,
  }) {
    final id = raw['id'] as String?;
    final isSelf = viewerId != null && id == viewerId;

    final out = <String, dynamic>{
      'id': raw['id'],
      'username': raw['username'],
      'display_name': raw['display_name'],
      'avatar_url': raw['avatar_url'],
      'public_key': raw['public_key'],
    };

    if (isSelf) {
      out['phone'] = raw['phone'];
      out['phone_visibility'] = raw['phone_visibility'];
      out['phone_searchable'] = raw['phone_searchable'];
      out['bio'] = raw['bio'];
      out['bio_visibility'] = raw['bio_visibility'];
      out['email_visibility'] = raw['email_visibility'];
      out['is_self'] = true;
      return out;
    }

    out['is_self'] = false;

    final phoneVis = ProfileVisibility.fromDb(
      raw['phone_visibility'] as String?,
    );
    if (phoneVis == ProfileVisibility.everyone) {
      out['phone'] = raw['phone'];
    }

    final bioVis = ProfileVisibility.fromDb(raw['bio_visibility'] as String?);
    if (bioVis == ProfileVisibility.everyone) {
      out['bio'] = raw['bio'];
    }

    // Email никога не идва от profiles select тук без auth —
    // ако по-късно държите email в profiles, маскирайте:
    final emailVis = ProfileVisibility.fromDb(
      raw['email_visibility'] as String?,
    );
    if (emailVis == ProfileVisibility.everyone && raw['email'] != null) {
      out['email'] = raw['email'];
    }

    return out;
  }

  static Future<void> updateDisplayName(String name) async {
    final id = _myId;
    if (id == null) throw Exception('Не си влязъл');
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Името е празно');

    await _supabase
        .from('profiles')
        .update({
          'display_name': trimmed,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }

  static Future<void> updateBio(String? bio) async {
    final id = _myId;
    if (id == null) throw Exception('Не си влязъл');
    final text = bio?.trim();
    await _supabase
        .from('profiles')
        .update({
          'bio': (text == null || text.isEmpty) ? null : text,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }

  /// [phone] в E.164 (+359...) или null за изтриване.
  static Future<void> updatePhone({
    String? phone,
    ProfileVisibility visibility = ProfileVisibility.nobody,
    bool searchable = false,
  }) async {
    final id = _myId;
    if (id == null) throw Exception('Не си влязъл');

    String? normalized;
    if (phone != null && phone.trim().isNotEmpty) {
      normalized = normalizePhone(phone);
      if (normalized == null) {
        throw ArgumentError('Невалиден телефон. Ползвай формат +3598...');
      }
    }

    // searchable само ако има номер
    final canSearch = normalized != null && searchable;

    await _supabase
        .from('profiles')
        .update({
          'phone': normalized,
          'phone_visibility': visibility.db,
          'phone_searchable': canSearch,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }

  static Future<void> updatePrivacy({
    ProfileVisibility? phoneVisibility,
    ProfileVisibility? emailVisibility,
    ProfileVisibility? bioVisibility,
    bool? phoneSearchable,
  }) async {
    final id = _myId;
    if (id == null) throw Exception('Не си влязъл');

    final patch = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (phoneVisibility != null) {
      patch['phone_visibility'] = phoneVisibility.db;
    }
    if (emailVisibility != null) {
      patch['email_visibility'] = emailVisibility.db;
    }
    if (bioVisibility != null) {
      patch['bio_visibility'] = bioVisibility.db;
    }
    if (phoneSearchable != null) {
      patch['phone_searchable'] = phoneSearchable;
    }

    await _supabase.from('profiles').update(patch).eq('id', id);
  }

  /// Смяна на login email → Supabase праща confirmation.
  static Future<void> requestEmailChange(String newEmail) async {
    final email = newEmail.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      throw ArgumentError('Невалиден email');
    }
    await _supabase.auth.updateUser(UserAttributes(email: email));
  }

  /// Търсене: username ILIKE или phone (само phone_searchable).
  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final myId = _myId ?? '';

    // Телефонен опит?
    final asPhone = normalizePhone(q);
    if (asPhone != null) {
      final byPhone = await _supabase
          .from('profiles')
          .select(
            'id, username, display_name, avatar_url, public_key, phone, phone_visibility',
          )
          .eq('phone', asPhone)
          .eq('phone_searchable', true)
          .neq('id', myId)
          .limit(10);

      return List<Map<String, dynamic>>.from(byPhone).map((row) {
        return filterForViewer(row, viewerId: myId);
      }).toList();
    }

    final byName = await _supabase
        .from('profiles')
        .select(
          'id, username, display_name, avatar_url, public_key, '
          'phone, phone_visibility, bio, bio_visibility, email_visibility',
        )
        .or('username.ilike.%$q%,display_name.ilike.%$q%')
        .neq('id', myId)
        .limit(20);

    return List<Map<String, dynamic>>.from(byName).map((row) {
      return filterForViewer(row, viewerId: myId);
    }).toList();
  }

  /// Нормализация към E.164-ish. Връща null ако е невалидно.
  static String? normalizePhone(String input) {
    var s = input.trim().replaceAll(RegExp(r'[\s\-()]'), '');
    if (s.startsWith('00')) s = '+${s.substring(2)}';
    // локални 08... → +3598...
    if (RegExp(r'^0[89]\d{8}$').hasMatch(s)) {
      s = '+359${s.substring(1)}';
    }
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(s)) return null;
    return s;
  }
}
