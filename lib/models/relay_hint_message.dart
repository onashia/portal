import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';

class RelayHintMessage {
  final String version;
  final String hintId;
  final String groupId;
  final String worldId;
  final String instanceId;
  final int nUsers;
  final DateTime detectedAt;
  final DateTime expiresAt;
  final String sourceClientId;

  const RelayHintMessage({
    required this.version,
    required this.hintId,
    required this.groupId,
    required this.worldId,
    required this.instanceId,
    required this.nUsers,
    required this.detectedAt,
    required this.expiresAt,
    required this.sourceClientId,
  });

  /// Creates a new hint for the given [groupId], [worldId], and [instanceId].
  ///
  /// Sets [expiresAt] to [AppConstants.relayHintTtlSeconds] seconds from [now]
  /// (defaults to [DateTime.now]).
  factory RelayHintMessage.create({
    required String groupId,
    required String worldId,
    required String instanceId,
    required int nUsers,
    required String sourceClientId,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final expiresAt = timestamp.add(
      const Duration(seconds: AppConstants.relayHintTtlSeconds),
    );
    return RelayHintMessage(
      version: '1',
      hintId: _generateHintId(sourceClientId: sourceClientId, now: timestamp),
      groupId: groupId,
      worldId: worldId,
      instanceId: instanceId,
      nUsers: nUsers,
      detectedAt: timestamp,
      expiresAt: expiresAt,
      sourceClientId: sourceClientId,
    );
  }

  /// Deserializes a hint from the JSON map received over the relay WebSocket.
  factory RelayHintMessage.fromJson(Map<String, dynamic> json) {
    return RelayHintMessage(
      version: json['version']?.toString() ?? '1',
      hintId: json['hintId']?.toString() ?? '',
      groupId: json['groupId']?.toString() ?? '',
      worldId: json['worldId']?.toString() ?? '',
      instanceId: json['instanceId']?.toString() ?? '',
      nUsers: (json['nUsers'] as num?)?.toInt() ?? 0,
      detectedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['detectedAtMs'] as num?)?.toInt() ?? 0,
      ),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (json['expiresAtMs'] as num?)?.toInt() ?? 0,
      ),
      sourceClientId: json['sourceClientId']?.toString() ?? '',
    );
  }

  /// Serializes this hint to a JSON map for transmission over the relay
  /// WebSocket.
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'hintId': hintId,
      'groupId': groupId,
      'worldId': worldId,
      'instanceId': instanceId,
      'nUsers': nUsers,
      'detectedAtMs': detectedAt.millisecondsSinceEpoch,
      'expiresAtMs': expiresAt.millisecondsSinceEpoch,
      'sourceClientId': sourceClientId,
    };
  }

  /// Returns true if all ID fields pass format validation.
  ///
  /// Does not check expiry — use [isExpired] for that. Mirrors server-side
  /// validation in workers/relay_assist/src/index.js.
  bool get isStructurallyValid {
    return hintId.isNotEmpty &&
        hintId.length <= 256 &&
        _groupIdPattern.hasMatch(groupId) &&
        _isValidWorldId(worldId) &&
        _isValidInstanceId(instanceId) &&
        sourceClientId.isNotEmpty;
  }

  // Case-sensitive: VRChat group IDs are always lowercase hex. Intentionally
  // not setting caseSensitive: false — mirrors GROUP_ID_RE in the server
  // (workers/relay_assist/src/index.js) which also enforces lowercase only.
  static final _groupIdPattern = RegExp(
    r'^grp_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  // caseSensitive: false — the server accepts mixed case for world IDs and we
  // match that permissiveness to avoid false rejections on the client.
  // Intentionally asymmetric with _groupIdPattern, which is case-sensitive.
  static final _worldIdPattern = RegExp(
    r'^wrld_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static final _instanceIdPattern = RegExp(r'^\d');

  static bool _isValidWorldId(String id) => _worldIdPattern.hasMatch(id);

  static bool _isValidInstanceId(String id) =>
      id.isNotEmpty && _instanceIdPattern.hasMatch(id);

  /// Returns true if this hint has expired.
  ///
  /// A [grace] period (default 5 s) extends the validity window beyond
  /// [expiresAt] to tolerate minor NTP skew between publisher and consumer
  /// clocks. For example, a hint with [expiresAt] of 12:00:00 is still
  /// considered valid until 12:00:05 from the consumer's perspective.
  bool isExpired({DateTime? now, Duration grace = const Duration(seconds: 5)}) {
    final current = now ?? DateTime.now();
    // Equivalent to: current >= expiresAt + grace.
    // The hint is valid while expiresAt > current - grace, allowing [grace]
    // seconds of clock skew between publisher and consumer.
    return !expiresAt.isAfter(current.subtract(grace));
  }

  /// Composite key uniquely identifying the instance: `groupId|worldId|instanceId`.
  String get instanceKey => '$groupId|$worldId|$instanceId';

  static String _generateHintId({
    required String sourceClientId,
    required DateTime now,
  }) {
    final randomPart = _random.nextInt(1 << 32).toRadixString(16);
    final micros = now.microsecondsSinceEpoch.toRadixString(16);
    return '$sourceClientId-$micros-$randomPart';
  }

  static final math.Random _random = math.Random.secure();
}

@immutable
class RelayConnectionStatus {
  final bool connected;
  final String? error;

  const RelayConnectionStatus({required this.connected, this.error});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RelayConnectionStatus &&
          connected == other.connected &&
          error == other.error;

  @override
  int get hashCode => Object.hash(connected, error);
}
