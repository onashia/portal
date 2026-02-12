import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import 'auth_provider.dart';
import '../utils/app_logger.dart';

class PipelineController {
  final VrcStreaming _streaming;
  bool _started = false;

  PipelineController(this._streaming);

  Stream<VrcStreamingEvent> get events => _streaming.vrcEventStream;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    try {
      _streaming.start();
      AppLogger.info('Pipeline streaming started', subCategory: 'pipeline');
    } catch (e, s) {
      _started = false;
      AppLogger.error(
        'Failed to start pipeline streaming',
        subCategory: 'pipeline',
        error: e,
        stackTrace: s,
      );
    }
  }

  Future<void> stop() async {
    if (!_started) {
      return;
    }
    try {
      _streaming.stop();
      AppLogger.info('Pipeline streaming stopped', subCategory: 'pipeline');
    } catch (e, s) {
      AppLogger.error(
        'Failed to stop pipeline streaming',
        subCategory: 'pipeline',
        error: e,
        stackTrace: s,
      );
    } finally {
      _started = false;
    }
  }
}

final pipelineControllerProvider = Provider<PipelineController>((ref) {
  final api = ref.read(vrchatApiProvider);
  final controller = PipelineController(api.streaming);
  final initialAuth = ref.read(authProvider).asData?.value;

  ref.listen<AsyncValue<AuthState>>(authProvider, (previous, next) {
    final wasAuthenticated =
        previous?.asData?.value.status == AuthStatus.authenticated;
    final isAuthenticated =
        next.asData?.value.status == AuthStatus.authenticated;

    if (isAuthenticated && !wasAuthenticated) {
      unawaited(controller.start());
    } else if (!isAuthenticated && wasAuthenticated) {
      unawaited(controller.stop());
    }
  });

  if (initialAuth?.status == AuthStatus.authenticated) {
    unawaited(controller.start());
  }

  ref.onDispose(() => unawaited(controller.stop()));
  return controller;
});

final pipelineEventsProvider = StreamProvider<VrcStreamingEvent>((ref) {
  final authState = ref.watch(authProvider).asData?.value;
  if (authState?.status != AuthStatus.authenticated) {
    return const Stream.empty();
  }

  final controller = ref.watch(pipelineControllerProvider);
  return controller.events;
});

final pipelineEventHandlerProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<VrcStreamingEvent>>(pipelineEventsProvider, (_, next) {
    final event = next.asData?.value;
    if (event is UserUpdateEvent) {
      ref.read(authProvider.notifier).updateCurrentUser(event.user);
    } else if (event is ErrorEvent) {
      AppLogger.warning(
        'Pipeline streaming error: ${event.message}',
        subCategory: 'pipeline',
      );
    }
  });
});
