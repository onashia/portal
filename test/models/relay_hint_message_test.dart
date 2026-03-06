import 'package:flutter_test/flutter_test.dart';
import 'package:portal/models/relay_hint_message.dart';

void main() {
  group('RelayHintMessage', () {
    test('create builds valid expiring payload', () {
      final now = DateTime.utc(2026, 3, 3, 12);
      final hint = RelayHintMessage.create(
        groupId: _validGroupId,
        worldId: 'wrld_12345678-1234-1234-1234-123456789abc',
        instanceId: '12345~alpha',
        nUsers: 10,
        sourceClientId: 'usr_a-abc',
        now: now,
      );

      expect(hint.isStructurallyValid, isTrue);
      expect(hint.isExpired(now: now), isFalse);
      expect(
        hint.instanceKey,
        '$_validGroupId|wrld_12345678-1234-1234-1234-123456789abc|12345~alpha',
      );
      expect(hint.expiresAt.isAfter(now), isTrue);
    });

    test('round-trips json representation', () {
      final hint = RelayHintMessage.create(
        groupId: _validGroupId,
        worldId: 'wrld_12345678-1234-1234-1234-123456789abc',
        instanceId: '12345~alpha',
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

    group('isStructurallyValid', () {
      test('rejects invalid worldId format', () {
        final hint = RelayHintMessage(
          version: '1',
          hintId: 'hint_1',
          groupId: _validGroupId,
          worldId: 'wrld_alpha',
          instanceId: '12345~alpha',
          nUsers: 1,
          detectedAt: _epoch,
          expiresAt: _farFuture,
          sourceClientId: 'usr_a',
        );
        expect(hint.isStructurallyValid, isFalse);
      });

      test('rejects instanceId not starting with a digit', () {
        final hint = RelayHintMessage(
          version: '1',
          hintId: 'hint_1',
          groupId: _validGroupId,
          worldId: 'wrld_12345678-1234-1234-1234-123456789abc',
          instanceId: 'inst_alpha',
          nUsers: 1,
          detectedAt: _epoch,
          expiresAt: _farFuture,
          sourceClientId: 'usr_a',
        );
        expect(hint.isStructurallyValid, isFalse);
      });

      test('rejects empty groupId', () {
        final hint = RelayHintMessage(
          version: '1',
          hintId: 'hint_1',
          groupId: '',
          worldId: 'wrld_12345678-1234-1234-1234-123456789abc',
          instanceId: '12345~alpha',
          nUsers: 1,
          detectedAt: _epoch,
          expiresAt: _farFuture,
          sourceClientId: 'usr_a',
        );
        expect(hint.isStructurallyValid, isFalse);
      });

      test('rejects malformed groupId missing grp_ prefix', () {
        final hint = RelayHintMessage(
          version: '1',
          hintId: 'hint_1',
          groupId: '11111111-1111-1111-1111-111111111111',
          worldId: 'wrld_12345678-1234-1234-1234-123456789abc',
          instanceId: '12345~alpha',
          nUsers: 1,
          detectedAt: _epoch,
          expiresAt: _farFuture,
          sourceClientId: 'usr_a',
        );
        expect(hint.isStructurallyValid, isFalse);
      });

      test('rejects groupId with non-UUID suffix', () {
        final hint = RelayHintMessage(
          version: '1',
          hintId: 'hint_1',
          groupId: 'grp_notauuid',
          worldId: 'wrld_12345678-1234-1234-1234-123456789abc',
          instanceId: '12345~alpha',
          nUsers: 1,
          detectedAt: _epoch,
          expiresAt: _farFuture,
          sourceClientId: 'usr_a',
        );
        expect(hint.isStructurallyValid, isFalse);
      });

      test('accepts valid groupId, worldId, and instanceId', () {
        final hint = RelayHintMessage(
          version: '1',
          hintId: 'hint_1',
          groupId: _validGroupId,
          worldId: 'wrld_12345678-1234-1234-1234-123456789abc',
          instanceId: '12345~alpha',
          nUsers: 1,
          detectedAt: _epoch,
          expiresAt: _farFuture,
          sourceClientId: 'usr_a',
        );
        expect(hint.isStructurallyValid, isTrue);
      });
    });

    group('isExpired', () {
      // Base expiry time used across tests.
      final expiresAt = DateTime.utc(2026, 3, 3, 12, 0, 0);

      RelayHintMessage makeHint() => RelayHintMessage(
        version: '1',
        hintId: 'hint_1',
        groupId: _validGroupId,
        worldId: 'wrld_12345678-1234-1234-1234-123456789abc',
        instanceId: '12345~alpha',
        nUsers: 1,
        detectedAt: _epoch,
        expiresAt: expiresAt,
        sourceClientId: 'usr_a',
      );

      test('returns_false_well_before_expiry', () {
        final hint = makeHint();
        expect(
          hint.isExpired(now: expiresAt.subtract(const Duration(minutes: 10))),
          isFalse,
        );
      });

      test('returns_false_within_default_grace_period_after_expiry', () {
        // Default grace is 5s; at expiresAt + 3s the hint should still be valid.
        final hint = makeHint();
        expect(
          hint.isExpired(now: expiresAt.add(const Duration(seconds: 3))),
          isFalse,
        );
      });

      test('returns_true_at_grace_period_boundary', () {
        // At exactly expiresAt + 5s the hint should be considered expired.
        final hint = makeHint();
        expect(
          hint.isExpired(now: expiresAt.add(const Duration(seconds: 5))),
          isTrue,
        );
      });

      test('returns_true_after_grace_period', () {
        final hint = makeHint();
        expect(
          hint.isExpired(now: expiresAt.add(const Duration(seconds: 60))),
          isTrue,
        );
      });

      test('custom_zero_grace_expires_immediately_at_expiresAt', () {
        final hint = makeHint();
        // With no grace, the hint is expired at exactly expiresAt.
        expect(hint.isExpired(now: expiresAt, grace: Duration.zero), isTrue);
        // One second before expiry it is still valid.
        expect(
          hint.isExpired(
            now: expiresAt.subtract(const Duration(seconds: 1)),
            grace: Duration.zero,
          ),
          isFalse,
        );
      });
    });
  });
}

const _validGroupId = 'grp_11111111-1111-1111-1111-111111111111';
final _epoch = DateTime.utc(2000);
final _farFuture = DateTime.utc(2099);
