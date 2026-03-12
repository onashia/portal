import 'package:flutter_test/flutter_test.dart';
import 'package:portal/providers/group_instance_normalization.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import 'test_helpers/fake_vrchat_models.dart';

void main() {
  GroupInstance buildGroupInstance({
    required String worldId,
    required String instanceId,
    required String location,
    required int memberCount,
    String worldName = 'World',
  }) {
    return GroupInstance(
      instanceId: instanceId,
      location: location,
      memberCount: memberCount,
      world: buildTestWorld(id: worldId, name: worldName),
    );
  }

  group('normalizeGroupInstance', () {
    test('maps group discovery payload into instance fields', () {
      final groupInstance = buildGroupInstance(
        worldId: 'wrld_alpha',
        instanceId: '12345~region(eu)',
        location: 'wrld_alpha:12345~region(eu)',
        memberCount: 6,
        worldName: 'Alpha',
      );

      final normalized = normalizeGroupInstance(
        groupInstance: groupInstance,
        groupId: 'grp_alpha',
      );

      expect(normalized.worldId, 'wrld_alpha');
      expect(normalized.instanceId, '12345~region(eu)');
      expect(normalized.location, 'wrld_alpha:12345~region(eu)');
      expect(normalized.nUsers, 6);
      expect(normalized.userCount, 6);
      expect(normalized.world.name, 'Alpha');
      expect(normalized.ownerId, 'grp_alpha');
      expect(normalized.region, InstanceRegion.eu);
      expect(normalized.photonRegion, Region.eu);
      expect(normalized.canRequestInvite, isNull);
    });

    test('overlays enriched metadata while keeping discovery counts', () {
      final groupInstance = buildGroupInstance(
        worldId: 'wrld_alpha',
        instanceId: 'inst_alpha',
        location: 'wrld_alpha:inst_alpha',
        memberCount: 4,
      );
      final enriched = buildTestInstance(
        instanceId: 'inst_alpha',
        world: buildTestWorld(id: 'wrld_alpha', name: 'Ignored'),
        userCount: 99,
      );

      final normalized = normalizeGroupInstance(
        groupInstance: groupInstance,
        groupId: 'grp_alpha',
        enrichedInstance: enriched,
      );

      expect(normalized.canRequestInvite, enriched.canRequestInvite);
      expect(normalized.secureName, enriched.secureName);
      expect(normalized.nUsers, 4);
      expect(normalized.userCount, 4);
      expect(normalized.world.name, 'World');
    });
  });

  group('mergeDiscoveryInstanceWithEnrichment', () {
    test(
      'keeps discovery identity and population while applying enrichment',
      () {
        final discovery = normalizeGroupInstance(
          groupInstance: buildGroupInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_alpha',
            location: 'wrld_alpha:inst_alpha',
            memberCount: 5,
            worldName: 'Discovery World',
          ),
          groupId: 'grp_alpha',
        );
        final enriched = buildTestInstance(
          instanceId: 'inst_alpha',
          world: buildTestWorld(id: 'wrld_alpha', name: 'Enriched World'),
          userCount: 11,
        );

        final merged = mergeDiscoveryInstanceWithEnrichment(
          discoveryInstance: discovery,
          enrichedInstance: enriched,
          groupId: 'grp_alpha',
        );

        expect(merged.location, discovery.location);
        expect(merged.worldId, discovery.worldId);
        expect(merged.world.name, 'Discovery World');
        expect(merged.nUsers, 5);
        expect(merged.userCount, 5);
        expect(merged.secureName, enriched.secureName);
        expect(merged.platforms, enriched.platforms);
      },
    );
  });

  group('region parsing', () {
    test('falls back to unknown for missing or unsupported region tags', () {
      expect(
        parseGroupInstanceRegion('wrld_alpha:inst_alpha'),
        InstanceRegion.unknown,
      );
      expect(
        parseGroupInstancePhotonRegion('wrld_alpha:inst_alpha~region(usw)'),
        Region.usw,
      );
      expect(
        parseGroupInstanceRegion('wrld_alpha:inst_alpha~region(usw)'),
        InstanceRegion.unknown,
      );
    });
  });
}
