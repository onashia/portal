import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/constants/app_constants.dart';
import 'package:portal/models/group_instance_with_group.dart';
import 'package:portal/models/relay_hint_message.dart';
import 'package:portal/providers/api_call_counter.dart';
import 'package:portal/providers/api_rate_limit_provider.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:portal/providers/group_monitor_api.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:portal/providers/group_monitor_storage.dart';
import 'package:portal/providers/polling_lifecycle.dart';
import 'package:portal/services/api_rate_limit_coordinator.dart';
import 'package:portal/services/invite_service.dart';
import 'package:portal/services/relay_hint_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vrchat_dart/vrchat_dart.dart' hide Response;

import 'test_helpers/auth_test_harness.dart';
import 'test_helpers/fake_group_monitor_api.dart';
import 'test_helpers/fake_vrchat_models.dart';

class _RelayHintServiceFake extends RelayHintService {
  _RelayHintServiceFake()
    : super(bootstrapUrl: 'https://example.com/bootstrap');

  final StreamController<RelayHintMessage> _hints =
      StreamController<RelayHintMessage>.broadcast();
  final StreamController<RelayConnectionStatus> _statuses =
      StreamController<RelayConnectionStatus>.broadcast();
  bool _isDisposed = false;
  final List<RelayHintMessage> publishedHints = <RelayHintMessage>[];

  /// Counts how many times [connect] has been called.
  int connectCallCount = 0;

  /// When non-null, overrides [runtimeDisabledUntil] so that tests can
  /// simulate the service's own cooldown value being read by
  /// [_reconcileRelayConnection].
  DateTime? runtimeDisabledUntilOverride;

  @override
  Stream<RelayHintMessage> get hints => _hints.stream;

  @override
  Stream<RelayConnectionStatus> get statuses => _statuses.stream;

  @override
  bool get isConfigured => true;

  @override
  DateTime? get runtimeDisabledUntil => runtimeDisabledUntilOverride;

  @override
  Future<void> connect({
    required String groupId,
    required String clientId,
  }) async {
    connectCallCount += 1;
    if (!_statuses.isClosed) {
      _statuses.add(const RelayConnectionStatus(connected: true));
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_statuses.isClosed) {
      _statuses.add(const RelayConnectionStatus(connected: false));
    }
  }

  @override
  Future<void> publishHint(RelayHintMessage hint) async {
    publishedHints.add(hint);
  }

  Future<void> emitHint(RelayHintMessage hint) async {
    if (!_hints.isClosed) {
      _hints.add(hint);
    }
  }

  Future<void> emitStatus(RelayConnectionStatus status) async {
    if (!_statuses.isClosed) {
      _statuses.add(status);
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _hints.close();
    await _statuses.close();
  }
}

class _CancelableInviteServiceFake implements InviteService {
  final Completer<void> started = Completer<void>();
  CancelToken? lastCancelToken;

  @override
  Future<InviteSendOutcome> inviteSelfToInstance(Instance instance) async {
    return InviteSendOutcome.sent;
  }

  @override
  Future<InviteSendOutcome> inviteSelfToLocation({
    required String worldId,
    required String instanceId,
  }) async {
    return InviteSendOutcome.sent;
  }

  @override
  Future<InviteRetryOutcome> inviteSelfToLocationWithRetry({
    required String worldId,
    required String instanceId,
    Duration maxWindow = const Duration(seconds: 25),
    CancelToken? cancelToken,
  }) async {
    lastCancelToken = cancelToken;
    if (!started.isCompleted) {
      started.complete();
    }
    if (cancelToken == null) {
      return InviteRetryOutcome.sent;
    }
    if (cancelToken.isCancelled) {
      return InviteRetryOutcome.cancelled;
    }
    await cancelToken.whenCancel;
    return InviteRetryOutcome.cancelled;
  }
}

class _ThrowingInviteServiceFake implements InviteService {
  @override
  Future<InviteSendOutcome> inviteSelfToInstance(Instance instance) async {
    return InviteSendOutcome.sent;
  }

  @override
  Future<InviteSendOutcome> inviteSelfToLocation({
    required String worldId,
    required String instanceId,
  }) async {
    return InviteSendOutcome.sent;
  }

  @override
  Future<InviteRetryOutcome> inviteSelfToLocationWithRetry({
    required String worldId,
    required String instanceId,
    Duration maxWindow = const Duration(seconds: 25),
    CancelToken? cancelToken,
  }) {
    throw StateError('unexpected invite failure');
  }
}

class _RecordingInviteServiceFake implements InviteService {
  final List<Instance> invitedInstances = <Instance>[];
  final Completer<void> started = Completer<void>();
  InviteSendOutcome inviteOutcome = InviteSendOutcome.sent;

  @override
  Future<InviteSendOutcome> inviteSelfToInstance(Instance instance) async {
    invitedInstances.add(instance);
    if (!started.isCompleted) {
      started.complete();
    }
    return inviteOutcome;
  }

  @override
  Future<InviteSendOutcome> inviteSelfToLocation({
    required String worldId,
    required String instanceId,
  }) async {
    return inviteOutcome;
  }

  @override
  Future<InviteRetryOutcome> inviteSelfToLocationWithRetry({
    required String worldId,
    required String instanceId,
    Duration maxWindow = const Duration(seconds: 25),
    CancelToken? cancelToken,
  }) async {
    return InviteRetryOutcome.sent;
  }
}

class _DelayedGroupMonitorApi extends FakeGroupMonitorApi {
  _DelayedGroupMonitorApi({
    super.groupInstancesByGroupId,
    super.enrichedInstancesByKey,
    required this.getInstanceDelay,
  });

  final Duration getInstanceDelay;

  @override
  Future<Response<Instance>> getInstance({
    required String worldId,
    required String instanceId,
    required ApiRequestLane lane,
  }) async {
    await Future<void>.delayed(getInstanceDelay);
    return super.getInstance(
      worldId: worldId,
      instanceId: instanceId,
      lane: lane,
    );
  }
}

({
  ProviderContainer container,
  TestAuthNotifier authNotifier,
  NotifierProvider<GroupMonitorNotifier, GroupMonitorState> provider,
  GroupMonitorNotifier notifier,
})
createGroupMonitorHarness({
  required AuthState initialAuthState,
  String userId = 'usr_test',
  GroupMonitorApi? groupMonitorApi,
  InviteService? inviteService,
  List<dynamic> overrides = const <dynamic>[],
}) {
  final monitorApi = groupMonitorApi ?? FakeGroupMonitorApi();
  final effectiveInviteService =
      inviteService ?? _CancelableInviteServiceFake();
  final authHarness = createAuthHarness(
    initialAuthState: initialAuthState,
    overrides: [
      groupMonitorApiProvider.overrideWithValue(monitorApi),
      inviteServiceProvider.overrideWithValue(effectiveInviteService),
      ...overrides,
    ],
  );
  final provider = groupMonitorProvider(userId);
  final notifier = authHarness.container.read(provider.notifier);
  return (
    container: authHarness.container,
    authNotifier: authHarness.authNotifier,
    provider: provider,
    notifier: notifier,
  );
}

Instance _buildMonitorInstance({
  required String instanceId,
  required World world,
  required int userCount,
  bool? hasCapacityForYou,
  int? capacity,
  bool queueEnabled = false,
  int queueSize = 0,
  GroupAccessType? groupAccessType,
}) {
  return Instance(
    capacity: capacity,
    clientNumber: 'unknown',
    groupAccessType: groupAccessType,
    hasCapacityForYou: hasCapacityForYou,
    id: 'inst_$instanceId',
    instanceId: instanceId,
    location: '${world.id}:$instanceId',
    nUsers: userCount,
    name: 'Instance $instanceId',
    photonRegion: Region.us,
    platforms: InstancePlatforms(android: 0, standalonewindows: userCount),
    queueEnabled: queueEnabled,
    queueSize: queueSize,
    recommendedCapacity: 16,
    region: InstanceRegion.us,
    secureName: 'secure-$instanceId',
    strict: false,
    tags: const [],
    type: InstanceType.group,
    userCount: userCount,
    world: world,
    worldId: world.id,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('resolveLoadedBoostSettings', () {
    test('keeps valid future boost settings', () {
      final now = DateTime.utc(2026, 2, 13, 10);
      final settings = GroupMonitorBoostSettings(
        groupId: 'grp_alpha',
        expiresAt: now.add(const Duration(minutes: 5)),
      );

      final result = resolveLoadedBoostSettings(settings: settings, now: now);

      expect(result.shouldClear, isFalse);
      expect(result.logExpired, isFalse);
      expect(result.boostedGroupId, 'grp_alpha');
      expect(result.boostExpiresAt, settings.expiresAt);
    });

    test('clears expired boost settings and marks as expired', () {
      final now = DateTime.utc(2026, 2, 13, 10);
      final settings = GroupMonitorBoostSettings(
        groupId: 'grp_alpha',
        expiresAt: now.subtract(const Duration(seconds: 1)),
      );

      final result = resolveLoadedBoostSettings(settings: settings, now: now);

      expect(result.shouldClear, isTrue);
      expect(result.logExpired, isTrue);
      expect(result.boostedGroupId, isNull);
      expect(result.boostExpiresAt, isNull);
    });

    test('clears partial persisted boost settings without expiry log', () {
      final now = DateTime.utc(2026, 2, 13, 10);

      final missingExpiry = resolveLoadedBoostSettings(
        settings: const GroupMonitorBoostSettings(groupId: 'grp_alpha'),
        now: now,
      );

      final missingGroupId = resolveLoadedBoostSettings(
        settings: GroupMonitorBoostSettings(expiresAt: now),
        now: now,
      );

      expect(missingExpiry.shouldClear, isTrue);
      expect(missingExpiry.logExpired, isFalse);
      expect(missingGroupId.shouldClear, isTrue);
      expect(missingGroupId.logExpired, isFalse);
    });
  });

  group('mergeFetchedGroupInstancesWithDiff', () {
    test(
      'reuses previous reference when payload is unchanged but reordered',
      () {
        final worldA = buildTestWorld(id: 'wrld_a', name: 'World A');
        final worldB = buildTestWorld(id: 'wrld_b', name: 'World B');
        final detectedAt = DateTime.utc(2026, 2, 13, 10, 0);

        final previousInstances = <GroupInstanceWithGroup>[
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_a',
              world: worldA,
              userCount: 3,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: DateTime.utc(2026, 2, 13, 8, 0),
          ),
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_b',
              world: worldB,
              userCount: 5,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: DateTime.utc(2026, 2, 13, 9, 0),
          ),
        ];

        final fetchedInstances = <Instance>[
          previousInstances[1].instance,
          previousInstances[0].instance,
        ];

        final merged = mergeFetchedGroupInstancesWithDiff(
          groupId: 'grp_alpha',
          fetchedInstances: fetchedInstances,
          previousInstances: previousInstances,
          detectedAt: detectedAt,
        );

        expect(merged.didChange, isFalse);
        expect(merged.newInstances, isEmpty);
        expect(identical(merged.effectiveInstances, previousInstances), isTrue);
      },
    );

    test(
      'marks add/remove changes and keeps only new entries in newInstances',
      () {
        final worldA = buildTestWorld(id: 'wrld_a', name: 'World A');
        final worldB = buildTestWorld(id: 'wrld_b', name: 'World B');
        final worldC = buildTestWorld(id: 'wrld_c', name: 'World C');
        final detectedAt = DateTime.utc(2026, 2, 13, 10, 0);
        final previousDetectedAt = DateTime.utc(2026, 2, 13, 9, 30);

        final previousInstances = <GroupInstanceWithGroup>[
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_a',
              world: worldA,
              userCount: 3,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: previousDetectedAt,
          ),
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_b',
              world: worldB,
              userCount: 4,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: previousDetectedAt,
          ),
        ];

        final fetchedInstances = <Instance>[
          buildTestInstance(instanceId: 'inst_a', world: worldA, userCount: 3),
          buildTestInstance(instanceId: 'inst_c', world: worldC, userCount: 8),
        ];

        final merged = mergeFetchedGroupInstancesWithDiff(
          groupId: 'grp_alpha',
          fetchedInstances: fetchedInstances,
          previousInstances: previousInstances,
          detectedAt: detectedAt,
        );

        expect(merged.didChange, isTrue);
        expect(
          identical(merged.effectiveInstances, previousInstances),
          isFalse,
        );
        expect(merged.newInstances, hasLength(1));
        expect(merged.newInstances.single.instance.instanceId, 'inst_c');
        expect(merged.newInstances.single.firstDetectedAt, detectedAt);

        final preserved = merged.effectiveInstances.firstWhere(
          (entry) => entry.instance.instanceId == 'inst_a',
        );
        expect(preserved.firstDetectedAt, previousDetectedAt);
      },
    );

