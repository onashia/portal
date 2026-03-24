import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runtime application version loaded during startup from package metadata.
///
/// The root [ProviderScope] must override this in production startup and in
/// tests that instantiate providers relying on runtime version headers.
final appVersionProvider = Provider<String>((ref) {
  throw StateError(
    'appVersionProvider must be overridden during app startup or in tests.',
  );
});
