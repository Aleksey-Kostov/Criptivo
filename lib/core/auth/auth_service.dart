import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../crypto/key_manager.dart';

/// Резултат от синхронизацията на публичния ключ.
enum KeySyncStatus {
  /// Локалният ключ съвпада със сървърния или е публикуван успешно.
  ok,

  /// Локалният и сървърният публичен ключ се различават.
  /// Сървърният ключ не се презаписва автоматично.
  mismatch,

  /// Липсва локална криптографска идентичност.
  missingLocal,

  /// Локалната двойка ключове е невалидна или непълна.
  invalidLocal,

  /// Грешка при комуникация със Supabase или синхронизацията.
  error,
}

class AuthService {
  static final _supabase = Supabase.instance.client;

  /// Последен резултат от синхронизацията на публичния ключ.
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
    final normalizedDisplayName = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : normalizedUsername;

    final available = await isUsernameAvailable(normalizedUsername);

    if (!available) {
      throw StateError('Този username вече е зает');
    }

    // Генерираме ключове само ако и двата липсват.
    // Непълна или невалидна идентичност прекратява регистрацията.
    if (!await KeyManager.hasKeys()) {
      await KeyManager.generateAndStoreKeys();
    }

    // Повторна проверка преди публикуване на публичния ключ.
    if (!await KeyManager.hasKeys()) {
      throw StateError(
        'Криптографските ключове не са налични. '
        'Регистрацията не може да продължи безопасно.',
      );
    }

    final publicKey = await KeyManager.getPublicKeyBase64();

    if (publicKey == null || publicKey.isEmpty) {
      throw StateError(
        'Публичният ключ липсва. '
        'Регистрацията не може да продължи безопасно.',
      );
    }

