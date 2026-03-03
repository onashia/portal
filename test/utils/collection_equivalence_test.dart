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

  group('areMapsEquivalent', () {
    test('returns true for identical maps', () {
      final map = {'a': 1, 'b': 2};
      expect(areMapsEquivalent(map, map), isTrue);
    });

    test('returns true for equivalent maps using default equality', () {
      expect(
        areMapsEquivalent(const {'a': 1, 'b': 2}, const {'b': 2, 'a': 1}),
        isTrue,
      );
    });

    test('returns false when keys differ', () {
      expect(areMapsEquivalent(const {'a': 1}, const {'b': 1}), isFalse);
    });

    test('returns false when values differ', () {
      expect(areMapsEquivalent(const {'a': 1}, const {'a': 2}), isFalse);
    });

    test('returns false when map lengths differ', () {
      expect(
        areMapsEquivalent(const {'a': 1, 'b': 2}, const {'a': 1}),
        isFalse,
      );
    });

    test('supports custom value equality', () {
      expect(
        areMapsEquivalent(
          const {'a': 'A', 'b': 'B'},
          const {'a': 'a', 'b': 'b'},
          valueEquals: (left, right) =>
              left.toLowerCase() == right.toLowerCase(),
        ),
        isTrue,
      );

      expect(
        areMapsEquivalent(
          const {'a': 'A', 'b': 'C'},
          const {'a': 'a', 'b': 'b'},
          valueEquals: (left, right) =>
              left.toLowerCase() == right.toLowerCase(),
        ),
        isFalse,
      );
    });

    test('handles maps with list values and custom comparators', () {
      expect(
        areMapsEquivalent(
          {
            'a': [1, 2],
            'b': [3, 4],
          },
          {
            'a': [1, 2],
            'b': [3, 4],
          },
          valueEquals: areListsEquivalent,
        ),
        isTrue,
      );

      expect(
        areMapsEquivalent(
          {
            'a': [1, 2],
            'b': [3, 4],
          },
          {
            'a': [1, 2],
            'b': [3, 5],
          },
          valueEquals: areListsEquivalent,
        ),
        isFalse,
      );
    });
  });
}
