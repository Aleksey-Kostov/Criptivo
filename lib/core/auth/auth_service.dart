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
    // 1. Генерираме ключове ако няма
    if (!await KeyManager.hasKeys()) {
      await KeyManager.generateAndStoreKeys();
    }

    final publicKey = await KeyManager.getPublicKeyBase64();

    // 2. Регистрация в Supabase
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'username': username,
        'display_name': displayName ?? username,
      },
    );

    // 3. Качваме публичния ключ в profiles
    if (response.user != null && publicKey != null) {
      await _supabase.from('profiles').update({
        'public_key': publicKey,
        'username': username,
        'display_name': displayName ?? username,
      }).eq('id', response.user!.id);
    }

    return response;
  }

  /// Вход
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    // Уверяваме се, че имаме ключове локално
    if (!await KeyManager.hasKeys()) {
      await KeyManager.generateAndStoreKeys();
      // Забележка: при нов device ключовете ще са различни.
      // По-късно ще добавим multi-device / recovery.
    }

    // Обновяваме публичния ключ ако е нужно
    final publicKey = await KeyManager.getPublicKeyBase64();
    if (response.user != null && publicKey != null) {
      await _supabase.from('profiles').update({
        'public_key': publicKey,
      }).eq('id', response.user!.id);
    }

    return response;
  }

  /// Изход
  static Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  /// Текущ потребител
  static User? get currentUser => _supabase.auth.currentUser;

  /// Stream за auth промени
  static Stream<AuthState> get authStateChanges =>
      _supabase.auth.onAuthStateChange;
}
