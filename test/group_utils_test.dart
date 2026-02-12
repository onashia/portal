import 'package:flutter_test/flutter_test.dart';
import 'package:portal/utils/group_utils.dart';

void main() {
  group('getShortGroupId', () {
    test('returns ID as-is when length is 8 characters', () {
      const groupId = 'grp12345';
      final result = GroupUtils.getShortGroupId(groupId);
      expect(result, 'grp12345');
    });

    test('returns ID as-is when length is less than 8 characters', () {
      const groupId = 'abc123';
      final result = GroupUtils.getShortGroupId(groupId);
      expect(result, 'abc123');
    });

    test('truncates to first 8 characters when ID is longer than 8', () {
      const groupId = 'grp_abcdefghijk123456';
      final result = GroupUtils.getShortGroupId(groupId);
      expect(result, 'grp_abcd');
    });

    test('truncates exactly to 8 characters when ID is longer', () {
      const groupId = 'verylonggroupidthatislonger';
      final result = GroupUtils.getShortGroupId(groupId);
      expect(result.length, 8);
      expect(result, 'verylong');
    });

    test('handles empty string', () {
      const groupId = '';
      final result = GroupUtils.getShortGroupId(groupId);
      expect(result, '');
    });

    test('handles ID with special characters', () {
      const groupId = 'grp-abc_def_123';
      final result = GroupUtils.getShortGroupId(groupId);
      expect(result, 'grp-abc_');
    });

    test('handles exactly 1 character ID', () {
      const groupId = 'a';
      final result = GroupUtils.getShortGroupId(groupId);
      expect(result, 'a');
    });
  });
}
