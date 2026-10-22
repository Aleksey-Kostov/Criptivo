import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../crypto/key_manager.dart';

class AuthService {
  static final _supabase = Supabase.instance.client;

  /// Проверява дали username е свободен (case-insensitive).
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

  /// Регистрация
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
    String? displayName,
  }) async {
    final normalizedUsername = username.trim().toLowerCase();

    // 1) Username свободен ли е?
    final available = await isUsernameAvailable(normalizedUsername);
    if (!available) {
      throw StateError('Този username вече е зает');
    }

    // 2) Ключове — създаваме само ако липсват
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

    // 3) Регистрация в Supabase Auth
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'username': normalizedUsername,
        'display_name': displayName ?? normalizedUsername,
      },
    );

    // 4) Публикуваме public key + username в профила
    final user = response.user;

    if (user != null) {
      await _supabase.from('profiles').update({
        'public_key': publicKey,
        'username': normalizedUsername,
        'display_name': displayName ?? normalizedUsername,
      }).eq('id', user.id);
    }

    return response;
  }

  /// Вход
  ///
  /// ВАЖНО:
  /// Входът не генерира нови криптографски ключове.
  /// Public key-ът се синхронизира отделно чрез [syncPublicKeyToProfile].
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

  /// Качва текущия локален public key в профила.
  static Future<void> syncPublicKeyToProfile() async {
    final user = currentUser;
    if (user == null) return;

    final publicKey = await KeyManager.getPublicKeyBase64();
    if (publicKey == null || publicKey.isEmpty) {
      debugPrint('syncPublicKeyToProfile: няма локален public key');
      return;
    }

    try {
      await _supabase
          .from('profiles')
          .update({'public_key': publicKey})
          .eq('id', user.id);

      debugPrint('Public key синхронизиран: $publicKey');
    } catch (e) {
      debugPrint('Грешка при sync на public key: $e');
    }
  }

  /// Изход
  static Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  /// Текущ потребител
  static User? get currentUser => _supabase.auth.currentUser;

  /// Stream за промени в състоянието на удостоверяването
  static Stream<AuthState> get authStateChanges =>
      _supabase.auth.onAuthStateChange;
}
