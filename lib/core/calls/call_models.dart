import 'package:flutter/foundation.dart';

enum CallKind { voice, video }

enum CallStatus {
  idle,
  outgoing,
  incoming,
  connecting,
  active,
  ending,
  ended,
}

enum CallEndReason {
  localHangup,
  remoteHangup,
  rejected,
  busy,
  timeout,
  failed,
  network,
}

enum CallSignalType {
  invite,
  accept,
  reject,
  hangup,
  offer,
  answer,
  ice,
  busy,
}

@immutable
class CallSignal {
  final CallSignalType type;
  final String callId;
  final String conversationId;
  final String fromUserId;
  final CallKind kind;
  final Map<String, dynamic>? sdp;
  final Map<String, dynamic>? candidate;
  final int ts;

  const CallSignal({
    required this.type,
    required this.callId,
    required this.conversationId,
    required this.fromUserId,
    required this.kind,
    this.sdp,
    this.candidate,
    required this.ts,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'call_id': callId,
        'conversation_id': conversationId,
        'from': fromUserId,
        'kind': kind.name,
        if (sdp != null) 'sdp': sdp,
        if (candidate != null) 'candidate': candidate,
        'ts': ts,
      };

  static CallSignal? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);

    CallSignalType? type;
    final t = map['type'] as String?;
    for (final e in CallSignalType.values) {
      if (e.name == t) {
        type = e;
        break;
      }
    }
    if (type == null) return null;

    final kindStr = map['kind'] as String? ?? 'voice';
    final kind = kindStr == 'video' ? CallKind.video : CallKind.voice;

    final callId = map['call_id'] as String?;
    final conversationId = map['conversation_id'] as String?;
    final from = map['from'] as String?;
    if (callId == null || conversationId == null || from == null) return null;

    return CallSignal(
      type: type,
      callId: callId,
      conversationId: conversationId,
      fromUserId: from,
      kind: kind,
      sdp: map['sdp'] is Map
          ? Map<String, dynamic>.from(map['sdp'] as Map)
          : null,
      candidate: map['candidate'] is Map
          ? Map<String, dynamic>.from(map['candidate'] as Map)
          : null,
      ts: (map['ts'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class ActiveCall {
  final String callId;
  final String conversationId;
  final String otherUserId;
  final String otherDisplayName;
  final String? otherAvatarUrl;
  final CallKind kind;
  final bool isOutgoing;
  final CallStatus status;
  final DateTime startedAt;
  final DateTime? connectedAt;
  final CallEndReason? endReason;

  const ActiveCall({
    required this.callId,
    required this.conversationId,
    required this.otherUserId,
    required this.otherDisplayName,
    this.otherAvatarUrl,
    required this.kind,
    required this.isOutgoing,
    required this.status,
    required this.startedAt,
    this.connectedAt,
    this.endReason,
  });

  ActiveCall copyWith({
    CallStatus? status,
    DateTime? connectedAt,
    CallEndReason? endReason,
  }) {
    return ActiveCall(
      callId: callId,
      conversationId: conversationId,
      otherUserId: otherUserId,
      otherDisplayName: otherDisplayName,
      otherAvatarUrl: otherAvatarUrl,
      kind: kind,
      isOutgoing: isOutgoing,
      status: status ?? this.status,
      startedAt: startedAt,
      connectedAt: connectedAt ?? this.connectedAt,
      endReason: endReason ?? this.endReason,
    );
  }

  Duration get elapsed {
    final from = connectedAt ?? startedAt;
    return DateTime.now().difference(from);
  }
}