    test('marks payload changes when existing instance fields differ', () {
      final world = buildTestWorld(id: 'wrld_a', name: 'World A');
      final detectedAt = DateTime.utc(2026, 2, 13, 10, 0);
      final previousDetectedAt = DateTime.utc(2026, 2, 13, 9, 0);

      final previousInstances = <GroupInstanceWithGroup>[
        GroupInstanceWithGroup(
          instance: buildTestInstance(
            instanceId: 'inst_a',
            world: world,
            userCount: 3,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: previousDetectedAt,
        ),
      ];

      final fetchedInstances = <Instance>[
        buildTestInstance(instanceId: 'inst_a', world: world, userCount: 9),
      ];

      final merged = mergeFetchedGroupInstancesWithDiff(
        groupId: 'grp_alpha',
        fetchedInstances: fetchedInstances,
        previousInstances: previousInstances,
        detectedAt: detectedAt,
      );

      expect(merged.didChange, isTrue);
      expect(merged.newInstances, isEmpty);
      expect(identical(merged.effectiveInstances, previousInstances), isFalse);
    });

    test('detects when previous instances are replaced by duplicates', () {
      final world = buildTestWorld(id: 'wrld_a', name: 'World A');
      final detectedAt = DateTime.utc(2026, 2, 13, 10, 0);
      final previousDetectedAt = DateTime.utc(2026, 2, 13, 9, 0);

      final previousInstances = <GroupInstanceWithGroup>[
        GroupInstanceWithGroup(
          instance: buildTestInstance(
            instanceId: 'inst_a',
            world: world,
            userCount: 5,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: previousDetectedAt,
        ),
        GroupInstanceWithGroup(
          instance: buildTestInstance(
            instanceId: 'inst_b',
            world: world,
            userCount: 3,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: previousDetectedAt,
        ),
      ];

      final fetchedInstances = <Instance>[
        buildTestInstance(instanceId: 'inst_a', world: world, userCount: 5),
        buildTestInstance(instanceId: 'inst_a', world: world, userCount: 5),
      ];

      final merged = mergeFetchedGroupInstancesWithDiff(
        groupId: 'grp_alpha',
        fetchedInstances: fetchedInstances,
        previousInstances: previousInstances,
        detectedAt: detectedAt,
      );

      expect(merged.didChange, isTrue);
      expect(merged.newInstances, isEmpty);
      expect(merged.effectiveInstances, hasLength(2));
      expect(merged.effectiveInstances[0].instance.instanceId, 'inst_a');
      expect(merged.effectiveInstances[1].instance.instanceId, 'inst_a');
      expect(merged.effectiveInstances[0].firstDetectedAt, previousDetectedAt);
      expect(merged.effectiveInstances[1].firstDetectedAt, previousDetectedAt);
    });

    test(
      'marks payload changes when only state-relevant enrichment fields differ',
      () {
        final world = buildTestWorld(id: 'wrld_a', name: 'World A');
        final detectedAt = DateTime.utc(2026, 2, 13, 10, 0);
        final previousDetectedAt = DateTime.utc(2026, 2, 13, 9, 0);

        final previousInstances = <GroupInstanceWithGroup>[
          GroupInstanceWithGroup(
            instance: _buildMonitorInstance(
              instanceId: 'inst_a',
              world: world,
              userCount: 3,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: previousDetectedAt,
          ),
        ];

        final fetchedInstances = <Instance>[
          _buildMonitorInstance(
            instanceId: 'inst_a',
            world: world,
            userCount: 3,
            hasCapacityForYou: false,
          ),
        ];

        final merged = mergeFetchedGroupInstancesWithDiff(
          groupId: 'grp_alpha',
          fetchedInstances: fetchedInstances,
          previousInstances: previousInstances,
          detectedAt: detectedAt,
        );

        expect(merged.didChange, isTrue);
        expect(merged.newInstances, isEmpty);
        expect(
          merged.effectiveInstances.single.instance.hasCapacityForYou,
          false,
        );
      },
    );

    test('marks payload changes when queue metadata differs', () {
      final world = buildTestWorld(id: 'wrld_a', name: 'World A');
      final detectedAt = DateTime.utc(2026, 2, 13, 10, 0);
      final previousDetectedAt = DateTime.utc(2026, 2, 13, 9, 0);

      final previousInstances = <GroupInstanceWithGroup>[
        GroupInstanceWithGroup(
          instance: _buildMonitorInstance(
            instanceId: 'inst_a',
            world: world,
            userCount: 3,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: previousDetectedAt,
        ),
      ];

      final fetchedInstances = <Instance>[
        _buildMonitorInstance(
          instanceId: 'inst_a',
          world: world,
          userCount: 3,
          queueEnabled: true,
          queueSize: 4,
        ),
      ];

      final merged = mergeFetchedGroupInstancesWithDiff(
        groupId: 'grp_alpha',
        fetchedInstances: fetchedInstances,
        previousInstances: previousInstances,
        detectedAt: detectedAt,
      );

      expect(merged.didChange, isTrue);
      expect(merged.newInstances, isEmpty);
      expect(merged.effectiveInstances.single.instance.queueEnabled, isTrue);
      expect(merged.effectiveInstances.single.instance.queueSize, 4);
    });

    test('marks payload changes when capacity differs', () {
      final world = buildTestWorld(id: 'wrld_a', name: 'World A');
      final detectedAt = DateTime.utc(2026, 2, 13, 10, 0);
      final previousDetectedAt = DateTime.utc(2026, 2, 13, 9, 0);

      final previousInstances = <GroupInstanceWithGroup>[
        GroupInstanceWithGroup(
          instance: _buildMonitorInstance(
            instanceId: 'inst_a',
            world: world,
            userCount: 3,
            capacity: 16,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: previousDetectedAt,
        ),
      ];

      final fetchedInstances = <Instance>[
        _buildMonitorInstance(
          instanceId: 'inst_a',
          world: world,
          userCount: 3,
          capacity: 24,
        ),
      ];

      final merged = mergeFetchedGroupInstancesWithDiff(
        groupId: 'grp_alpha',
        fetchedInstances: fetchedInstances,
        previousInstances: previousInstances,
        detectedAt: detectedAt,
      );

      expect(merged.didChange, isTrue);
      expect(merged.newInstances, isEmpty);
      expect(merged.effectiveInstances.single.instance.capacity, 24);
    });
  });

  group('areGroupInstanceListsEquivalent', () {
    test('returns true for equivalent lists even if order differs', () {
      final worldA = buildTestWorld(id: 'wrld_a', name: 'World A');
      final worldB = buildTestWorld(id: 'wrld_b', name: 'World B');
      final detectedAt = DateTime.utc(2026, 2, 13, 9, 0);

      final previous = [
        GroupInstanceWithGroup(
          instance: buildTestInstance(
            instanceId: 'inst_a',
            world: worldA,
            userCount: 3,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: detectedAt,
        ),
        GroupInstanceWithGroup(
          instance: buildTestInstance(
            instanceId: 'inst_b',
            world: worldB,
            userCount: 4,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: detectedAt,
        ),
      ];
      final next = [previous[1], previous[0]];

      expect(areGroupInstanceListsEquivalent(previous, next), isTrue);
    });

    test('returns false when nUsers changes', () {
      final world = buildTestWorld(id: 'wrld_a', name: 'World A');
      final detectedAt = DateTime.utc(2026, 2, 13, 9, 0);

      final previous = [
        GroupInstanceWithGroup(
          instance: buildTestInstance(
            instanceId: 'inst_a',
            world: world,
            userCount: 3,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: detectedAt,
        ),
      ];
      final next = [
        GroupInstanceWithGroup(
          instance: buildTestInstance(
            instanceId: 'inst_a',
            world: world,
            userCount: 5,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: detectedAt,
        ),
      ];

      expect(areGroupInstanceListsEquivalent(previous, next), isFalse);
    });

    test('returns false when world name changes', () {
      final worldBefore = buildTestWorld(id: 'wrld_a', name: 'World A');
      final worldAfter = buildTestWorld(id: 'wrld_a', name: 'World A Prime');
      final detectedAt = DateTime.utc(2026, 2, 13, 9, 0);

      final previous = [
        GroupInstanceWithGroup(
          instance: buildTestInstance(
            instanceId: 'inst_a',
            world: worldBefore,
            userCount: 3,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: detectedAt,
        ),
      ];
      final next = [
        GroupInstanceWithGroup(
          instance: buildTestInstance(
            instanceId: 'inst_a',
            world: worldAfter,
            userCount: 3,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: detectedAt,
        ),
      ];

      expect(areGroupInstanceListsEquivalent(previous, next), isFalse);
    });

    test(
      'returns false when next contains duplicates replacing previous items',
      () {
        final world = buildTestWorld(id: 'wrld_a', name: 'World A');
        final detectedAt = DateTime.utc(2026, 2, 13, 9, 0);

        final previous = [
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_a',
              world: world,
              userCount: 3,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: detectedAt,
          ),
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_b',
              world: world,
              userCount: 4,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: detectedAt,
          ),
        ];

        final next = [previous[0], previous[0]];

        expect(areGroupInstanceListsEquivalent(previous, next), isFalse);
      },
    );
  });

  group('group instance change tracking', () {
    test('treats key-set mismatch as changed', () {
      final world = buildTestWorld(id: 'wrld_1', name: 'World One');
      final detectedAt = DateTime.utc(2026, 2, 13, 9, 0);
      final groupInstances = <String, List<GroupInstanceWithGroup>>{
        'grp_alpha': [
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_alpha',
              world: world,
              userCount: 3,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: detectedAt,
          ),
        ],
      };

      expect(
        hasGroupInstanceKeyMismatch(
          selectedGroupIds: {'grp_alpha', 'grp_beta'},
          groupInstances: groupInstances,
        ),
        isTrue,
      );
      expect(
        hasGroupInstanceKeyMismatch(
          selectedGroupIds: {'grp_alpha'},
          groupInstances: {...groupInstances, 'grp_beta': []},
        ),
        isTrue,
      );
    });

    test(
      'reuses previous map reference when keys and payloads are unchanged',
      () {
        final world = buildTestWorld(id: 'wrld_1', name: 'World One');
        final detectedAt = DateTime.utc(2026, 2, 13, 9, 0);
        final previousAlpha = <GroupInstanceWithGroup>[
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_alpha',
              world: world,
              userCount: 3,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: detectedAt,
          ),
        ];
        final previousBeta = <GroupInstanceWithGroup>[
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_beta',
              world: world,
              userCount: 4,
            ),
            groupId: 'grp_beta',
            firstDetectedAt: detectedAt,
          ),
        ];
        final previousGroupInstances = <String, List<GroupInstanceWithGroup>>{
          'grp_alpha': previousAlpha,
          'grp_beta': previousBeta,
        };

        var didInstancesChange = hasGroupInstanceKeyMismatch(
          selectedGroupIds: {'grp_alpha', 'grp_beta'},
          groupInstances: previousGroupInstances,
        );
        final mergedAlpha = [previousAlpha.first];
        final alphaDidChange = !areGroupInstanceListsEquivalent(
          previousAlpha,
          mergedAlpha,
        );
        final resolvedAlpha = alphaDidChange ? mergedAlpha : previousAlpha;
        final mergedBeta = [previousBeta.first];
        final betaDidChange = !areGroupInstanceListsEquivalent(
          previousBeta,
          mergedBeta,
        );
        final resolvedBeta = betaDidChange ? mergedBeta : previousBeta;
        didInstancesChange =
            didInstancesChange || alphaDidChange || betaDidChange;

        final nextGroupInstances = <String, List<GroupInstanceWithGroup>>{
          'grp_alpha': resolvedAlpha,
          'grp_beta': resolvedBeta,
        };
        final selectedGroupInstances = didInstancesChange
            ? nextGroupInstances
            : previousGroupInstances;

        expect(didInstancesChange, isFalse);
        expect(identical(resolvedAlpha, previousAlpha), isTrue);
        expect(identical(resolvedBeta, previousBeta), isTrue);
        expect(
          identical(selectedGroupInstances, previousGroupInstances),
          isTrue,
        );
      },
    );

    test(
      'updates changed group while preserving unchanged group list references',
      () {
        final world = buildTestWorld(id: 'wrld_1', name: 'World One');
        final detectedAt = DateTime.utc(2026, 2, 13, 9, 0);
        final previousAlpha = <GroupInstanceWithGroup>[
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_alpha',
              world: world,
              userCount: 3,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: detectedAt,
          ),
        ];
        final previousBeta = <GroupInstanceWithGroup>[
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_beta',
              world: world,
              userCount: 4,
            ),
            groupId: 'grp_beta',
            firstDetectedAt: detectedAt,
          ),
        ];
        final previousGroupInstances = <String, List<GroupInstanceWithGroup>>{
          'grp_alpha': previousAlpha,
          'grp_beta': previousBeta,
        };

        var didInstancesChange = hasGroupInstanceKeyMismatch(
          selectedGroupIds: {'grp_alpha', 'grp_beta'},
          groupInstances: previousGroupInstances,
        );
        final mergedAlpha = <GroupInstanceWithGroup>[
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_alpha',
              world: world,
              userCount: 8,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: detectedAt,
          ),
        ];
        final alphaDidChange = !areGroupInstanceListsEquivalent(
          previousAlpha,
          mergedAlpha,
        );
        final resolvedAlpha = alphaDidChange ? mergedAlpha : previousAlpha;
        final mergedBeta = [previousBeta.first];
        final betaDidChange = !areGroupInstanceListsEquivalent(
          previousBeta,
          mergedBeta,
        );
        final resolvedBeta = betaDidChange ? mergedBeta : previousBeta;
        didInstancesChange =
            didInstancesChange || alphaDidChange || betaDidChange;

        final nextGroupInstances = <String, List<GroupInstanceWithGroup>>{
          'grp_alpha': resolvedAlpha,
          'grp_beta': resolvedBeta,
        };
        final selectedGroupInstances = didInstancesChange
            ? nextGroupInstances
            : previousGroupInstances;

        expect(didInstancesChange, isTrue);
        expect(
          identical(selectedGroupInstances, previousGroupInstances),
          isFalse,
        );
        expect(
          identical(selectedGroupInstances['grp_alpha'], previousAlpha),
          isFalse,
        );
        expect(
          identical(selectedGroupInstances['grp_beta'], previousBeta),
          isTrue,
        );
      },
    );
  });

