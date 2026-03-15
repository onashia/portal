import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:portal/models/file_id_info.dart';
import 'package:portal/providers/portal_vrchat_api.dart';
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
    final fileApi = ref.read(portalFileApiProvider);
    final fileIdInfo = extractFileIdFromUrl(imageUrl);

    AppLogger.debug(
      'Fetching image from API: $imageUrl',
      subCategory: 'image_fetch',
    );

    final bytes = await fileApi.downloadFileVersion(
      fileId: fileIdInfo.fileId,
      versionId: fileIdInfo.version,
    );
    AppLogger.debug(
      'Successfully fetched image: $imageUrl',
      subCategory: 'image_fetch',
    );
    return bytes;
  } catch (e) {
    AppLogger.error(
      'Failed to fetch image: $e',
      subCategory: 'image_fetch',
      error: e,
    );
    return null;
  }
}
