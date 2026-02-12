import 'package:flutter/foundation.dart';

@immutable
class FileIdInfo {
  final String fileId;
  final int version;

  const FileIdInfo({required this.fileId, this.version = 1});
}