  group('newestInstanceIdFromGroupInstances', () {
    test(
      'returns newest across groups and remains correct after group replacement',
      () {
        final world = buildTestWorld(id: 'wrld_1', name: 'World One');

        final initial = {
          'grp_alpha': [
            GroupInstanceWithGroup(
              instance: buildTestInstance(
                instanceId: 'inst_alpha_old',
                world: world,
                userCount: 4,
              ),
              groupId: 'grp_alpha',
              firstDetectedAt: DateTime.utc(2026, 2, 13, 8, 0),
            ),
          ],
          'grp_beta': [
            GroupInstanceWithGroup(
              instance: buildTestInstance(
                instanceId: 'inst_beta_new',
                world: world,
                userCount: 7,
              ),
              groupId: 'grp_beta',
              firstDetectedAt: DateTime.utc(2026, 2, 13, 9, 0),
            ),
          ],
        };

        expect(newestInstanceIdFromGroupInstances(initial), 'inst_beta_new');

        final boostedUpdate = {
          ...initial,
          'grp_alpha': [
            GroupInstanceWithGroup(
              instance: buildTestInstance(
                instanceId: 'inst_alpha_boosted',
                world: world,
                userCount: 10,
              ),
              groupId: 'grp_alpha',
              firstDetectedAt: DateTime.utc(2026, 2, 13, 10, 0),
            ),
          ],
        };

        expect(
          newestInstanceIdFromGroupInstances(boostedUpdate),
          'inst_alpha_boosted',
        );
      },
    );

    test(
      'remains correct with unchanged groups and one changed group payload',
      () {
        final world = buildTestWorld(id: 'wrld_1', name: 'World One');

        final previous = {
          'grp_alpha': [
            GroupInstanceWithGroup(
              instance: buildTestInstance(
                instanceId: 'inst_alpha',
                world: world,
                userCount: 4,
              ),
              groupId: 'grp_alpha',
              firstDetectedAt: DateTime.utc(2026, 2, 13, 8, 0),
            ),
          ],
          'grp_beta': [
            GroupInstanceWithGroup(
              instance: buildTestInstance(
                instanceId: 'inst_beta',
                world: world,
                userCount: 6,
              ),
              groupId: 'grp_beta',
              firstDetectedAt: DateTime.utc(2026, 2, 13, 9, 0),
            ),
          ],
        };

        final next = {
          'grp_alpha': previous['grp_alpha']!,
          'grp_beta': [
            GroupInstanceWithGroup(
              instance: buildTestInstance(
                instanceId: 'inst_beta_new',
                world: world,
                userCount: 7,
              ),
              groupId: 'grp_beta',
              firstDetectedAt: DateTime.utc(2026, 2, 13, 10, 0),
            ),
          ],
        };

        expect(newestInstanceIdFromGroupInstances(previous), 'inst_beta');
        expect(newestInstanceIdFromGroupInstances(next), 'inst_beta_new');
      },
    );
  });

  group('fetchGroupInstancesChunked', () {
    test('limits concurrency and preserves ordered results', () async {
      const orderedGroupIds = [
        'grp_alpha',
        'grp_beta',
        'grp_gamma',
        'grp_delta',
      ];
      final releaseByGroup = {
        for (final groupId in orderedGroupIds) groupId: Completer<void>(),
      };
      final started = <String>[];
      var activeRequests = 0;
      var peakConcurrentRequests = 0;

      final resultFuture = fetchGroupInstancesChunked(
        orderedGroupIds: orderedGroupIds,
        maxConcurrentRequests: 2,
        fetchGroupInstances: (groupId) async {
          started.add(groupId);
          activeRequests += 1;
          if (activeRequests > peakConcurrentRequests) {
            peakConcurrentRequests = activeRequests;
          }

          await releaseByGroup[groupId]!.future;
          activeRequests -= 1;
          return null;
        },
      );

      await pumpEventQueue();
      expect(started, equals(['grp_alpha', 'grp_beta']));

      releaseByGroup['grp_alpha']!.complete();
      releaseByGroup['grp_beta']!.complete();
      await pumpEventQueue();
      expect(
        started,
        equals(['grp_alpha', 'grp_beta', 'grp_gamma', 'grp_delta']),
      );

      releaseByGroup['grp_gamma']!.complete();
      releaseByGroup['grp_delta']!.complete();
      final results = await resultFuture;

      expect(peakConcurrentRequests, lessThanOrEqualTo(2));
      expect(
        results.map((entry) => entry.groupId).toList(growable: false),
        equals(orderedGroupIds),
      );
    });

    test('throws when maxConcurrentRequests is less than 1', () async {
      expect(
        () => fetchGroupInstancesChunked(
          orderedGroupIds: const ['grp_alpha'],
          maxConcurrentRequests: 0,
          fetchGroupInstances: (_) async => null,
        ),
        throwsArgumentError,
      );
    });
  });

  group('shouldAttemptSelfInviteForInstance', () {
    Instance buildInstance({
      required String worldId,
      required String instanceId,
      required bool? canRequestInvite,
    }) {
      final world = buildTestWorld(
        id: worldId.isEmpty ? 'wrld_fallback' : worldId,
        name: 'World',
      );
      return Instance(
        canRequestInvite: canRequestInvite,
        clientNumber: 'unknown',
        id: 'inst_${instanceId.isEmpty ? 'fallback' : instanceId}',
        instanceId: instanceId,
        location: '$worldId:$instanceId',
        nUsers: 5,
        name: 'Instance $instanceId',
        photonRegion: Region.us,
        platforms: InstancePlatforms(android: 0, standalonewindows: 5),
        queueEnabled: false,
        queueSize: 0,
        recommendedCapacity: 16,
        region: InstanceRegion.us,
        secureName: 'secure-${instanceId.isEmpty ? 'fallback' : instanceId}',
        strict: false,
        tags: const [],
        type: InstanceType.group,
        userCount: 5,
        world: world,
        worldId: worldId,
      );
    }

    test('returns true when canRequestInvite is explicitly false', () {
      final instance = buildInstance(
        worldId: 'wrld_alpha',
        instanceId: 'inst_alpha',
        canRequestInvite: false,
      );

      expect(shouldAttemptSelfInviteForInstance(instance), isTrue);
    });

    test('returns true when canRequestInvite is true', () {
      final instance = buildInstance(
        worldId: 'wrld_alpha',
        instanceId: 'inst_alpha',
        canRequestInvite: true,
      );

      expect(shouldAttemptSelfInviteForInstance(instance), isTrue);
    });

    test('returns true when canRequestInvite is null', () {
      final instance = buildInstance(
        worldId: 'wrld_alpha',
        instanceId: 'inst_alpha',
        canRequestInvite: null,
      );

      expect(shouldAttemptSelfInviteForInstance(instance), isTrue);
    });

    test('returns false when worldId or instanceId is invalid', () {
      final missingWorld = buildInstance(
        worldId: '',
        instanceId: 'inst_alpha',
        canRequestInvite: true,
      );
      final missingInstance = buildInstance(
        worldId: 'wrld_alpha',
        instanceId: '',
        canRequestInvite: true,
      );

      expect(shouldAttemptSelfInviteForInstance(missingWorld), isFalse);
      expect(shouldAttemptSelfInviteForInstance(missingInstance), isFalse);
    });
  });

