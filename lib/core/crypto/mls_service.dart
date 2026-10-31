import 'dart:convert';

import 'package:criptivo/core/crypto/mls_secure_storage.dart';
import 'package:criptivo/src/rust/api.dart' as rust;

/// Високо ниво API над OpenMLS (през FRB).
///
/// Всички методи хвърлят [MlsServiceException] при status != ok.
class MlsService {
  MlsService._();
  static final MlsService instance = MlsService._();

  bool _identityLoaded = false;

  bool get isIdentityLoaded => _identityLoaded;

  // ---------------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------------

  /// Създава нова identity и я записва в secure storage.
  Future<MlsIdentityInfo> createIdentity(String userId) async {
    final raw = await rust.mlsCreateIdentity(identity: userId);
    final map = _decodeOk(raw);

    final state = map['protected_state_json'] as String;
    await MlsSecureStorage.saveIdentityState(state);
    _identityLoaded = true;

    return MlsIdentityInfo(
      identity: map['identity'] as String,
      signaturePublicKeyBase64: map['signature_public_key_base64'] as String,
    );
  }

  /// Зарежда identity от secure storage в Rust runtime.
  /// Извикай при старт на app (след login).
  Future<MlsIdentityInfo?> loadIdentityFromStorage() async {
    final state = await MlsSecureStorage.loadIdentityState();
    if (state == null || state.isEmpty) {
      _identityLoaded = false;
      return null;
    }

    final raw = await rust.mlsLoadIdentity(protectedStateJson: state);
    final map = _decodeOk(raw);
    _identityLoaded = true;

    return MlsIdentityInfo(
      identity: map['identity'] as String,
      signaturePublicKeyBase64: map['signature_public_key_base64'] as String,
    );
  }

  /// Генерира KeyPackages за качване в Supabase.
  /// След това **задължително** записва обновения identity state.
  Future<List<String>> generateKeyPackages({int count = 50}) async {
    _ensureIdentity();
    final raw = await rust.mlsGenerateKeyPackages(count: count);
    final map = _decodeOk(raw);

    final state = map['protected_state_json'] as String;
    await MlsSecureStorage.saveIdentityState(state);

    return (map['key_packages'] as List).cast<String>();
  }

  Future<String> publicKey() async {
    _ensureIdentity();
    final raw = await rust.mlsPublicKey();
    final map = _decodeOk(raw);
    return map['signature_public_key_base64'] as String;
  }

  // ---------------------------------------------------------------------------
  // 1:1 DM
  // ---------------------------------------------------------------------------

  /// Alice: създава DM група с Bob чрез неговия KeyPackage.
  /// Връща welcome (за изпращане на Bob) + commit.
  Future<MlsCreateDmResult> createDm({
    required String conversationId,
    required String theirKeyPackageB64,
  }) async {
    _ensureIdentity();
    final raw = await rust.mlsCreateDm(
      groupId: conversationId,
      theirKeyPackageB64: theirKeyPackageB64,
    );
    final map = _decodeOk(raw);

    final groupState = map['group_state_json'] as String;
    await MlsSecureStorage.saveGroupState(conversationId, groupState);

    return MlsCreateDmResult(
      groupId: map['group_id'] as String,
      commitB64: map['commit_b64'] as String,
      welcomeB64: map['welcome_b64'] as String,
    );
  }

