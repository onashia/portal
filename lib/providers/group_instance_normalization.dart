import 'package:vrchat_dart/vrchat_dart.dart';

final RegExp _groupInstanceRegionPattern = RegExp(r'~region\(([^)]+)\)');

String groupInstanceStableKey({
  required String worldId,
  required String instanceId,
}) {
  return '$worldId|$instanceId';
}

Instance normalizeGroupInstance({
  required GroupInstance groupInstance,
  required String groupId,
  Instance? enrichedInstance,
}) {
  final world = groupInstance.world;
  final worldId = world.id;
  final instanceId = groupInstance.instanceId;
  final location = groupInstance.location;
  final memberCount = groupInstance.memberCount;
  final photonRegion = parseGroupInstancePhotonRegion(location);
  final region = parseGroupInstanceRegion(location);

  return Instance(
    active: enrichedInstance?.active,
    ageGate: enrichedInstance?.ageGate,
    calendarEntryId: enrichedInstance?.calendarEntryId,
    canRequestInvite: enrichedInstance?.canRequestInvite,
    capacity: enrichedInstance?.capacity ?? world.capacity,
    clientNumber: 'unknown',
    closedAt: enrichedInstance?.closedAt,
    contentSettings: enrichedInstance?.contentSettings,
    creatorId: enrichedInstance?.creatorId,
    displayName: enrichedInstance?.displayName,
    friends: enrichedInstance?.friends,
    full: enrichedInstance?.full ?? false,
    gameServerVersion: enrichedInstance?.gameServerVersion,
    groupAccessType: enrichedInstance?.groupAccessType,
    hardClose: enrichedInstance?.hardClose,
    hasCapacityForYou: enrichedInstance?.hasCapacityForYou,
    hidden: enrichedInstance?.hidden,
    id: enrichedInstance?.id ?? location,
    instanceId: instanceId,
    instancePersistenceEnabled: enrichedInstance?.instancePersistenceEnabled,
    location: location,
    nUsers: memberCount,
    name: enrichedInstance?.name ?? instanceId,
    nonce: enrichedInstance?.nonce,
    ownerId: enrichedInstance?.ownerId ?? groupId,
    permanent: enrichedInstance?.permanent ?? false,
    photonRegion: enrichedInstance?.photonRegion ?? photonRegion,
    platforms:
        enrichedInstance?.platforms ??
        InstancePlatforms(android: 0, standalonewindows: memberCount),
    playerPersistenceEnabled: enrichedInstance?.playerPersistenceEnabled,
    private: enrichedInstance?.private,
    queueEnabled: enrichedInstance?.queueEnabled ?? false,
    queueSize: enrichedInstance?.queueSize ?? 0,
    recommendedCapacity:
        enrichedInstance?.recommendedCapacity ?? world.recommendedCapacity,
    region: enrichedInstance?.region ?? region,
    roleRestricted: enrichedInstance?.roleRestricted,
    secureName: enrichedInstance?.secureName ?? instanceId,
    shortName: enrichedInstance?.shortName,
    strict: enrichedInstance?.strict ?? false,
    tags: enrichedInstance?.tags ?? const [],
    type: enrichedInstance?.type ?? InstanceType.group,
    userCount: memberCount,
    users: enrichedInstance?.users,
    world: world,
    worldId: worldId,
  );
}

Instance mergeDiscoveryInstanceWithEnrichment({
  required Instance discoveryInstance,
  required Instance enrichedInstance,
  required String groupId,
}) {
  return Instance(
    active: enrichedInstance.active,
    ageGate: enrichedInstance.ageGate,
    calendarEntryId: enrichedInstance.calendarEntryId,
    canRequestInvite: enrichedInstance.canRequestInvite,
    capacity: enrichedInstance.capacity ?? discoveryInstance.capacity,
    clientNumber: 'unknown',
    closedAt: enrichedInstance.closedAt,
    contentSettings: enrichedInstance.contentSettings,
    creatorId: enrichedInstance.creatorId,
    displayName: enrichedInstance.displayName,
    friends: enrichedInstance.friends,
    full: enrichedInstance.full,
    gameServerVersion: enrichedInstance.gameServerVersion,
    groupAccessType: enrichedInstance.groupAccessType,
    hardClose: enrichedInstance.hardClose,
    hasCapacityForYou: enrichedInstance.hasCapacityForYou,
    hidden: enrichedInstance.hidden,
    id: enrichedInstance.id,
    instanceId: discoveryInstance.instanceId,
    instancePersistenceEnabled: enrichedInstance.instancePersistenceEnabled,
    location: discoveryInstance.location,
    nUsers: discoveryInstance.nUsers,
    name: enrichedInstance.name,
    nonce: enrichedInstance.nonce,
    ownerId: enrichedInstance.ownerId ?? groupId,
    permanent: enrichedInstance.permanent,
    photonRegion: enrichedInstance.photonRegion,
    platforms: enrichedInstance.platforms,
    playerPersistenceEnabled: enrichedInstance.playerPersistenceEnabled,
    private: enrichedInstance.private,
    queueEnabled: enrichedInstance.queueEnabled,
    queueSize: enrichedInstance.queueSize,
    recommendedCapacity: enrichedInstance.recommendedCapacity,
    region: enrichedInstance.region,
    roleRestricted: enrichedInstance.roleRestricted,
    secureName: enrichedInstance.secureName,
    shortName: enrichedInstance.shortName,
    strict: enrichedInstance.strict,
    tags: enrichedInstance.tags,
    type: enrichedInstance.type,
    userCount: discoveryInstance.userCount,
    users: enrichedInstance.users,
    world: discoveryInstance.world,
    worldId: discoveryInstance.worldId,
  );
}

Region parseGroupInstancePhotonRegion(String location) {
  final region = _parseGroupInstanceRegionValue(location);
  return switch (region) {
    'eu' => Region.eu,
    'jp' => Region.jp,
    'us' => Region.us,
    'use' => Region.use,
    'usw' => Region.usw,
    'usx' => Region.usx,
    _ => Region.unknown,
  };
}

InstanceRegion parseGroupInstanceRegion(String location) {
  final region = _parseGroupInstanceRegionValue(location);
  return switch (region) {
    'eu' => InstanceRegion.eu,
    'jp' => InstanceRegion.jp,
    'us' => InstanceRegion.us,
    'use' => InstanceRegion.use,
    _ => InstanceRegion.unknown,
  };
}

String? _parseGroupInstanceRegionValue(String location) {
  final match = _groupInstanceRegionPattern.firstMatch(location);
  return match?.group(1);
}
