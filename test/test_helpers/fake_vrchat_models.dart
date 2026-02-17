import 'package:vrchat_dart/vrchat_dart.dart';

World buildTestWorld({required String id, required String name}) {
  return World(
    authorId: 'usr_author',
    authorName: 'Author',
    capacity: 40,
    createdAt: DateTime.utc(2024, 1, 1),
    description: 'Test world',
    id: id,
    imageUrl: 'https://example.com/$id.png',
    labsPublicationDate: '2024-01-01',
    name: name,
    publicationDate: '2024-01-01',
    recommendedCapacity: 16,
    releaseStatus: ReleaseStatus.public,
    tags: const [],
    thumbnailImageUrl: 'https://example.com/$id-thumb.png',
    updatedAt: DateTime.utc(2024, 1, 1),
  );
}

Instance buildTestInstance({
  required String instanceId,
  required World world,
  required int userCount,
}) {
  return Instance(
    clientNumber: 'unknown',
    id: 'inst_$instanceId',
    instanceId: instanceId,
    location: '${world.id}:$instanceId',
    nUsers: userCount,
    name: 'Instance $instanceId',
    photonRegion: Region.us,
    platforms: InstancePlatforms(android: 0, standalonewindows: userCount),
    queueEnabled: false,
    queueSize: 0,
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

LimitedUserGroups buildTestGroup({
  required String groupId,
  required String name,
}) {
  return LimitedUserGroups(groupId: groupId, name: name);
}
