import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../crypto/key_manager.dart';

/// Резултат от sync на public key — за UI.
enum KeySyncStatus {
  /// Локалният ключ = сървърния (или сървърът беше празен и го записахме).
  ok,

  /// Локално има ключове, на сървъра — друг public key.
  /// НЕ презаписваме. Трябва restore от backup.
  mismatch,

  /// Няма локален public key.
  missingLocal,
}

class AuthService {
  static final _supabase = Supabase.instance.client;

  /// Последен статус след [syncPublicKeyToProfile] (за Settings / banner).
  static KeySyncStatus lastKeySyncStatus = KeySyncStatus.ok;

  static Future<bool> isUsernameAvailable(String username) async {
    final normalized = username.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    final row = await _supabase
        .from('profiles')
        .select('id')
        .ilike('username', normalized)
        .maybeSingle();

    return row == null;
  }

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
    String? displayName,
  }) async {
    final normalizedUsername = username.trim().toLowerCase();

    final available = await isUsernameAvailable(normalizedUsername);
    if (!available) {
      throw StateError('Този username вече е зает');
    }

    if (!await KeyManager.hasKeys()) {
      await KeyManager.generateAndStoreKeys();
    }

    final publicKey = await KeyManager.getPublicKeyBase64();
    if (publicKey == null || publicKey.isEmpty) {
      throw StateError(
        'Криптографските ключове не са налични. '
        'Регистрацията не може да продължи безопасно.',
      );
    }

    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'username': normalizedUsername,
        'display_name': displayName ?? normalizedUsername,
      },
    );

    final user = response.user;
    if (user != null) {
      await _supabase.from('profiles').update({
        'public_key': publicKey,
        'username': normalizedUsername,
        'display_name': displayName ?? normalizedUsername,
      }).eq('id', user.id);
    }

    lastKeySyncStatus = KeySyncStatus.ok;
    return response;
  }

  /// Вход — НЕ генерира ключове. Sync е внимателен (виж [syncPublicKeyToProfile]).
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (response.session != null) {
      await syncPublicKeyToProfile();
    }

    return response;
  }

  /// Синхронизация на public key.
  ///
  /// - Ако на сървъра няма ключ → записваме локалния.
  /// - Ако локалният == сървърния → OK.
  /// - Ако се различават → **НЕ презаписваме** (иначе чупим старите съобщения
  ///   и другите устройства). Връща [KeySyncStatus.mismatch].
  static Future<KeySyncStatus> syncPublicKeyToProfile() async {
    final user = currentUser;
    if (user == null) {
      lastKeySyncStatus = KeySyncStatus.missingLocal;
      return lastKeySyncStatus;
    }

    final local = await KeyManager.getPublicKeyBase64();
    if (local == null || local.isEmpty) {
      debugPrint('syncPublicKeyToProfile: няма локален public key');
      lastKeySyncStatus = KeySyncStatus.missingLocal;
      return lastKeySyncStatus;
    }

    try {
      final row = await _supabase
          .from('profiles')
          .select('public_key')
          .eq('id', user.id)
          .maybeSingle();

      final remote = row?['public_key'] as String?;

      if (remote == null || remote.isEmpty) {
        await _supabase
            .from('profiles')
            .update({'public_key': local})
            .eq('id', user.id);
        debugPrint('Public key записан (сървърът беше празен): $local');
        lastKeySyncStatus = KeySyncStatus.ok;
        return lastKeySyncStatus;
      }

      if (remote == local) {
        debugPrint('Public key OK (локален == сървър): $local');
        lastKeySyncStatus = KeySyncStatus.ok;
        return lastKeySyncStatus;
      }

      // MISMATCH — критично: не пипаме сървъра
      debugPrint(
        'Key MISMATCH: local=$local remote=$remote — '
        'нужен е Key Backup restore. Сървърният ключ НЕ е презаписан.',
      );
      lastKeySyncStatus = KeySyncStatus.mismatch;
      return lastKeySyncStatus;
    } catch (e) {
      debugPrint('Грешка при sync на public key: $e');
      lastKeySyncStatus = KeySyncStatus.missingLocal;
      return lastKeySyncStatus;
    }
  }

  /// След успешен import на backup — форсира запис на локалния ключ към профила.
  static Future<void> forcePublishLocalPublicKey() async {
    final user = currentUser;
    if (user == null) return;
    final local = await KeyManager.getPublicKeyBase64();
    if (local == null || local.isEmpty) return;

    await _supabase
        .from('profiles')
        .update({'public_key': local})
        .eq('id', user.id);
    lastKeySyncStatus = KeySyncStatus.ok;
    debugPrint('Public key force-published: $local');
  }

  static Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  static User? get currentUser => _supabase.auth.currentUser;

  static Stream<AuthState> get authStateChanges =>
      _supabase.auth.onAuthStateChange;
}