  group('isSelfInviteUnavailableForCapacity', () {
    Instance buildInstance({
      bool? hasCapacityForYou,
      bool queueEnabled = false,
      int queueSize = 0,
    }) {
      final world = buildTestWorld(id: 'wrld_alpha', name: 'World');
      return Instance(
        clientNumber: 'unknown',
        hasCapacityForYou: hasCapacityForYou,
        id: 'inst_alpha',
        instanceId: 'inst_alpha',
        location: '${world.id}:inst_alpha',
        nUsers: 5,
        name: 'Instance inst_alpha',
        photonRegion: Region.us,
        platforms: InstancePlatforms(android: 0, standalonewindows: 5),
        queueEnabled: queueEnabled,
        queueSize: queueSize,
        recommendedCapacity: 16,
        region: InstanceRegion.us,
        secureName: 'secure-inst_alpha',
        strict: false,
        tags: const [],
        type: InstanceType.group,
        userCount: 5,
        world: world,
        worldId: world.id,
      );
    }

    test('returns false when only queueEnabled is true', () {
      final instance = buildInstance(
        hasCapacityForYou: true,
        queueEnabled: true,
        queueSize: 0,
      );

      expect(isSelfInviteUnavailableForCapacity(instance), isFalse);
    });

    test('returns true when queue has entries', () {
      final instance = buildInstance(
        hasCapacityForYou: true,
        queueEnabled: true,
        queueSize: 2,
      );

      expect(isSelfInviteUnavailableForCapacity(instance), isTrue);
    });

    test('returns true when hasCapacityForYou is false', () {
      final instance = buildInstance(
        hasCapacityForYou: false,
        queueEnabled: false,
        queueSize: 0,
      );

      expect(isSelfInviteUnavailableForCapacity(instance), isTrue);
    });
  });

  group('pending refresh decisions', () {
    test('queues pending refresh only when active and in-flight', () {
      final queueWhenActive = shouldRequestImmediateRefresh(
        isActive: true,
        isInFlight: true,
        immediate: true,
      );
      expect(queueWhenActive.shouldQueuePending, isTrue);

      final noQueueWhenIdle = shouldRequestImmediateRefresh(
        isActive: true,
        isInFlight: false,
        immediate: true,
      );
      expect(noQueueWhenIdle.shouldQueuePending, isFalse);

      final noQueueWhenInactive = shouldRequestImmediateRefresh(
        isActive: false,
        isInFlight: true,
        immediate: true,
      );
      expect(noQueueWhenInactive.shouldQueuePending, isFalse);
    });

    test('drains only when pending and not currently fetching', () {
      final drainsWhenEligible = shouldDrainPendingRefresh(
        isMounted: true,
        isInFlight: false,
        hasPendingRefresh: true,
        isActive: true,
      );
      expect(drainsWhenEligible, isTrue);

      expect(
        shouldDrainPendingRefresh(
          isMounted: true,
          isInFlight: true,
          hasPendingRefresh: true,
          isActive: true,
        ),
        isFalse,
      );
      expect(
        shouldDrainPendingRefresh(
          isMounted: true,
          isInFlight: false,
          hasPendingRefresh: true,
          isActive: false,
        ),
        isFalse,
      );
      expect(
        shouldDrainPendingRefresh(
          isMounted: true,
          isInFlight: false,
          hasPendingRefresh: false,
          isActive: true,
        ),
        isFalse,
      );
      expect(
        shouldDrainPendingRefresh(
          isMounted: false,
          isInFlight: false,
          hasPendingRefresh: true,
          isActive: true,
        ),
        isFalse,
      );
    });
  });

  group('auth session polling guards', () {
    test('isSessionEligible requires auth and matching user id', () {
      expect(
        isSessionEligible(
          isAuthenticated: true,
          authenticatedUserId: 'usr_test',
          expectedUserId: 'usr_test',
        ),
        isTrue,
      );
      expect(
        isSessionEligible(
          isAuthenticated: false,
          authenticatedUserId: 'usr_test',
          expectedUserId: 'usr_test',
        ),
        isFalse,
      );
      expect(
        isSessionEligible(
          isAuthenticated: true,
          authenticatedUserId: 'usr_other',
          expectedUserId: 'usr_test',
        ),
        isFalse,
      );
    });

    test(
      'stops monitoring when auth transitions away from authenticated',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final authNotifier = harness.authNotifier;
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        notifier.state = const GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
          isMonitoring: true,
        );

        authNotifier.setData(unauthenticatedAuthState());
        await Future<void>.delayed(Duration.zero);

        expect(container.read(provider).isMonitoring, isFalse);
      },
    );

    test(
      'fetchGroupInstances is skipped when authenticated user id mismatches',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_other'),
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        notifier.state = const GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
          isMonitoring: true,
        );

        await notifier.fetchGroupInstances();

