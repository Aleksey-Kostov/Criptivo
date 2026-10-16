import 'package:supabase_flutter/supabase_flutter.dart';

import '../crypto/key_manager.dart';

class AuthService {
  static final _supabase = Supabase.instance.client;

  /// Регистрация
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
    String? displayName,
  }) async {
    // При регистрация създаваме ключове само ако липсват.
    // Никога не заменяме вече съществуваща локална идентичност.
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

    // Регистрация в Supabase.
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'username': username,
        'display_name': displayName ?? username,
      },
    );

    // Публикуваме публичния ключ само за новата регистрация.
    // Ако Supabase не върне потребител, не правим промени в профила.
    final user = response.user;

    if (user != null) {
      await _supabase.from('profiles').update({
        'public_key': publicKey,
        'username': username,
        'display_name': displayName ?? username,
      }).eq('id', user.id);
    }

    return response;
  }

  /// Вход
  ///
  /// ВАЖНО:
  /// Входът не генерира нови криптографски ключове и не презаписва
  /// публичния ключ в профила. Това предпазва съществуващата
  /// криптографска идентичност и достъпа до старите съобщения.
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
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