    final response = await _supabase.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'username': normalizedUsername,
        'display_name': normalizedDisplayName,
      },
    );

    final user = response.user;

    if (user != null) {
      final result = await _supabase
          .from('profiles')
          .update({
            'public_key': publicKey,
            'username': normalizedUsername,
            'display_name': normalizedDisplayName,
          })
          .eq('id', user.id)
          .select('id')
          .maybeSingle();

      if (result == null) {
        lastKeySyncStatus = KeySyncStatus.error;

        throw StateError(
          'Акаунтът е създаден, но профилът не беше актуализиран. '
          'Не изтривай и не генерирай нови ключове. '
          'Провери профила и настройките за достъп в Supabase.',
        );
      }

      lastKeySyncStatus = KeySyncStatus.ok;
    } else {
      // При изискване за потвърждение на имейл Supabase
      // може да не върне потребител веднага.
      lastKeySyncStatus = KeySyncStatus.error;
    }

    return response;
  }

  /// Входът не генерира нова криптографска идентичност.
  ///
  /// Синхронизацията се извършва от HomePage._init().
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return _supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Безопасно синхронизира локалния публичен ключ с профила.
  ///
  /// - Липсваща локална идентичност: missingLocal.
  /// - Невалидна локална двойка: invalidLocal.
  /// - Празен сървърен ключ: опит за публикуване на локалния ключ.
  /// - Съвпадащи ключове: ok.
  /// - Различни ключове: mismatch, без презаписване.
  /// - Грешка при заявка или запис: error.
  static Future<KeySyncStatus> syncPublicKeyToProfile() async {
    final user = currentUser;

    if (user == null) {
      lastKeySyncStatus = KeySyncStatus.error;
      return lastKeySyncStatus;
    }

    late final String local;

    // Първо валидираме локалната криптографска идентичност.
    try {
      final hasKeys = await KeyManager.hasKeys();

      if (!hasKeys) {
        debugPrint('Criptivo: локалните криптографски ключове липсват.');

        lastKeySyncStatus = KeySyncStatus.missingLocal;
        return lastKeySyncStatus;
      }

      final publicKey = await KeyManager.getPublicKeyBase64();

      if (publicKey == null || publicKey.isEmpty) {
        lastKeySyncStatus = KeySyncStatus.invalidLocal;
        return lastKeySyncStatus;
      }

      local = publicKey;
    } catch (e) {
      debugPrint(
        'Criptivo: локалната криптографска идентичност '
        'не премина проверката: $e',
      );

      lastKeySyncStatus = KeySyncStatus.invalidLocal;
      return lastKeySyncStatus;
    }

    // Следващите грешки се отнасят до Supabase или синхронизацията.
    try {
      final row = await _supabase
          .from('profiles')
          .select('public_key')
          .eq('id', user.id)
          .maybeSingle();

      if (row == null) {
        debugPrint('Criptivo: профилът на потребителя не беше намерен.');

        lastKeySyncStatus = KeySyncStatus.error;
        return lastKeySyncStatus;
      }

      final remote = row['public_key'] as String?;

      if (remote == null || remote.isEmpty) {
        final result = await _supabase
            .from('profiles')
            .update({'public_key': local})
            .eq('id', user.id)
            .select('id')
            .maybeSingle();

        if (result == null) {
          debugPrint(
            'Criptivo: публичният ключ не е публикуван. '
            'Записът не е потвърден.',
          );

          lastKeySyncStatus = KeySyncStatus.error;
          return lastKeySyncStatus;
        }

        debugPrint('Criptivo: публичният ключ е публикуван.');

        lastKeySyncStatus = KeySyncStatus.ok;
        return lastKeySyncStatus;
      }

      if (remote == local) {
        debugPrint('Criptivo: локалният и сървърният публичен ключ съвпадат.');

        lastKeySyncStatus = KeySyncStatus.ok;
        return lastKeySyncStatus;
      }

      // Критично: не заменяме сървърната идентичност автоматично.
      debugPrint(
        'Criptivo: открито е несъответствие на публичните ключове. '
        'Сървърният ключ не е променен. '
        'Необходимо е възстановяване на правилната идентичност.',
      );

      lastKeySyncStatus = KeySyncStatus.mismatch;
      return lastKeySyncStatus;
    } catch (e) {
      debugPrint('Criptivo: синхронизацията на публичния ключ се провали: $e');

      lastKeySyncStatus = KeySyncStatus.error;
      return lastKeySyncStatus;
    }
  }

  /// Публикува локалния ключ след изрично потвърдено възстановяване.
  ///
  /// ВНИМАНИЕ: заменя публичния ключ в профила.
  /// Използвай само след възстановяване на правилната идентичност
  /// и изрично потвърждение от потребителя.
  static Future<void> forcePublishLocalPublicKey() async {
    final user = currentUser;

    if (user == null) {
      throw StateError(
        'Няма влязъл потребител. Публичният ключ не е публикуван.',
      );
    }

    final hasKeys = await KeyManager.hasKeys();

    if (!hasKeys) {
      throw StateError(
        'Локалните криптографски ключове липсват. '
        'Публичният ключ не е публикуван.',
      );
    }

    final local = await KeyManager.getPublicKeyBase64();

    if (local == null || local.isEmpty) {
      throw StateError(
        'Локалният публичен ключ липсва. '
        'Публичният ключ не е публикуван.',
      );
    }

    final result = await _supabase
        .from('profiles')
        .update({'public_key': local})
        .eq('id', user.id)
        .select('id')
        .maybeSingle();

    if (result == null) {
      lastKeySyncStatus = KeySyncStatus.error;

      throw StateError(
        'Публичният ключ не беше публикуван. '
        'Профилът липсва или записът не е разрешен.',
      );
    }

    lastKeySyncStatus = KeySyncStatus.ok;

    // Не записваме самия ключ в логовете.
    debugPrint(
      'Criptivo: публичният ключ е публикуван '
      'след потвърдено възстановяване.',
    );
  }

  static Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  static User? get currentUser => _supabase.auth.currentUser;

  static Stream<AuthState> get authStateChanges =>
      _supabase.auth.onAuthStateChange;
}
