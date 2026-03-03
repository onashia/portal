import 'package:flutter_test/flutter_test.dart';
import 'package:portal/utils/chunked_async.dart';

void main() {
  group('runInChunks', () {
    test('preserves order while respecting max concurrency', () async {
      var active = 0;
      var maxActive = 0;

      final result = await runInChunks<int, int>(
        items: const [1, 2, 3, 4, 5],
        maxConcurrent: 2,
        operation: (item) async {
          active += 1;
          if (active > maxActive) {
            maxActive = active;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
          active -= 1;
          return item * 2;
        },
      );

      expect(result, const [2, 4, 6, 8, 10]);
      expect(maxActive, lessThanOrEqualTo(2));
    });

    test('throws when max concurrency is less than 1', () async {
      expect(
        () => runInChunks<int, int>(
          items: const [1],
          maxConcurrent: 0,
          operation: (item) async => item,
        ),
        throwsArgumentError,
      );
    });
  });
}
