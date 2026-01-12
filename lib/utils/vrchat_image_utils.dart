import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:portal/providers/auth_provider.dart';

class FileIdInfo {
  final String fileId;
  final int version;

  FileIdInfo({required this.fileId, this.version = 1});
}

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
    final response = await api.rawApi.getFilesApi().downloadFileVersion(
      fileId: fileIdInfo.fileId,
      versionId: fileIdInfo.version,
    );
    return response.data as Uint8List;
  } catch (e) {
    debugPrint('[IMAGE_FETCH] Failed to fetch image: $e');
    return null;
  }
}
