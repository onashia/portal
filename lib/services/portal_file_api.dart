import 'dart:typed_data';

import 'package:vrchat_dart/vrchat_dart.dart';

import 'api_rate_limit_coordinator.dart';
import 'portal_api_request_runner.dart';

Uint8List extractDownloadedFileBytes({
  required Object? data,
  required String fileId,
  required int versionId,
}) {
  if (data is Uint8List) {
    return data;
  }

  throw StateError(
    'Expected Uint8List from file download for $fileId/$versionId, '
    'got ${data.runtimeType}.',
  );
}

class PortalFileApi {
  PortalFileApi(this._api, this._runner);

  final VrchatDart _api;
  final PortalApiRequestRunner _runner;

  Future<Uint8List> downloadFileVersion({
    required String fileId,
    required int versionId,
  }) async {
    final response = await _runner.run(
      lane: ApiRequestLane.image,
      request: (extra) => _api.rawApi.getFilesApi().downloadFileVersion(
        fileId: fileId,
        versionId: versionId,
        extra: extra,
      ),
    );
    return extractDownloadedFileBytes(
      data: response.data,
      fileId: fileId,
      versionId: versionId,
    );
  }
}
