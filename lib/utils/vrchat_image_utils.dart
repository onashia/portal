import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:portal/models/file_id_info.dart';
import 'package:portal/providers/api_call_counter.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:portal/services/api_rate_limit_coordinator.dart';
import 'package:portal/utils/app_logger.dart';

FileIdInfo extractFileIdFromUrl(String url) {
  if (url.isEmpty) {
    throw ArgumentError('URL cannot be empty');
  }

  final uri = Uri.parse(url);

  final pathSegments = uri.pathSegments;

  for (int i = 0; i < pathSegments.length; i++) {
    final segment = pathSegments[i];

    if (segment.startsWith('file_')) {
      final fileId = segment;

      int version = 1;

      if (i + 1 < pathSegments.length) {
        final nextSegment = pathSegments[i + 1];
        final parsedVersion = int.tryParse(nextSegment);
        if (parsedVersion != null) {
          version = parsedVersion;
        }
      }

      return FileIdInfo(fileId: fileId, version: version);
    }
  }

  throw FormatException('Could not extract file ID from URL: $url');
}

Future<Uint8List?> fetchImageBytesWithAuth(
  WidgetRef ref,
  String imageUrl,
) async {
  if (imageUrl.isEmpty) {
    return null;
  }

  try {
    final api = ref.read(vrchatApiProvider);
    final fileIdInfo = extractFileIdFromUrl(imageUrl);

    AppLogger.debug(
      'Fetching image from API: $imageUrl',
      subCategory: 'image_fetch',
    );

    ref
        .read(apiCallCounterProvider.notifier)
        .incrementApiCall(lane: ApiRequestLane.image);

    final response = await api.rawApi.getFilesApi().downloadFileVersion(
      fileId: fileIdInfo.fileId,
      versionId: fileIdInfo.version,
      extra: apiRequestLaneExtra(ApiRequestLane.image),
    );
    AppLogger.debug(
      'Successfully fetched image: $imageUrl',
      subCategory: 'image_fetch',
    );
    return response.data as Uint8List;
  } catch (e) {
    AppLogger.error(
      'Failed to fetch image: $e',
      subCategory: 'image_fetch',
      error: e,
    );
    return null;
  }
}
