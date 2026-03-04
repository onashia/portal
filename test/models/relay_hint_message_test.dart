import 'package:flutter_test/flutter_test.dart';
import 'package:portal/models/relay_hint_message.dart';

void main() {
  group('RelayHintMessage', () {
    test('create builds valid expiring payload', () {
      final now = DateTime.utc(2026, 3, 3, 12);
      final hint = RelayHintMessage.create(
        groupId: 'grp_alpha',
        worldId: 'wrld_alpha',
        instanceId: 'inst_alpha',
        nUsers: 10,
        sourceClientId: 'usr_a-abc',
        now: now,
      );

      expect(hint.isStructurallyValid, isTrue);
      expect(hint.isExpired(now: now), isFalse);
      expect(hint.instanceKey, 'grp_alpha|wrld_alpha|inst_alpha');
      expect(hint.expiresAt.isAfter(now), isTrue);
    });

    test('round-trips json representation', () {
      final hint = RelayHintMessage.create(
        groupId: 'grp_alpha',
        worldId: 'wrld_alpha',
        instanceId: 'inst_alpha',
        nUsers: 10,
        sourceClientId: 'usr_a-abc',
      );

      final decoded = RelayHintMessage.fromJson(hint.toJson());

      expect(decoded.hintId, hint.hintId);
      expect(decoded.groupId, hint.groupId);
      expect(decoded.worldId, hint.worldId);
      expect(decoded.instanceId, hint.instanceId);
      expect(decoded.nUsers, hint.nUsers);
      expect(decoded.sourceClientId, hint.sourceClientId);
      expect(
        decoded.detectedAt.millisecondsSinceEpoch,
        hint.detectedAt.millisecondsSinceEpoch,
      );
      expect(
        decoded.expiresAt.millisecondsSinceEpoch,
        hint.expiresAt.millisecondsSinceEpoch,
      );
    });
  });
}
