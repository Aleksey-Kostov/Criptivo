import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';
import '../crypto/mls_key_package_service.dart';
import '../crypto/mls_secure_storage.dart';
import '../crypto/mls_service.dart';

/// MLS session + send/receive за един conversation.
class MlsChatService {
  MlsChatService._();
  static final instance = MlsChatService._();

  static final _db = Supabase.instance.client;

  String? get _myId => AuthService.currentUser?.id;

  /// Alice: claim KP → createDm → запис welcome като системно съобщение.
  Future<void> ensureMlsSessionAsInitiator({
    required String conversationId,
    required String otherUserId,
  }) async {
    final existing = await MlsSecureStorage.loadGroupState(conversationId);
    if (existing != null && existing.isNotEmpty) {
      await MlsService.instance.ensureGroupLoaded(conversationId);
      return;
    }

    final kp = await MlsKeyPackageService.instance.claimKeyPackage(otherUserId);
    if (kp == null) {
      throw StateError(
        'Няма наличен KeyPackage за този потребител. '
        'Другият трябва да е влязъл поне веднъж (C3 pool).',
      );
    }

    final dm = await MlsService.instance.createDm(
      conversationId: conversationId,
      theirKeyPackageB64: kp,
    );

    await _db
        .from('conversations')
        .update({'crypto_version': 'mls'})
        .eq('id', conversationId);

    await _db.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': _myId,
      'ciphertext': dm.welcomeB64,
      'nonce': '',
      'crypto_version': 'mls',
      'message_type': 'mls_welcome',
      'is_deleted': false,
    });

    await _db.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': _myId,
      'ciphertext': dm.commitB64,
      'nonce': '',
      'crypto_version': 'mls',
      'message_type': 'mls_commit',
      'is_deleted': false,
    });

    debugPrint('Criptivo: MLS session created $conversationId');
  }

  /// Bob: намира welcome, joinDm, process commit ако има.
  Future<void> ensureMlsSessionAsResponder({
    required String conversationId,
  }) async {
    final existing = await MlsSecureStorage.loadGroupState(conversationId);
    if (existing != null && existing.isNotEmpty) {
      await MlsService.instance.ensureGroupLoaded(conversationId);
      return;
    }

    final welcomeRow = await _db
        .from('messages')
        .select('id, ciphertext')
        .eq('conversation_id', conversationId)
        .eq('message_type', 'mls_welcome')
        .order('created_at')
        .limit(1)
        .maybeSingle();

    if (welcomeRow == null) {
      throw StateError('Няма MLS Welcome за този разговор.');
    }

    await MlsService.instance.joinDm(
      conversationId: conversationId,
      welcomeB64: welcomeRow['ciphertext'] as String,
    );

    final commits = await _db
        .from('messages')
        .select('ciphertext')
        .eq('conversation_id', conversationId)
        .eq('message_type', 'mls_commit')
        .order('created_at');

    for (final row in commits) {
      try {
        await MlsService.instance.process(
          conversationId: conversationId,
          messageB64: row['ciphertext'] as String,
        );
      } catch (e) {
        debugPrint('Criptivo: commit process skip: $e');
      }
    }

    debugPrint('Criptivo: MLS session joined $conversationId');
  }

  /// При отваряне на чат: initiator или responder.
  Future<void> ensureSession({
    required String conversationId,
    required String otherUserId,
  }) async {
    final myId = _myId;
    if (myId == null) throw StateError('Не си влязъл.');

    final conv = await _db
        .from('conversations')
        .select('crypto_version, participant_1, participant_2')
        .eq('id', conversationId)
        .maybeSingle();

    if (conv == null) throw StateError('Разговорът не съществува.');

    final version = conv['crypto_version'] as String? ?? 'x25519';
    final localState = await MlsSecureStorage.loadGroupState(conversationId);

    if (version == 'mls' || localState != null) {
      if (localState != null) {
        await MlsService.instance.ensureGroupLoaded(conversationId);
        return;
      }
      await ensureMlsSessionAsResponder(conversationId: conversationId);
      return;
    }

    await ensureMlsSessionAsInitiator(
      conversationId: conversationId,
      otherUserId: otherUserId,
    );
  }

  Future<Map<String, dynamic>> sendMlsMessage({
    required String conversationId,
    required String plaintext,
  }) async {
    final myId = _myId;
    if (myId == null) throw StateError('Не си влязъл.');

    await MlsService.instance.ensureGroupLoaded(conversationId);
    final enc = await MlsService.instance.encrypt(
      conversationId: conversationId,
      plaintext: plaintext,
    );

    final inserted = await _db
        .from('messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': myId,
          'ciphertext': enc.ciphertextB64,
          'nonce': '',
          'crypto_version': 'mls',
          'message_type': 'mls_application',
          'is_deleted': false,
        })
        .select(
          'id, sender_id, ciphertext, nonce, created_at, read_at, expires_at, crypto_version, message_type',
        )
        .single();

    await _db
        .from('conversations')
        .update({
          'last_message_at': DateTime.now().toUtc().toIso8601String(),
          'crypto_version': 'mls',
        })
        .eq('id', conversationId);

    return Map<String, dynamic>.from(inserted);
  }

  /// Decrypt един ред. Връща plaintext или null за welcome/commit.
  Future<String?> decryptRow(Map<String, dynamic> row) async {
    final type = row['message_type'] as String? ?? 'text';
    final version = row['crypto_version'] as String? ?? 'x25519';

    if (version != 'mls') return null;

    if (type == 'mls_welcome' || type == 'mls_commit') {
      return null;
    }

    final conversationId = row['conversation_id'] as String?;
    final cid = conversationId ?? row['_conversation_id'] as String?;
    if (cid == null) return null;

    final result = await MlsService.instance.process(
      conversationId: cid,
      messageB64: row['ciphertext'] as String,
    );

    if (result is MlsApplicationMessage) {
      return result.plaintext;
    }
    return null;
  }
}