  /// Bob: приема Welcome и влиза в групата.
  Future<MlsJoinDmResult> joinDm({
    required String conversationId,
    required String welcomeB64,
  }) async {
    _ensureIdentity();
    final raw = await rust.mlsJoinDm(
      groupId: conversationId,
      welcomeB64: welcomeB64,
    );
    final map = _decodeOk(raw);

    final groupState = map['group_state_json'] as String;
    await MlsSecureStorage.saveGroupState(conversationId, groupState);

    return MlsJoinDmResult(
      groupId: map['group_id'] as String,
      epoch: _asInt(map['epoch']),
    );
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  Future<MlsEncryptResult> encrypt({
    required String conversationId,
    required String plaintext,
  }) async {
    _ensureIdentity();
    final raw = await rust.mlsEncrypt(
      groupId: conversationId,
      plaintext: plaintext,
    );
    final map = _decodeOk(raw);

    final groupState = map['group_state_json'] as String;
    await MlsSecureStorage.saveGroupState(conversationId, groupState);

    return MlsEncryptResult(
      ciphertextB64: map['ciphertext_b64'] as String,
      epoch: _asInt(map['epoch']),
    );
  }

  Future<MlsProcessResult> process({
    required String conversationId,
    required String messageB64,
  }) async {
    _ensureIdentity();
    final raw = await rust.mlsProcess(
      groupId: conversationId,
      messageB64: messageB64,
    );
    final map = _decodeOk(raw);

    final groupState = map['group_state_json'] as String?;
    if (groupState != null) {
      await MlsSecureStorage.saveGroupState(conversationId, groupState);
    }

    final type = map['type'] as String;
    switch (type) {
      case 'application':
        return MlsProcessResult.application(
          plaintext: map['plaintext'] as String,
          epoch: _asInt(map['epoch']),
        );
      case 'commit':
        return MlsProcessResult.commit(epoch: _asInt(map['epoch']));
      case 'proposal':
        return MlsProcessResult.proposal();
      default:
        return MlsProcessResult.other(info: map['info']?.toString() ?? type);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _ensureIdentity() {
    if (!_identityLoaded) {
      throw MlsServiceException(
        'MLS identity not loaded. Call loadIdentityFromStorage() or createIdentity() first.',
      );
    }
  }

  Map<String, dynamic> _decodeOk(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    if (map['status'] != 'ok') {
      throw MlsServiceException(
        map['error']?.toString() ?? 'Unknown MLS error',
      );
    }
    return map;
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

// -----------------------------------------------------------------------------
// Result types
// -----------------------------------------------------------------------------

class MlsIdentityInfo {
  final String identity;
  final String signaturePublicKeyBase64;

  const MlsIdentityInfo({
    required this.identity,
    required this.signaturePublicKeyBase64,
  });
}

class MlsCreateDmResult {
  final String groupId;
  final String commitB64;
  final String welcomeB64;

  const MlsCreateDmResult({
    required this.groupId,
    required this.commitB64,
    required this.welcomeB64,
  });
}

class MlsJoinDmResult {
  final String groupId;
  final int epoch;

  const MlsJoinDmResult({required this.groupId, required this.epoch});
}

class MlsEncryptResult {
  final String ciphertextB64;
  final int epoch;

  const MlsEncryptResult({required this.ciphertextB64, required this.epoch});
}

sealed class MlsProcessResult {
  const MlsProcessResult();

  factory MlsProcessResult.application({
    required String plaintext,
    required int epoch,
  }) = MlsApplicationMessage;

  factory MlsProcessResult.commit({required int epoch}) = MlsCommitMessage;

  factory MlsProcessResult.proposal() = MlsProposalMessage;

  factory MlsProcessResult.other({required String info}) = MlsOtherMessage;
}

class MlsApplicationMessage extends MlsProcessResult {
  final String plaintext;
  final int epoch;
  const MlsApplicationMessage({required this.plaintext, required this.epoch});
}

class MlsCommitMessage extends MlsProcessResult {
  final int epoch;
  const MlsCommitMessage({required this.epoch});
}

class MlsProposalMessage extends MlsProcessResult {
  const MlsProposalMessage();
}

class MlsOtherMessage extends MlsProcessResult {
  final String info;
  const MlsOtherMessage({required this.info});
}

class MlsServiceException implements Exception {
  final String message;
  MlsServiceException(this.message);

  @override
  String toString() => 'MlsServiceException: $message';
}
