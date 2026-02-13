import 'package:flutter_test/flutter_test.dart';
import 'package:portal/utils/vrchat_image_utils.dart';

void main() {
  group('extractFileIdFromUrl', () {
    test('extracts file ID and version from standard URL', () {
      const url = 'https://api.vrchat.cloud/api/1/file_abc123/2';
      final result = extractFileIdFromUrl(url);
      expect(result.fileId, 'file_abc123');
      expect(result.version, 2);
    });

    test('extracts file ID with version as first path segment', () {
      const url = 'https://api.vrchat.cloud/file_xyz789/5';
      final result = extractFileIdFromUrl(url);
      expect(result.fileId, 'file_xyz789');
      expect(result.version, 5);
    });

    test('defaults version to 1 when not present in URL', () {
      const url = 'https://api.vrchat.cloud/api/1/file_test123';
      final result = extractFileIdFromUrl(url);
      expect(result.fileId, 'file_test123');
      expect(result.version, 1);
    });

    test('extracts file ID with query parameters', () {
      const url =
          'https://api.vrchat.cloud/api/1/file_query123/3?token=abc&size=large';
      final result = extractFileIdFromUrl(url);
      expect(result.fileId, 'file_query123');
      expect(result.version, 3);
    });

    test('extracts file ID with fragment', () {
      const url = 'https://api.vrchat.cloud/api/1/file_frag456/4#section';
      final result = extractFileIdFromUrl(url);
      expect(result.fileId, 'file_frag456');
      expect(result.version, 4);
    });

    test('handles file ID with underscores', () {
      const url = 'https://api.vrchat.cloud/api/1/file_abc_def_123/2';
      final result = extractFileIdFromUrl(url);
      expect(result.fileId, 'file_abc_def_123');
      expect(result.version, 2);
    });

    test('extracts from URL with multiple path segments before file ID', () {
      const url =
          'https://api.vrchat.cloud/api/1/users/user123/file_multi789/3';
      final result = extractFileIdFromUrl(url);
      expect(result.fileId, 'file_multi789');
      expect(result.version, 3);
    });

    test('treats non-numeric next segment as no version', () {
      const url = 'https://api.vrchat.cloud/api/1/file_numericabc/nextsegment';
      final result = extractFileIdFromUrl(url);
      expect(result.fileId, 'file_numericabc');
      expect(result.version, 1);
    });

    test('throws ArgumentError when URL is empty', () {
      expect(
        () => extractFileIdFromUrl(''),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'URL cannot be empty',
          ),
        ),
      );
    });

    test('throws FormatException when no file_ prefix found', () {
      const url = 'https://api.vrchat.cloud/api/1/no_file_here/1';
      expect(
        () => extractFileIdFromUrl(url),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Could not extract file ID from URL'),
          ),
        ),
      );
    });

    test('throws FormatException when URL has no path segments', () {
      const url = 'https://api.vrchat.cloud';
      expect(() => extractFileIdFromUrl(url), throwsA(isA<FormatException>()));
    });

    test('extracts file ID with special characters', () {
      const url = 'https://api.vrchat.cloud/api/1/file_special-123/2';
      final result = extractFileIdFromUrl(url);
      expect(result.fileId, 'file_special-123');
      expect(result.version, 2);
    });
  });
}
