import 'dart:math' as math;

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

  bool get isStructurallyValid {
    return hintId.isNotEmpty &&
        groupId.isNotEmpty &&
        _isValidWorldId(worldId) &&
        _isValidInstanceId(instanceId) &&
        sourceClientId.isNotEmpty;
  }

  // Mirrors server-side validation in workers/relay_assist/src/index.js.
  static final _worldIdPattern = RegExp(
    r'^wrld_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static bool _isValidWorldId(String id) => _worldIdPattern.hasMatch(id);

  static bool _isValidInstanceId(String id) =>
      id.isNotEmpty && RegExp(r'^\d').hasMatch(id);

  /// Returns true if this hint has expired.
  ///
  /// A [grace] period (default 5 s) extends the validity window beyond
  /// [expiresAt] to tolerate minor NTP skew between publisher and consumer
  /// clocks. For example, a hint with [expiresAt] of 12:00:00 is still
  /// considered valid until 12:00:05 from the consumer's perspective.
  bool isExpired({DateTime? now, Duration grace = const Duration(seconds: 5)}) {
    final current = now ?? DateTime.now();
    return !expiresAt.isAfter(current.subtract(grace));
  }

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

class RelayConnectionStatus {
  final bool connected;
  final String? error;

  const RelayConnectionStatus({required this.connected, this.error});
}
