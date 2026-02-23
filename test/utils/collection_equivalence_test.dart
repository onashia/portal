import 'package:flutter_test/flutter_test.dart';
import 'package:portal/utils/collection_equivalence.dart';

void main() {
  group('areListsEquivalent', () {
    test('returns true for equal values', () {
      expect(areListsEquivalent(const [1, 2, 3], const [1, 2, 3]), isTrue);
    });

    test('supports custom comparators', () {
      expect(
        areListsEquivalent<String>(
          const ['A', 'B'],
          const ['a', 'b'],
          equals: (left, right) => left.toLowerCase() == right.toLowerCase(),
        ),
        isTrue,
      );
    });

    test('returns false for different lengths or values', () {
      expect(areListsEquivalent(const [1, 2], const [1]), isFalse);
      expect(areListsEquivalent(const [1, 2], const [1, 3]), isFalse);
    });
  });

  group('areStringMapsEquivalent', () {
    test('returns true for value-equivalent maps', () {
      expect(
        areStringMapsEquivalent(
          const {'a': '1', 'b': '2'},
          const {'b': '2', 'a': '1'},
        ),
        isTrue,
      );
    });

    test('returns false when keys or values differ', () {
      expect(
        areStringMapsEquivalent(const {'a': '1'}, const {'a': '2'}),
        isFalse,
      );
      expect(
        areStringMapsEquivalent(const {'a': '1'}, const {'b': '1'}),
        isFalse,
      );
    });
  });
}
