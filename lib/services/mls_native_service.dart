import 'dart:convert';

import '../src/rust/api.dart' as rust_api;
import '../src/rust/frb_generated.dart';

/// Flutter service за връзка с Rust/OpenMLS чрез FRB.
class MlsNativeService {
  MlsNativeService._();

  static Future<void>? _initialization;

  /// Инициализира native bridge само веднъж.
  static Future<void> initialize() {
    return _initialization ??= RustLib.init();
  }

  /// Проверява дали Rust модулът отговаря.
  static Future<String> checkStatus() async {
    await initialize();
    return rust_api.mlsNativeStatus();
  }

  /// Връща версията на Rust/OpenMLS crate.
  static Future<String> getVersion() async {
    await initialize();
    return rust_api.mlsVersion();
  }

  /// Създава MLS идентичност.
  ///
  /// ВАЖНО: успешният резултат съдържа protected_state_json,
  /// който включва чувствителен криптографски материал.
  /// Не отпечатвай резултата в логове и не го изпращай към Supabase.
  static Future<Map<String, dynamic>> createIdentity(String identity) async {
    await initialize();

    final normalizedIdentity = identity.trim();

    if (normalizedIdentity.isEmpty) {
      throw ArgumentError('Identity must not be empty.');
    }

    if (utf8.encode(normalizedIdentity).length > 255) {
      throw ArgumentError('Identity must not exceed 255 UTF-8 bytes.');
    }

    final response = await rust_api.mlsCreateIdentity(
      identity: normalizedIdentity,
    );

    final decoded = jsonDecode(response);

    if (decoded is! Map) {
      throw const FormatException('Rust returned an unexpected JSON response.');
    }

    final result = Map<String, dynamic>.from(decoded);

    if (result['status'] == 'error') {
      throw MlsNativeException(
        result['error']?.toString() ?? 'Unknown Rust error.',
      );
    }

    if (result['status'] != 'key_package_created') {
      throw const FormatException(
        'Rust did not confirm successful identity creation.',
      );
    }

    return result;
  }
}

/// Грешка, върната от native MLS слоя.
class MlsNativeException implements Exception {
  const MlsNativeException(this.message);

  final String message;

  @override
  String toString() => 'MlsNativeException: $message';
}
