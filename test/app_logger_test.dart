import 'package:flutter_test/flutter_test.dart';
import 'package:portal/utils/app_logger.dart';

void main() {
  group('AppLogger.shouldEmitForTesting', () {
    test('returns false when not in debug mode', () {
      expect(
        AppLogger.shouldEmitForTesting(
          level: 500,
          isDebugMode: false,
          debugLogsEnabled: true,
        ),
        isFalse,
      );
      expect(
        AppLogger.shouldEmitForTesting(
          level: 700,
          isDebugMode: false,
          debugLogsEnabled: false,
        ),
        isFalse,
      );
    });

    test('keeps info/warning/error enabled in debug mode', () {
      expect(
        AppLogger.shouldEmitForTesting(
          level: 500,
          isDebugMode: true,
          debugLogsEnabled: false,
        ),
        isTrue,
      );
      expect(
        AppLogger.shouldEmitForTesting(
          level: 900,
          isDebugMode: true,
          debugLogsEnabled: false,
        ),
        isTrue,
      );
      expect(
        AppLogger.shouldEmitForTesting(
          level: 1000,
          isDebugMode: true,
          debugLogsEnabled: false,
        ),
        isTrue,
      );
    });

    test('gates debug logs on PORTAL_DEBUG_LOGS flag', () {
      expect(
        AppLogger.shouldEmitForTesting(
          level: 700,
          isDebugMode: true,
          debugLogsEnabled: false,
        ),
        isFalse,
      );
      expect(
        AppLogger.shouldEmitForTesting(
          level: 700,
          isDebugMode: true,
          debugLogsEnabled: true,
        ),
        isTrue,
      );
    });
  });
}
