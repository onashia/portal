import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/constants/app_constants.dart';
import 'package:portal/services/relay_bootstrap_client.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockDio mockDio;

  setUp(() {
    mockDio = _MockDio();
    registerFallbackValue(Options());
  });

  RelayBootstrapClient makeClient({
    String bootstrapUrl = 'https://relay.test/bootstrap',
    String appSecret = 'test-secret',
    bool allowInsecureTransport = false,
  }) => RelayBootstrapClient(
    dio: mockDio,
    bootstrapUrl: bootstrapUrl,
    appSecret: appSecret,
    allowInsecureTransport: allowInsecureTransport,
  );

  void stubPost(Map<String, dynamic> data) {
    when(
      () => mockDio.post<dynamic>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response(
        data: data,
        statusCode: 200,
        requestOptions: RequestOptions(path: ''),
      ),
    );
  }

  group('isConfigured', () {
    test('returns true with valid url and secret', () {
      expect(makeClient().isConfigured, isTrue);
    });

    test('returns false when appSecret is empty', () {
      expect(makeClient(appSecret: '').isConfigured, isFalse);
    });

    test('returns false when bootstrapUrl is empty', () {
      expect(makeClient(bootstrapUrl: '').isConfigured, isFalse);
    });

    test('returns false when bootstrapUrl is whitespace only', () {
      expect(makeClient(bootstrapUrl: '   ').isConfigured, isFalse);
    });

    test('returns false when bootstrapUrl uses http by default', () {
      expect(
        makeClient(bootstrapUrl: 'http://relay.test/bootstrap').isConfigured,
        isFalse,
      );
    });

    test(
      'returns true for http bootstrapUrl when insecure transport is enabled',
      () {
        expect(
          makeClient(
            bootstrapUrl: 'http://relay.test/bootstrap',
            allowInsecureTransport: true,
          ).isConfigured,
          isTrue,
        );
      },
    );
  });

  group('bootstrap', () {
    final fixedNow = DateTime.utc(2026, 1, 1);
    DateTime? capturedDisabledUntil;

    setUp(() {
      capturedDisabledUntil = null;
    });

    Future<Uri> call(RelayBootstrapClient client) => client.bootstrap(
      groupId: 'grp_12345678-1234-1234-1234-123456789abc',
      clientId: 'client_test',
      now: () => fixedNow,
      onRuntimeDisabled: (until) => capturedDisabledUntil = until,
    );

    test('success returns the parsed wsUrl', () async {
      stubPost({'relayEnabled': true, 'wsUrl': 'wss://relay.test/ws'});

      final uri = await call(makeClient());

      expect(uri, Uri.parse('wss://relay.test/ws'));
    });

    test(
      'throws before request when bootstrapUrl uses http by default',
      () async {
        await expectLater(
          call(makeClient(bootstrapUrl: 'http://relay.test/bootstrap')),
          throwsA(isA<StateError>()),
        );

        verifyNever(
          () => mockDio.post<dynamic>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ),
        );
      },
    );

    test('sends correct payload and x-app-secret header', () async {
      stubPost({'relayEnabled': true, 'wsUrl': 'wss://relay.test/ws'});

      await call(makeClient());

      final captured = verify(
        () => mockDio.post<dynamic>(
          'https://relay.test/bootstrap',
          data: captureAny(named: 'data'),
          options: captureAny(named: 'options'),
        ),
      ).captured;

      final body = captured[0] as Map<String, dynamic>;
      expect(body['groupId'], 'grp_12345678-1234-1234-1234-123456789abc');
      expect(body['clientId'], 'client_test');
      expect(body['version'], '1');

      final opts = captured[1] as Options;
      expect(opts.headers?['x-app-secret'], 'test-secret');
    });

    test('calls onRuntimeDisabled and throws when relay is disabled', () async {
      stubPost({'relayEnabled': false, 'retryAfterSeconds': 120});

      await expectLater(call(makeClient()), throwsA(isA<StateError>()));
      expect(capturedDisabledUntil, fixedNow.add(const Duration(seconds: 120)));
    });

    test(
      'falls back to default cooldown when retryAfterSeconds is absent',
      () async {
        stubPost({'relayEnabled': false});

        await expectLater(call(makeClient()), throwsA(isA<StateError>()));
        expect(
          capturedDisabledUntil,
          fixedNow.add(
            Duration(seconds: AppConstants.relayCircuitBreakerCooldownSeconds),
          ),
        );
      },
    );

    test('throws StateError when response is not a Map', () async {
      when(
        () => mockDio.post<dynamic>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response(
          data: 'not a map',
          statusCode: 200,
          requestOptions: RequestOptions(path: ''),
        ),
      );

      await expectLater(call(makeClient()), throwsA(isA<StateError>()));
    });

    test('throws StateError when wsUrl is absent', () async {
      stubPost({'relayEnabled': true});

      await expectLater(call(makeClient()), throwsA(isA<StateError>()));
    });

    test('throws StateError when wsUrl is empty', () async {
      stubPost({'relayEnabled': true, 'wsUrl': ''});

      await expectLater(call(makeClient()), throwsA(isA<StateError>()));
    });

    test('throws StateError when wsUrl uses ws by default', () async {
      stubPost({'relayEnabled': true, 'wsUrl': 'ws://relay.test/ws'});

      await expectLater(call(makeClient()), throwsA(isA<StateError>()));
    });

    test(
      'accepts insecure relay transport only when explicitly enabled',
      () async {
        stubPost({'relayEnabled': true, 'wsUrl': 'ws://relay.test/ws'});

        final uri = await call(
          makeClient(
            bootstrapUrl: 'http://relay.test/bootstrap',
            allowInsecureTransport: true,
          ),
        );

        expect(uri, Uri.parse('ws://relay.test/ws'));
      },
    );

    test('propagates DioException from the HTTP layer', () async {
      when(
        () => mockDio.post<dynamic>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(DioException(requestOptions: RequestOptions(path: '')));

      await expectLater(call(makeClient()), throwsA(isA<DioException>()));
    });
  });
}