        expect(container.read(apiCallCounterProvider).totalCalls, 0);
      },
    );

    test(
      'timer-driven fetch remains guarded when auth user changes after scheduling',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final authNotifier = harness.authNotifier;
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        notifier.state = const GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
        );
        notifier.startMonitoring();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final callsBeforeAuthChange = container
            .read(apiCallCounterProvider)
            .totalCalls;

        authNotifier.setData(authenticatedAuthState(userId: 'usr_other'));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          container.read(apiCallCounterProvider).totalCalls,
          callsBeforeAuthChange,
        );
        expect(container.read(provider).isMonitoring, isFalse);
      },
    );

    test(
      'auth transition does not start monitoring with empty selection',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: unauthenticatedAuthState(),
        );
        final authNotifier = harness.authNotifier;
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        notifier.state = const GroupMonitorState(selectedGroupIds: <String>{});
        authNotifier.setData(authenticatedAuthState(userId: 'usr_test'));
        expect(container.read(provider).isMonitoring, isFalse);
      },
    );

    test(
      'auth transition starts monitoring when selected groups exist',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: unauthenticatedAuthState(),
        );
        final authNotifier = harness.authNotifier;
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        notifier.state = const GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
        );
        authNotifier.setData(authenticatedAuthState(userId: 'usr_test'));
        await Future<void>.delayed(Duration.zero);
        expect(container.read(provider).isMonitoring, isTrue);
        notifier.stopMonitoring();
      },
    );

    test(
      'toggleGroupSelection starts monitoring when first group is selected',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        notifier.state = const GroupMonitorState();

        notifier.toggleGroupSelection('grp_alpha');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final currentState = container.read(provider);
        expect(currentState.selectedGroupIds, contains('grp_alpha'));
        expect(currentState.isMonitoring, isTrue);
      },
    );

    test(
      'toggleGroupSelection restarts monitoring after deselect/reselect',
      () {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        notifier.state = const GroupMonitorState();

        notifier.toggleGroupSelection('grp_alpha');
        expect(container.read(provider).isMonitoring, isTrue);

        notifier.toggleGroupSelection('grp_alpha');
        expect(container.read(provider).isMonitoring, isFalse);
        expect(container.read(provider).selectedGroupIds, isEmpty);

        notifier.toggleGroupSelection('grp_alpha');
        expect(container.read(provider).isMonitoring, isTrue);
      },
    );

    test(
      'toggleGroupSelection debounces refresh when adding a group while already monitoring',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        notifier.state = const GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
          isMonitoring: true,
        );
        notifier.requestRefresh(immediate: false);

        final callsBefore = container.read(apiCallCounterProvider).totalCalls;

        notifier.toggleGroupSelection('grp_beta');
        await Future<void>.delayed(const Duration(milliseconds: 700));

        expect(container.read(provider).selectedGroupIds, contains('grp_beta'));
        expect(
          container.read(apiCallCounterProvider).totalCalls,
          greaterThan(callsBefore),
        );
      },
    );

    test(
      'toggleGroupSelection does not immediately refresh on removal while still monitoring',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        notifier.state = const GroupMonitorState(
          selectedGroupIds: {'grp_alpha', 'grp_beta'},
          isMonitoring: true,
        );
        notifier.requestRefresh(immediate: false);

        final callsBefore = container.read(apiCallCounterProvider).totalCalls;

        notifier.toggleGroupSelection('grp_beta');
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          container.read(provider).selectedGroupIds,
          isNot(contains('grp_beta')),
        );
        expect(container.read(provider).isMonitoring, isTrue);
        expect(container.read(apiCallCounterProvider).totalCalls, callsBefore);
      },
    );

    test(
      'toggleGroupSelection does not start monitoring for ineligible session',
      () {
        final harness = createGroupMonitorHarness(
          initialAuthState: unauthenticatedAuthState(),
        );
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        notifier.state = const GroupMonitorState();

        notifier.toggleGroupSelection('grp_alpha');

        final currentState = container.read(provider);
        expect(currentState.selectedGroupIds, contains('grp_alpha'));
        expect(currentState.isMonitoring, isFalse);
      },
    );
  });

  group('baseline polling timer invariant', () {
    test(
      'creates a baseline polling timer when refresh is requested non-immediately',
      () {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        notifier.state = const GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
          isMonitoring: true,
        );
        expect(notifier.hasActivePollingTimer, isFalse);

        notifier.requestRefresh(immediate: false);

        expect(notifier.hasActivePollingTimer, isTrue);
      },
    );

    test('forces monitoring off when active monitoring becomes ineligible', () {
      final harness = createGroupMonitorHarness(
        initialAuthState: unauthenticatedAuthState(),
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);
      notifier.state = const GroupMonitorState(
        selectedGroupIds: {'grp_alpha'},
        isMonitoring: true,
      );

      notifier.toggleGroupSelection('grp_beta');

      expect(container.read(provider).isMonitoring, isFalse);
      expect(notifier.hasActivePollingTimer, isFalse);
    });
  });

  group('rate limit and boost baseline behaviors', () {
    test(
      'baseline polling excludes boosted group to avoid duplicate calls',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        notifier.state = GroupMonitorState(
          selectedGroupIds: const {'grp_alpha'},
          isMonitoring: true,
          isBoostActive: true,
          boostedGroupId: 'grp_alpha',
          boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );

        await notifier.fetchGroupInstances();
        notifier.stopMonitoring();

        expect(container.read(apiCallCounterProvider).totalCalls, 0);
      },
    );

    test('clearing boost triggers baseline recovery refresh', () async {
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
      );
      final container = harness.container;
      final notifier = harness.notifier;
      addTearDown(container.dispose);
      notifier.state = GroupMonitorState(
        selectedGroupIds: const {'grp_alpha'},
        autoInviteEnabled: false,
        isMonitoring: true,
        isBoostActive: true,
        boostedGroupId: 'grp_alpha',
        boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );

      await notifier.clearBoost();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(container.read(apiCallCounterProvider).totalCalls, greaterThan(0));
    });

    test('automatic baseline poll is deferred during cooldown', () async {
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);

      container
          .read(apiRateLimitCoordinatorProvider)
          .recordRateLimited(
            ApiRequestLane.groupBaseline,
            retryAfter: const Duration(seconds: 60),
          );

      notifier.state = const GroupMonitorState(
        selectedGroupIds: {'grp_alpha'},
        isMonitoring: true,
      );

      await notifier.fetchGroupInstances();

      expect(container.read(apiCallCounterProvider).totalCalls, 0);
      expect(container.read(apiCallCounterProvider).throttledSkips, 1);
      expect(container.read(provider).groupErrors, isEmpty);
    });

    test('automatic boost poll is deferred during cooldown', () async {
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);

      container
          .read(apiRateLimitCoordinatorProvider)
          .recordRateLimited(
            ApiRequestLane.groupBoost,
            retryAfter: const Duration(seconds: 60),
          );

      notifier.state = GroupMonitorState(
        selectedGroupIds: const {'grp_alpha'},
        autoInviteEnabled: false,
        isMonitoring: true,
        isBoostActive: true,
        boostedGroupId: 'grp_alpha',
        boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );

      await notifier.fetchBoostedGroupInstances();

      expect(container.read(apiCallCounterProvider).totalCalls, 0);
      expect(container.read(apiCallCounterProvider).throttledSkips, 1);
      expect(container.read(provider).groupErrors, isEmpty);
    });

    test('expired boost is cleared before cooldown defers the poll', () async {
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);

      container
          .read(apiRateLimitCoordinatorProvider)
          .recordRateLimited(
            ApiRequestLane.groupBoost,
            retryAfter: const Duration(seconds: 60),
          );

      notifier.state = GroupMonitorState(
        selectedGroupIds: const {'grp_alpha'},
        autoInviteEnabled: false,
        isMonitoring: true,
        isBoostActive: true,
        boostedGroupId: 'grp_alpha',
        boostExpiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );

      await notifier.fetchBoostedGroupInstances();

      final nextState = container.read(provider);
      expect(nextState.isBoostActive, isFalse);
      expect(nextState.boostedGroupId, isNull);
      expect(nextState.boostExpiresAt, isNull);
      expect(container.read(apiCallCounterProvider).totalCalls, 0);
    });

    test(
      'deselected boost is cleared before cooldown defers the poll',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        container
            .read(apiRateLimitCoordinatorProvider)
            .recordRateLimited(
              ApiRequestLane.groupBoost,
              retryAfter: const Duration(seconds: 60),
            );

        notifier.state = GroupMonitorState(
          selectedGroupIds: const {'grp_beta'},
          autoInviteEnabled: false,
          isMonitoring: true,
          isBoostActive: true,
          boostedGroupId: 'grp_alpha',
          boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );

        await notifier.fetchBoostedGroupInstances();

        final nextState = container.read(provider);
        expect(nextState.isBoostActive, isFalse);
        expect(nextState.boostedGroupId, isNull);
        expect(nextState.boostExpiresAt, isNull);
        expect(container.read(apiCallCounterProvider).totalCalls, 0);
      },
    );

    test('manual refresh bypasses baseline cooldown', () async {
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
      );
      final container = harness.container;
      final notifier = harness.notifier;
      addTearDown(container.dispose);

      container
          .read(apiRateLimitCoordinatorProvider)
          .recordRateLimited(
            ApiRequestLane.groupBaseline,
            retryAfter: const Duration(seconds: 60),
          );

      notifier.state = const GroupMonitorState(
        selectedGroupIds: {'grp_alpha'},
        isMonitoring: true,
      );

      notifier.requestRefresh(immediate: true);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(container.read(apiCallCounterProvider).totalCalls, greaterThan(0));
    });

    test(
      'queued manual refresh preserves bypass intent during cooldown',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        container
            .read(apiRateLimitCoordinatorProvider)
            .recordRateLimited(
              ApiRequestLane.groupBaseline,
              retryAfter: const Duration(seconds: 60),
            );

        notifier.state = const GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
          isMonitoring: true,
        );

        unawaited(notifier.fetchGroupInstances(bypassRateLimit: true));
        notifier.requestRefresh(immediate: true);
        await Future<void>.delayed(const Duration(milliseconds: 120));

        final baselineCalls =
            container
                .read(apiCallCounterProvider)
                .callsByLane['groupBaseline'] ??
            0;
        expect(baselineCalls, greaterThanOrEqualTo(2));
      },
    );

    test('records baseline diagnostics for cooldown skip', () async {
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);

      container
          .read(apiRateLimitCoordinatorProvider)
          .recordRateLimited(
            ApiRequestLane.groupBaseline,
            retryAfter: const Duration(seconds: 60),
          );

      notifier.state = const GroupMonitorState(
        selectedGroupIds: {'grp_alpha'},
        isMonitoring: true,
      );

      await notifier.fetchGroupInstances();

      final state = container.read(provider);
      expect(state.lastBaselineAttemptAt, isNotNull);
      expect(state.lastBaselineSuccessAt, isNull);
      expect(state.lastBaselineSkipReason, 'cooldown');
    });

    test('records baseline diagnostics for completed cycle', () async {
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);
      notifier.state = const GroupMonitorState(
        selectedGroupIds: {'grp_alpha'},
        isMonitoring: true,
      );

      await notifier.fetchGroupInstances(bypassRateLimit: true);

      final state = container.read(provider);
      expect(state.lastBaselineAttemptAt, isNotNull);
      expect(state.lastBaselineSuccessAt, isNotNull);
      expect(state.lastBaselinePolledGroupCount, 1);
      expect(state.lastBaselineTotalInstances, isNotNull);
      expect(state.lastBaselineSkipReason, isNull);
    });

    test('startMonitoring records a baseline attempt', () async {
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);
      notifier.state = const GroupMonitorState(selectedGroupIds: {'grp_alpha'});

      notifier.startMonitoring();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(container.read(provider).lastBaselineAttemptAt, isNotNull);
    });
  });

  group('instance enrichment caching', () {
    test(
      'reuses enrichment cache across boosted polls for same instance',
      () async {
        final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
        final groupInstance = buildTestGroupInstance(
          instanceId: '12345~group(grp_alpha)~region(us)',
          location: 'wrld_alpha:12345~group(grp_alpha)~region(us)',
          world: world,
          memberCount: 3,
        );
        final key = '${world.id}|${groupInstance.instanceId}';
        final fakeApi = FakeGroupMonitorApi(
          groupInstancesByGroupId: {
            'grp_alpha': [groupInstance],
          },
          enrichedInstancesByKey: {
            key: buildTestInstance(
              instanceId: groupInstance.instanceId,
              world: world,
              userCount: 3,
            ),
          },
        );
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          groupMonitorApi: fakeApi,
          inviteService: _CancelableInviteServiceFake(),
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        notifier.state = GroupMonitorState(
          selectedGroupIds: const {'grp_alpha'},
          autoInviteEnabled: false,
          isMonitoring: true,
          isBoostActive: true,
          boostedGroupId: 'grp_alpha',
          boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );

        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);
        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);

        expect(fakeApi.getInstanceCallCountByKey[key], 1);
      },
    );

    test('prunes enrichment cache once an instance disappears', () async {
      final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
      final groupInstance = buildTestGroupInstance(
        instanceId: '12345~group(grp_alpha)~region(us)',
        location: 'wrld_alpha:12345~group(grp_alpha)~region(us)',
        world: world,
        memberCount: 2,
      );
      final key = '${world.id}|${groupInstance.instanceId}';
      final fakeApi = FakeGroupMonitorApi(
        groupInstancesByGroupId: {
          'grp_alpha': [groupInstance],
        },
        enrichedInstancesByKey: {
          key: buildTestInstance(
            instanceId: groupInstance.instanceId,
            world: world,
            userCount: 2,
          ),
        },
      );
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        groupMonitorApi: fakeApi,
        inviteService: _CancelableInviteServiceFake(),
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);

      notifier.state = GroupMonitorState(
        selectedGroupIds: const {'grp_alpha'},
        autoInviteEnabled: false,
        isMonitoring: true,
        isBoostActive: true,
        boostedGroupId: 'grp_alpha',
        boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );

      await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);
      fakeApi.groupInstancesByGroupId['grp_alpha'] = const <GroupInstance>[];
      await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);
      expect(container.read(provider).groupInstances['grp_alpha'], isEmpty);

      fakeApi.groupInstancesByGroupId['grp_alpha'] = [groupInstance];
      await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);

      expect(fakeApi.getInstanceCallCountByKey[key], 2);
    });

    test(
      'enrichment failure cooldown preserves discovery instance without retrying immediately',
      () async {
        final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
        final groupInstance = buildTestGroupInstance(
          instanceId: '12345~group(grp_alpha)~region(us)',
          location: 'wrld_alpha:12345~group(grp_alpha)~region(us)',
          world: world,
          memberCount: 1,
        );
        final key = '${world.id}|${groupInstance.instanceId}';
        final fakeApi = FakeGroupMonitorApi(
          groupInstancesByGroupId: {
            'grp_alpha': [groupInstance],
          },
          instanceErrorsByKey: {
            key: DioException(
              requestOptions: RequestOptions(
                path: '/instances/${world.id}:${groupInstance.instanceId}',
              ),
              response: Response<void>(
                requestOptions: RequestOptions(
                  path: '/instances/${world.id}:${groupInstance.instanceId}',
                ),
                statusCode: 429,
              ),
              type: DioExceptionType.badResponse,
            ),
          },
        );
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          groupMonitorApi: fakeApi,
          inviteService: _CancelableInviteServiceFake(),
        );
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        notifier.state = GroupMonitorState(
          selectedGroupIds: const {'grp_alpha'},
          autoInviteEnabled: false,
          isMonitoring: true,
          isBoostActive: true,
          boostedGroupId: 'grp_alpha',
          boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );

        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);
        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);

        expect(fakeApi.getInstanceCallCountByKey[key], 1);
        expect(
          container.read(provider).groupInstances['grp_alpha'],
          hasLength(1),
        );
      },
    );

    test(
      'persists enrichment metadata for an existing instance when identity and population are unchanged',
      () async {
        final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
        final groupInstance = buildTestGroupInstance(
          instanceId: '12345~group(grp_alpha)~region(us)',
          location: 'wrld_alpha:12345~group(grp_alpha)~region(us)',
          world: world,
          memberCount: 2,
        );
        final key = '${world.id}|${groupInstance.instanceId}';
        final fakeApi = FakeGroupMonitorApi(
          groupInstancesByGroupId: {
            'grp_alpha': [groupInstance],
          },
          enrichedInstancesByKey: {
            key: _buildMonitorInstance(
              instanceId: groupInstance.instanceId,
              world: world,
              userCount: 2,
              hasCapacityForYou: false,
              queueEnabled: true,
              queueSize: 3,
              capacity: 24,
            ),
          },
        );
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          groupMonitorApi: fakeApi,
          inviteService: _CancelableInviteServiceFake(),
        );
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        notifier.state = GroupMonitorState(
          selectedGroupIds: const {'grp_alpha'},
          autoInviteEnabled: false,
          isMonitoring: true,
          isBoostActive: true,
          boostedGroupId: 'grp_alpha',
          boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
          groupInstances: {
            'grp_alpha': [
              GroupInstanceWithGroup(
                instance: _buildMonitorInstance(
                  instanceId: groupInstance.instanceId,
                  world: world,
                  userCount: 2,
                  capacity: world.capacity,
                ),
                groupId: 'grp_alpha',
                firstDetectedAt: DateTime.utc(2026, 2, 13, 9, 0),
              ),
            ],
          },
        );

        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);

        final stored = container
            .read(provider)
            .groupInstances['grp_alpha']!
            .single
            .instance;
        expect(stored.hasCapacityForYou, isFalse);
        expect(stored.queueEnabled, isTrue);
        expect(stored.queueSize, 3);
        expect(stored.capacity, 24);
      },
    );
  });

  group('auto-invite state guard', () {
    test(
      'does not send auto-invite for baseline discovery when no boost is active',
      () async {
        final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
        final groupInstance = buildTestGroupInstance(
          instanceId: '12345~group(grp_alpha)~region(us)',
          location: 'wrld_alpha:12345~group(grp_alpha)~region(us)',
          world: world,
          memberCount: 2,
        );
        final key = '${world.id}|${groupInstance.instanceId}';
        final fakeApi = FakeGroupMonitorApi(
          groupInstancesByGroupId: {'grp_alpha': const <GroupInstance>[]},
          enrichedInstancesByKey: {
            key: _buildMonitorInstance(
              instanceId: groupInstance.instanceId,
              world: world,
              userCount: 2,
              hasCapacityForYou: true,
            ),
          },
        );
        final inviteService = _RecordingInviteServiceFake();
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          groupMonitorApi: fakeApi,
          inviteService: inviteService,
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        notifier.state = GroupMonitorState(
          selectedGroupIds: const {'grp_alpha'},
          autoInviteEnabled: true,
          isMonitoring: true,
          groupInstances: const {'grp_alpha': <GroupInstanceWithGroup>[]},
        );

        await notifier.fetchGroupInstances(bypassRateLimit: true);
        fakeApi.groupInstancesByGroupId['grp_alpha'] = [groupInstance];

        await notifier.fetchGroupInstances(bypassRateLimit: true);

        expect(inviteService.invitedInstances, isEmpty);
      },
    );

    test(
      'does not send auto-invite for baseline discovery in a non-boosted selected group',
      () async {
        final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
        final boostedGroupInstance = buildTestGroupInstance(
          instanceId: 'boosted~group(grp_alpha)~region(us)',
          location: 'wrld_alpha:boosted~group(grp_alpha)~region(us)',
          world: world,
          memberCount: 3,
        );
        final baselineOnlyGroupInstance = buildTestGroupInstance(
          instanceId: 'baseline~group(grp_beta)~region(us)',
          location: 'wrld_alpha:baseline~group(grp_beta)~region(us)',
          world: world,
          memberCount: 2,
        );
        final fakeApi = FakeGroupMonitorApi(
          groupInstancesByGroupId: {
            'grp_alpha': [boostedGroupInstance],
            'grp_beta': const <GroupInstance>[],
          },
          enrichedInstancesByKey: {
            '${world.id}|${boostedGroupInstance.instanceId}':
                _buildMonitorInstance(
                  instanceId: boostedGroupInstance.instanceId,
                  world: world,
                  userCount: 3,
                  hasCapacityForYou: true,
                ),
            '${world.id}|${baselineOnlyGroupInstance.instanceId}':
                _buildMonitorInstance(
                  instanceId: baselineOnlyGroupInstance.instanceId,
                  world: world,
                  userCount: 2,
                  hasCapacityForYou: true,
                ),
          },
        );
        final inviteService = _RecordingInviteServiceFake();
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          groupMonitorApi: fakeApi,
          inviteService: inviteService,
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        notifier.state = GroupMonitorState(
          selectedGroupIds: const {'grp_alpha', 'grp_beta'},
          autoInviteEnabled: true,
          isMonitoring: true,
          isBoostActive: true,
          boostedGroupId: 'grp_alpha',
          boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
          groupInstances: {
            'grp_alpha': [
              GroupInstanceWithGroup(
                instance: _buildMonitorInstance(
                  instanceId: boostedGroupInstance.instanceId,
                  world: world,
                  userCount: 3,
                  hasCapacityForYou: true,
                ),
                groupId: 'grp_alpha',
                firstDetectedAt: DateTime.utc(2026, 2, 13, 9, 0),
              ),
            ],
            'grp_beta': const <GroupInstanceWithGroup>[],
          },
        );

        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);
        fakeApi.groupInstancesByGroupId['grp_beta'] = [
          baselineOnlyGroupInstance,
        ];

        await notifier.fetchGroupInstances(bypassRateLimit: true);

        expect(inviteService.invitedInstances, isEmpty);
      },
    );

    test(
      'does not send auto-invite when auto-invite is disabled during verification',
      () async {
        final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
        final groupInstance = buildTestGroupInstance(
          instanceId: '12345~group(grp_alpha)~region(us)',
          location: 'wrld_alpha:12345~group(grp_alpha)~region(us)',
          world: world,
          memberCount: 2,
        );
        final key = '${world.id}|${groupInstance.instanceId}';
        final fakeApi = _DelayedGroupMonitorApi(
          getInstanceDelay: const Duration(milliseconds: 50),
          groupInstancesByGroupId: {'grp_alpha': const <GroupInstance>[]},
          enrichedInstancesByKey: {
            key: _buildMonitorInstance(
              instanceId: groupInstance.instanceId,
              world: world,
              userCount: 2,
              hasCapacityForYou: true,
            ),
          },
        );
        final inviteService = _RecordingInviteServiceFake();
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          groupMonitorApi: fakeApi,
          inviteService: inviteService,
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        notifier.state = GroupMonitorState(
          selectedGroupIds: const {'grp_alpha'},
          autoInviteEnabled: true,
          isMonitoring: true,
          isBoostActive: true,
          boostedGroupId: 'grp_alpha',
          boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );

        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);
        fakeApi.groupInstancesByGroupId['grp_alpha'] = [groupInstance];

        final pendingFetch = notifier.fetchBoostedGroupInstances(
          bypassRateLimit: true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        notifier.state = notifier.state.copyWith(autoInviteEnabled: false);
        await pendingFetch;

        expect(inviteService.invitedInstances, isEmpty);
      },
    );

    test(
      'does not send auto-invite when monitoring stops during verification',
      () async {
        final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
        final groupInstance = buildTestGroupInstance(
          instanceId: '12345~group(grp_alpha)~region(us)',
          location: 'wrld_alpha:12345~group(grp_alpha)~region(us)',
          world: world,
          memberCount: 2,
        );
        final key = '${world.id}|${groupInstance.instanceId}';
        final fakeApi = _DelayedGroupMonitorApi(
          getInstanceDelay: const Duration(milliseconds: 50),
          groupInstancesByGroupId: {'grp_alpha': const <GroupInstance>[]},
          enrichedInstancesByKey: {
            key: _buildMonitorInstance(
              instanceId: groupInstance.instanceId,
              world: world,
              userCount: 2,
              hasCapacityForYou: true,
            ),
          },
        );
        final inviteService = _RecordingInviteServiceFake();
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          groupMonitorApi: fakeApi,
          inviteService: inviteService,
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        notifier.state = GroupMonitorState(
          selectedGroupIds: const {'grp_alpha'},
          autoInviteEnabled: true,
          isMonitoring: true,
          isBoostActive: true,
          boostedGroupId: 'grp_alpha',
          boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );

        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);
        fakeApi.groupInstancesByGroupId['grp_alpha'] = [groupInstance];

        final pendingFetch = notifier.fetchBoostedGroupInstances(
          bypassRateLimit: true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        notifier.state = notifier.state.copyWith(isMonitoring: false);
        await pendingFetch;

        expect(inviteService.invitedInstances, isEmpty);
      },
    );

    test(
      'sends auto-invite when state is still enabled after verification',
      () async {
        final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
        final groupInstance = buildTestGroupInstance(
          instanceId: '12345~group(grp_alpha)~region(us)',
          location: 'wrld_alpha:12345~group(grp_alpha)~region(us)',
          world: world,
          memberCount: 2,
        );
        final key = '${world.id}|${groupInstance.instanceId}';
        final fakeApi = _DelayedGroupMonitorApi(
          getInstanceDelay: const Duration(milliseconds: 20),
          groupInstancesByGroupId: {'grp_alpha': const <GroupInstance>[]},
          enrichedInstancesByKey: {
            key: _buildMonitorInstance(
              instanceId: groupInstance.instanceId,
              world: world,
              userCount: 2,
              hasCapacityForYou: true,
            ),
          },
        );
        final inviteService = _RecordingInviteServiceFake();
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          groupMonitorApi: fakeApi,
          inviteService: inviteService,
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        notifier.state = GroupMonitorState(
          selectedGroupIds: const {'grp_alpha'},
          autoInviteEnabled: true,
          isMonitoring: true,
          isBoostActive: true,
          boostedGroupId: 'grp_alpha',
          boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );

        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);
        fakeApi.groupInstancesByGroupId['grp_alpha'] = [groupInstance];

        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);

        expect(inviteService.invitedInstances, hasLength(1));
        expect(
          inviteService.invitedInstances.single.instanceId,
          groupInstance.instanceId,
        );
      },
    );

    test(
      'sends auto-invite when queue is enabled but empty after verification',
      () async {
        final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
        final groupInstance = buildTestGroupInstance(
          instanceId: '12345~group(grp_alpha)~region(use)',
          location: 'wrld_alpha:12345~group(grp_alpha)~region(use)',
          world: world,
          memberCount: 1,
        );
        final key = '${world.id}|${groupInstance.instanceId}';
        final fakeApi = FakeGroupMonitorApi(
          groupInstancesByGroupId: {'grp_alpha': const <GroupInstance>[]},
          enrichedInstancesByKey: {
            key: _buildMonitorInstance(
              instanceId: groupInstance.instanceId,
              world: world,
              userCount: 1,
              hasCapacityForYou: true,
              queueEnabled: true,
              queueSize: 0,
            ),
          },
        );
        final inviteService = _RecordingInviteServiceFake();
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          groupMonitorApi: fakeApi,
          inviteService: inviteService,
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        notifier.state = GroupMonitorState(
          selectedGroupIds: const {'grp_alpha'},
          autoInviteEnabled: true,
          isMonitoring: true,
          isBoostActive: true,
          boostedGroupId: 'grp_alpha',
          boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );

        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);
        fakeApi.groupInstancesByGroupId['grp_alpha'] = [groupInstance];

        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);

        expect(inviteService.invitedInstances, hasLength(1));
        expect(
          inviteService.invitedInstances.single.instanceId,
          groupInstance.instanceId,
        );
      },
    );

    test(
      'does not send auto-invite when all verified candidates are unavailable',
      () async {
        final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
        final groupInstanceA = buildTestGroupInstance(
          instanceId: '12345~group(grp_alpha)~region(us)',
          location: 'wrld_alpha:12345~group(grp_alpha)~region(us)',
          world: world,
          memberCount: 3,
        );
        final groupInstanceB = buildTestGroupInstance(
          instanceId: '67890~group(grp_alpha)~region(us)',
          location: 'wrld_alpha:67890~group(grp_alpha)~region(us)',
          world: world,
          memberCount: 2,
        );
        final fakeApi = FakeGroupMonitorApi(
          groupInstancesByGroupId: {'grp_alpha': const <GroupInstance>[]},
          enrichedInstancesByKey: {
            '${world.id}|${groupInstanceA.instanceId}': _buildMonitorInstance(
              instanceId: groupInstanceA.instanceId,
              world: world,
              userCount: 3,
              hasCapacityForYou: false,
            ),
            '${world.id}|${groupInstanceB.instanceId}': _buildMonitorInstance(
              instanceId: groupInstanceB.instanceId,
              world: world,
              userCount: 2,
              hasCapacityForYou: true,
              queueEnabled: true,
              queueSize: 2,
            ),
          },
        );
        final inviteService = _RecordingInviteServiceFake();
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          groupMonitorApi: fakeApi,
          inviteService: inviteService,
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        notifier.state = GroupMonitorState(
          selectedGroupIds: const {'grp_alpha'},
          autoInviteEnabled: true,
          isMonitoring: true,
          isBoostActive: true,
          boostedGroupId: 'grp_alpha',
          boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );

        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);
        fakeApi.groupInstancesByGroupId['grp_alpha'] = [
          groupInstanceA,
          groupInstanceB,
        ];

        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);

        expect(inviteService.invitedInstances, isEmpty);
      },
    );

    test(
      'baseline fetch preserves boosted-group unavailable metadata before later auto-invite',
      () async {
        final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
        final cachedGroupInstance = buildTestGroupInstance(
          instanceId: 'cached~group(grp_alpha)~region(us)',
          location: 'wrld_alpha:cached~group(grp_alpha)~region(us)',
          world: world,
          memberCount: 4,
        );
        final groupInstanceA = buildTestGroupInstance(
          instanceId: 'a~group(grp_alpha)~region(us)',
          location: 'wrld_alpha:a~group(grp_alpha)~region(us)',
          world: world,
          memberCount: 7,
        );
        final groupInstanceB = buildTestGroupInstance(
          instanceId: 'b~group(grp_alpha)~region(us)',
          location: 'wrld_alpha:b~group(grp_alpha)~region(us)',
          world: world,
          memberCount: 6,
        );
        final groupInstanceC = buildTestGroupInstance(
          instanceId: 'c~group(grp_alpha)~region(us)',
          location: 'wrld_alpha:c~group(grp_alpha)~region(us)',
          world: world,
          memberCount: 5,
        );
        final baselineOnlyGroupInstance = buildTestGroupInstance(
          instanceId: 'baseline~group(grp_beta)~region(us)',
          location: 'wrld_alpha:baseline~group(grp_beta)~region(us)',
          world: world,
          memberCount: 1,
        );
        final fakeApi = FakeGroupMonitorApi(
          groupInstancesByGroupId: {
            'grp_alpha': [cachedGroupInstance],
            'grp_beta': [baselineOnlyGroupInstance],
          },
          enrichedInstancesByKey: {
            '${world.id}|${cachedGroupInstance.instanceId}':
                _buildMonitorInstance(
                  instanceId: cachedGroupInstance.instanceId,
                  world: world,
                  userCount: 4,
                  hasCapacityForYou: false,
                ),
            '${world.id}|${groupInstanceA.instanceId}': _buildMonitorInstance(
              instanceId: groupInstanceA.instanceId,
              world: world,
              userCount: 7,
              hasCapacityForYou: false,
            ),
            '${world.id}|${groupInstanceB.instanceId}': _buildMonitorInstance(
              instanceId: groupInstanceB.instanceId,
              world: world,
              userCount: 6,
              hasCapacityForYou: true,
              queueEnabled: true,
              queueSize: 2,
            ),
            '${world.id}|${groupInstanceC.instanceId}': _buildMonitorInstance(
              instanceId: groupInstanceC.instanceId,
              world: world,
              userCount: 5,
              hasCapacityForYou: false,
            ),
            '${world.id}|${baselineOnlyGroupInstance.instanceId}':
                _buildMonitorInstance(
                  instanceId: baselineOnlyGroupInstance.instanceId,
                  world: world,
                  userCount: 1,
                  hasCapacityForYou: true,
                ),
          },
        );
        final inviteService = _RecordingInviteServiceFake();
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          groupMonitorApi: fakeApi,
          inviteService: inviteService,
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        notifier.state = GroupMonitorState(
          selectedGroupIds: const {'grp_alpha', 'grp_beta'},
          autoInviteEnabled: false,
          isMonitoring: true,
          isBoostActive: true,
          boostedGroupId: 'grp_alpha',
          boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
          groupInstances: {
            'grp_beta': [
              GroupInstanceWithGroup(
                instance: _buildMonitorInstance(
                  instanceId: baselineOnlyGroupInstance.instanceId,
                  world: world,
                  userCount: 1,
                  hasCapacityForYou: true,
                ),
                groupId: 'grp_beta',
                firstDetectedAt: DateTime.utc(2026, 2, 13, 9, 0),
              ),
            ],
          },
        );

        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);
        await notifier.fetchGroupInstances(bypassRateLimit: true);

        notifier.state = notifier.state.copyWith(
          autoInviteEnabled: true,
          groupInstances: {
            'grp_alpha': const <GroupInstanceWithGroup>[],
            'grp_beta': notifier.state.groupInstances['grp_beta'] ?? const [],
          },
          newestInstanceId: null,
        );
        fakeApi.groupInstancesByGroupId['grp_alpha'] = [
          groupInstanceA,
          groupInstanceB,
          groupInstanceC,
          cachedGroupInstance,
        ];

        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);

        expect(inviteService.invitedInstances, isEmpty);
        expect(
          fakeApi
              .getInstanceCallCountByKey['${world.id}|${cachedGroupInstance.instanceId}'],
          1,
        );
      },
    );

    test(
      'sends auto-invite for unresolved top candidate when verification fails',
      () async {
        final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
        final groupInstanceA = buildTestGroupInstance(
          instanceId: '12345~group(grp_alpha)~region(us)',
          location: 'wrld_alpha:12345~group(grp_alpha)~region(us)',
          world: world,
          memberCount: 3,
        );
        final groupInstanceB = buildTestGroupInstance(
          instanceId: '67890~group(grp_alpha)~region(us)',
          location: 'wrld_alpha:67890~group(grp_alpha)~region(us)',
          world: world,
          memberCount: 2,
        );
        final fakeApi = FakeGroupMonitorApi(
          groupInstancesByGroupId: {'grp_alpha': const <GroupInstance>[]},
          enrichedInstancesByKey: {
            '${world.id}|${groupInstanceB.instanceId}': _buildMonitorInstance(
              instanceId: groupInstanceB.instanceId,
              world: world,
              userCount: 2,
              hasCapacityForYou: true,
            ),
          },
          instanceErrorsByKey: {
            '${world.id}|${groupInstanceA.instanceId}': DioException(
              requestOptions: RequestOptions(
                path: '/instances/${world.id}:${groupInstanceA.instanceId}',
              ),
              response: Response<void>(
                requestOptions: RequestOptions(
                  path: '/instances/${world.id}:${groupInstanceA.instanceId}',
                ),
                statusCode: 429,
              ),
              type: DioExceptionType.badResponse,
            ),
          },
        );
        final inviteService = _RecordingInviteServiceFake();
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          groupMonitorApi: fakeApi,
          inviteService: inviteService,
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        notifier.state = GroupMonitorState(
          selectedGroupIds: const {'grp_alpha'},
          autoInviteEnabled: true,
          isMonitoring: true,
          isBoostActive: true,
          boostedGroupId: 'grp_alpha',
          boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );

        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);
        fakeApi.groupInstancesByGroupId['grp_alpha'] = [
          groupInstanceA,
          groupInstanceB,
        ];

        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);

        expect(inviteService.invitedInstances, hasLength(1));
        expect(
          inviteService.invitedInstances.single.instanceId,
          groupInstanceA.instanceId,
        );
      },
    );

    test(
      'publishes relay hint for the same resolved target used by auto-invite',
      () async {
        final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
        final relayService = _RelayHintServiceFake();
        final groupInstanceA = buildTestGroupInstance(
          instanceId: '12345~group(grp_alpha)~region(us)',
          location: 'wrld_alpha:12345~group(grp_alpha)~region(us)',
          world: world,
          memberCount: 3,
        );
        final groupInstanceB = buildTestGroupInstance(
          instanceId: '67890~group(grp_alpha)~region(us)',
          location: 'wrld_alpha:67890~group(grp_alpha)~region(us)',
          world: world,
          memberCount: 2,
        );
        final fakeApi = FakeGroupMonitorApi(
          groupInstancesByGroupId: {'grp_alpha': const <GroupInstance>[]},
          enrichedInstancesByKey: {
            '${world.id}|${groupInstanceA.instanceId}': _buildMonitorInstance(
              instanceId: groupInstanceA.instanceId,
              world: world,
              userCount: 3,
              hasCapacityForYou: false,
            ),
            '${world.id}|${groupInstanceB.instanceId}': _buildMonitorInstance(
              instanceId: groupInstanceB.instanceId,
              world: world,
              userCount: 2,
              hasCapacityForYou: true,
            ),
          },
        );
        final inviteService = _RecordingInviteServiceFake();
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          groupMonitorApi: fakeApi,
          inviteService: inviteService,
          overrides: [relayHintServiceProvider.overrideWithValue(relayService)],
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        notifier.state = GroupMonitorState(
          selectedGroupIds: const {'grp_alpha'},
          autoInviteEnabled: true,
          isMonitoring: true,
          isBoostActive: true,
          boostedGroupId: 'grp_alpha',
          boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
          relayAssistEnabled: true,
          relayConnected: true,
        );

        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);
        fakeApi.groupInstancesByGroupId['grp_alpha'] = [
          groupInstanceA,
          groupInstanceB,
        ];

        await notifier.fetchBoostedGroupInstances(bypassRateLimit: true);

        expect(inviteService.invitedInstances, hasLength(1));
        expect(
          inviteService.invitedInstances.single.instanceId,
          groupInstanceB.instanceId,
        );
        expect(relayService.publishedHints, hasLength(1));
        expect(
          relayService.publishedHints.single.instanceId,
          groupInstanceB.instanceId,
        );
      },
    );
  });

  group('relay hint lifecycle cancellation', () {
    test('cancels in-flight relay invite work on notifier dispose', () async {
      final relayService = _RelayHintServiceFake();
      final inviteService = _CancelableInviteServiceFake();
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        inviteService: inviteService,
        overrides: [relayHintServiceProvider.overrideWithValue(relayService)],
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;

      final observedRelayErrors = <String?>[];
      final subscription = container.listen<GroupMonitorState>(
        provider,
        (_, next) => observedRelayErrors.add(next.lastRelayError),
        fireImmediately: true,
      );

      notifier.state = GroupMonitorState(
        isMonitoring: true,
        autoInviteEnabled: true,
        isBoostActive: true,
        boostedGroupId: 'grp_11111111-1111-1111-1111-111111111111',
        boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );

      final hint = RelayHintMessage.create(
        groupId: 'grp_11111111-1111-1111-1111-111111111111',
        worldId: 'wrld_12345678-1234-1234-1234-123456789abc',
        instanceId: '12345~alpha',
        nUsers: 9,
        sourceClientId: 'relay_peer',
      );
      await relayService.emitHint(hint);
      await inviteService.started.future;

      final tokenBeforeDispose = inviteService.lastCancelToken;
      expect(tokenBeforeDispose, isNotNull);
      expect(tokenBeforeDispose!.isCancelled, isFalse);

      container.dispose();
      await Future<void>.delayed(Duration.zero);
      subscription.close();

      expect(tokenBeforeDispose.isCancelled, isTrue);
      expect(observedRelayErrors.whereType<String>(), isEmpty);
    });

    test('records relay failure for unexpected invite exceptions', () async {
      final relayService = _RelayHintServiceFake();
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        inviteService: _ThrowingInviteServiceFake(),
        overrides: [relayHintServiceProvider.overrideWithValue(relayService)],
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);
      final observedRelayErrors = <String?>[];
      final subscription = container.listen<GroupMonitorState>(
        provider,
        (_, next) => observedRelayErrors.add(next.lastRelayError),
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      notifier.state = GroupMonitorState(
        isMonitoring: true,
        autoInviteEnabled: true,
        isBoostActive: true,
        boostedGroupId: 'grp_11111111-1111-1111-1111-111111111111',
        boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );

      final hint = RelayHintMessage.create(
        groupId: 'grp_11111111-1111-1111-1111-111111111111',
        worldId: 'wrld_12345678-1234-1234-1234-123456789abc',
        instanceId: '12345~alpha',
        nUsers: 9,
        sourceClientId: 'relay_peer',
      );
      await relayService.emitHint(hint);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(observedRelayErrors, contains('unexpected_invite_error'));
    });
  });

  group('relay circuit breaker', () {
    test(
      'opens circuit after threshold consecutive connection errors',
      () async {
        final relayService = _RelayHintServiceFake();
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          overrides: [relayHintServiceProvider.overrideWithValue(relayService)],
        );
        final container = harness.container;
        final provider = harness.provider;
        addTearDown(container.dispose);

        final states = <GroupMonitorState>[];
        final subscription = container.listen<GroupMonitorState>(
          provider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );
        addTearDown(subscription.close);

        // Emit connection errors up to the circuit breaker threshold (4).
        for (var i = 0; i < AppConstants.relayCircuitBreakerThreshold; i++) {
          await relayService.emitStatus(
            const RelayConnectionStatus(
              connected: false,
              error: 'test_connection_error',
            ),
          );
          await Future<void>.delayed(Duration.zero);
        }

        // The circuit breaker state is emitted synchronously before
        // disconnect() fires. Check that the states list captured it.
        final circuitBreakerState = states.firstWhere(
          (s) => s.lastRelayError == 'relay_circuit_breaker',
          orElse: () => throw StateError('Circuit breaker state not emitted'),
        );
        expect(circuitBreakerState.relayTemporarilyDisabledUntil, isNotNull);
        expect(
          circuitBreakerState.relayTemporarilyDisabledUntil!.isAfter(
            DateTime.now(),
          ),
          isTrue,
        );
        expect(circuitBreakerState.relayConnected, isFalse);
      },
    );

    // A successful connection must reset the streak so that a subsequent run
    // of N-1 errors does not re-open the circuit.
    test('streak_resets_on_successful_connection', () async {
      final relayService = _RelayHintServiceFake();
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        overrides: [relayHintServiceProvider.overrideWithValue(relayService)],
      );
      final container = harness.container;
      final provider = harness.provider;
      addTearDown(container.dispose);

      final states = <GroupMonitorState>[];
      final subscription = container.listen<GroupMonitorState>(
        provider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      // Emit one fewer error than the threshold (streak not yet at limit).
      for (var i = 0; i < AppConstants.relayCircuitBreakerThreshold - 1; i++) {
        await relayService.emitStatus(
          const RelayConnectionStatus(
            connected: false,
            error: 'test_connection_error',
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }

      // A successful connection resets the streak to zero.
      await relayService.emitStatus(
        const RelayConnectionStatus(connected: true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(provider).relayConnected, isTrue);

      // Another N-1 errors should NOT open the circuit (streak was reset).
      for (var i = 0; i < AppConstants.relayCircuitBreakerThreshold - 1; i++) {
        await relayService.emitStatus(
          const RelayConnectionStatus(
            connected: false,
            error: 'test_connection_error',
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }

      // Circuit breaker must NOT have fired in any observed state.
      expect(
        states.any((s) => s.lastRelayError == 'relay_circuit_breaker'),
        isFalse,
        reason: 'circuit should not open when streak was reset by a success',
      );
    });

    // After the circuit opens, the cooldown stored in
    // runtimeDisabledUntilOverride propagates back to state whenever
    // _reconcileRelayConnection runs, so connect() is not called again.
    test('circuit_breaker_cooldown_prevents_reconnect', () async {
      final relayService = _RelayHintServiceFake();
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        overrides: [relayHintServiceProvider.overrideWithValue(relayService)],
      );
      final container = harness.container;
      final notifier = harness.notifier;
      addTearDown(container.dispose);

      // Open the circuit by emitting the threshold number of errors.
      for (var i = 0; i < AppConstants.relayCircuitBreakerThreshold; i++) {
        await relayService.emitStatus(
          const RelayConnectionStatus(
            connected: false,
            error: 'test_connection_error',
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }

      // Simulate the relay service's own cooldown (what runtimeDisabledUntil
      // would return after a real server-side disable or circuit open).
      relayService.runtimeDisabledUntilOverride = DateTime.now().add(
        const Duration(minutes: 10),
      );
      final countAtBreak = relayService.connectCallCount;

      // Toggle auto-invite off then on to trigger _reconcileRelayConnection()
      // twice without waiting for a real polling timer.
      await notifier
          .toggleAutoInvite(); // off — clears lastRelayError, syncs cooldown
      await Future<void>.delayed(Duration.zero);
      await notifier
          .toggleAutoInvite(); // on  — cooldown still future, connect() blocked
      await Future<void>.delayed(Duration.zero);

      expect(
        relayService.connectCallCount,
        countAtBreak,
        reason: 'connect() must not be called while cooldown is in the future',
      );
    });

    // Once the cooldown has elapsed, _reconcileRelayConnection() must call
    // connect() again so the client recovers without manual intervention.
    test('circuit_breaker_resets_after_cooldown', () async {
      final relayService = _RelayHintServiceFake();
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        overrides: [relayHintServiceProvider.overrideWithValue(relayService)],
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);

      // Open the circuit.
      for (var i = 0; i < AppConstants.relayCircuitBreakerThreshold; i++) {
        await relayService.emitStatus(
          const RelayConnectionStatus(
            connected: false,
            error: 'test_connection_error',
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }

      // Leave runtimeDisabledUntilOverride as null (cooldown expired).
      final countAtBreak = relayService.connectCallCount;

      // Set the state so _shouldConnectRelay() can return true once the
      // cooldown is cleared.  Direct state assignment is used here to avoid
      // side effects from the full setBoostedGroup() flow.
      notifier.state = notifier.state.copyWith(
        isMonitoring: true,
        autoInviteEnabled: true,
        isBoostActive: true,
        boostedGroupId: 'grp_alpha',
      );

      // Toggle auto-invite off: clears lastRelayError and sets
      // relayTemporarilyDisabledUntil from runtimeDisabledUntilOverride (null).
      await notifier.toggleAutoInvite(); // off
      await Future<void>.delayed(Duration.zero);

      // Toggle auto-invite on: cooldown is now null → connect() fires.
      await notifier.toggleAutoInvite(); // on
      await Future<void>.delayed(Duration.zero);

      expect(
        relayService.connectCallCount,
        greaterThan(countAtBreak),
        reason: 'connect() must be called once the cooldown has elapsed',
      );
      expect(container.read(provider).relayConnected, isTrue);
    });
  });

  group('relay hint filtering and deduplication', () {
    /// Returns a [GroupMonitorState] with all prerequisites for relay hint
    /// processing satisfied: monitoring, auto-invite, boost active for [groupId].
    GroupMonitorState activeState({
      String groupId = 'grp_11111111-1111-1111-1111-111111111111',
    }) => GroupMonitorState(
      isMonitoring: true,
      autoInviteEnabled: true,
      isBoostActive: true,
      boostedGroupId: groupId,
      boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );

    RelayHintMessage validHint({
      String groupId = 'grp_11111111-1111-1111-1111-111111111111',
    }) => RelayHintMessage.create(
      groupId: groupId,
      worldId: 'wrld_12345678-1234-1234-1234-123456789abc',
      instanceId: '12345~alpha',
      nUsers: 9,
      sourceClientId: 'relay_peer',
    );

    test('hint_for_monitored_group_increments_relayHintsReceived', () async {
      final relayService = _RelayHintServiceFake();
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        overrides: [relayHintServiceProvider.overrideWithValue(relayService)],
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);

      notifier.state = activeState();

      await relayService.emitHint(validHint());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(provider).relayHintsReceived, 1);
    });

    test('hint_for_wrong_group_is_ignored', () async {
      final relayService = _RelayHintServiceFake();
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        overrides: [relayHintServiceProvider.overrideWithValue(relayService)],
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);

      notifier.state = activeState(
        groupId: 'grp_11111111-1111-1111-1111-111111111111',
      );

      await relayService.emitHint(
        validHint(groupId: 'grp_22222222-2222-2222-2222-222222222222'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(provider).relayHintsReceived, 0);
    });

    test('duplicate_hint_id_is_deduplicated', () async {
      final relayService = _RelayHintServiceFake();
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        overrides: [relayHintServiceProvider.overrideWithValue(relayService)],
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);

      notifier.state = activeState();

      final hint = validHint();
      await relayService.emitHint(hint);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await relayService.emitHint(hint); // same hint again
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(provider).relayHintsReceived, 1);
    });

    test('duplicate_instance_key_is_deduplicated', () async {
      final relayService = _RelayHintServiceFake();
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        overrides: [relayHintServiceProvider.overrideWithValue(relayService)],
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);

      notifier.state = activeState();

      // Two hints with different hintIds but same worldId+instanceId (same instanceKey).
      final hint1 = RelayHintMessage.create(
        groupId: 'grp_11111111-1111-1111-1111-111111111111',
        worldId: 'wrld_12345678-1234-1234-1234-123456789abc',
        instanceId: '12345~alpha',
        nUsers: 9,
        sourceClientId: 'peer_a',
      );
      final hint2 = RelayHintMessage.create(
        groupId: 'grp_11111111-1111-1111-1111-111111111111',
        worldId: 'wrld_12345678-1234-1234-1234-123456789abc',
        instanceId: '12345~alpha',
        nUsers: 9,
        sourceClientId: 'peer_b',
      );

      await relayService.emitHint(hint1);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await relayService.emitHint(hint2);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(provider).relayHintsReceived, 1);
    });

    test('invalid_or_expired_hint_records_relay_failure', () async {
      final relayService = _RelayHintServiceFake();
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        overrides: [relayHintServiceProvider.overrideWithValue(relayService)],
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);

      notifier.state = activeState();

      final observedErrors = <String?>[];
      final subscription = container.listen<GroupMonitorState>(
        provider,
        (_, next) => observedErrors.add(next.lastRelayError),
        fireImmediately: false,
      );
      addTearDown(subscription.close);

      // An expired hint (expiresAt in the past).
      final expiredHint = RelayHintMessage(
        version: '1',
        hintId: 'hint_expired',
        groupId: 'grp_alpha',
        worldId: 'wrld_12345678-1234-1234-1234-123456789abc',
        instanceId: '12345~alpha',
        nUsers: 1,
        detectedAt: DateTime.utc(2000),
        expiresAt: DateTime.utc(2000),
        sourceClientId: 'peer_a',
      );
      await relayService.emitHint(expiredHint);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        observedErrors,
        contains('invalid_or_expired_hint'),
        reason: 'expired hint must record a relay failure',
      );
      expect(container.read(provider).relayHintsReceived, 0);
    });
  });

  group('setBoostedGroup', () {
    test(
      'emits one state update and resets boost diagnostics fields',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final provider = groupMonitorProvider('usr_test');
        final notifier = container.read(provider.notifier);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        notifier.state = GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
          isMonitoring: true,
          boostPollCount: 7,
          lastBoostLatencyMs: 150,
          lastBoostFetchedAt: DateTime.utc(2026, 2, 13, 10, 0),
          boostFirstSeenAfter: const Duration(seconds: 12),
        );

        final emittedStates = <GroupMonitorState>[];
        final subscription = container.listen<GroupMonitorState>(
          provider,
          (_, next) => emittedStates.add(next),
          fireImmediately: false,
        );

        await notifier.setBoostedGroup('grp_alpha');
        subscription.close();
        notifier.stopMonitoring();

        expect(emittedStates, hasLength(1));
        final updated = emittedStates.single;
        expect(updated.boostedGroupId, 'grp_alpha');
        expect(updated.boostExpiresAt, isNotNull);
        expect(updated.boostPollCount, 0);
        expect(updated.lastBoostLatencyMs, isNull);
        expect(updated.lastBoostFetchedAt, isNull);
        expect(updated.boostFirstSeenAfter, isNull);
      },
    );
  });
}
