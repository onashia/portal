import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/services/api_rate_limit_coordinator.dart';
import 'package:portal/services/portal_api_request_runner.dart';
import 'package:portal/services/portal_file_api.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

class _MockVrchatDart extends Mock implements VrchatDart {}

class _MockVrchatRawApi extends Mock implements VrchatDartGenerated {}

class _MockFilesApi extends Mock implements FilesApi {}

void main() {
  test('returns bytes and forwards image lane metadata', () async {
    final api = _MockVrchatDart();
    final rawApi = _MockVrchatRawApi();
    final filesApi = _MockFilesApi();
    final bytes = Uint8List.fromList(<int>[1, 2, 3]);
    final recordedLanes = <ApiRequestLane?>[];
    final runner = PortalApiRequestRunner(
      coordinator: ApiRateLimitCoordinator(),
      recordApiCall: ({lane}) => recordedLanes.add(lane),
      recordThrottledSkip: ({lane}) {},
    );
    final service = PortalFileApi(api, runner);

    when(() => api.rawApi).thenReturn(rawApi);
    when(() => rawApi.getFilesApi()).thenReturn(filesApi);
    when(
      () => filesApi.downloadFileVersion(
        fileId: 'file_alpha',
        versionId: 2,
        extra: any(named: 'extra'),
      ),
    ).thenAnswer(
      (_) async => dio.Response<Uint8List>(
        requestOptions: dio.RequestOptions(path: '/file/file_alpha/2'),
        statusCode: 200,
        data: bytes,
      ),
    );

    final result = await service.downloadFileVersion(
      fileId: 'file_alpha',
      versionId: 2,
    );

    expect(result, bytes);
    expect(recordedLanes, [ApiRequestLane.image]);
    final extra =
        verify(
              () => filesApi.downloadFileVersion(
                fileId: 'file_alpha',
                versionId: 2,
                extra: captureAny(named: 'extra'),
              ),
            ).captured.single
            as Map<String, dynamic>?;
    expect(
      apiRequestLaneFromExtraValue(extra?[portalApiLaneExtraKey]),
      ApiRequestLane.image,
    );
  });

  test('throws a descriptive error for non-byte payloads', () {
    expect(
      () => extractDownloadedFileBytes(
        data: 'not-bytes',
        fileId: 'file_alpha',
        versionId: 2,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Expected Uint8List from file download for file_alpha/2'),
        ),
      ),
    );
  });

  test('throws a descriptive error for null payloads', () {
    expect(
      () => extractDownloadedFileBytes(
        data: null,
        fileId: 'file_alpha',
        versionId: 2,
      ),
      throwsA(
        isA<StateError>()
            .having(
              (error) => error.message,
              'message',
              contains('Expected Uint8List from file download for file_alpha/2'),
            )
            .having(
              (error) => error.message,
              'message',
              contains('got Null'),
            ),
      ),
    );
  });
}
