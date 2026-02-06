import 'package:dio/dio.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../utils/app_logger.dart';

/// Sends in-game invites via the VRChat API.
class InviteService {
  final VrchatDart _api;

  InviteService(this._api);

  Future<void> inviteSelfToInstance(Instance instance) async {
    try {
      await _api.rawApi.getInviteApi().inviteMyselfTo(
        worldId: instance.worldId,
        instanceId: instance.instanceId,
      );
      AppLogger.info(
        'Sent self-invite to ${instance.worldId}:${instance.instanceId}',
        subCategory: 'invite',
      );
    } catch (e, s) {
      if (e is DioException) {
        AppLogger.error(
          'Failed to send self-invite',
          subCategory: 'invite',
          error: {
            'type': e.type.toString(),
            'message': e.message,
            'statusCode': e.response?.statusCode,
            'uri': e.requestOptions.uri.toString(),
          },
          stackTrace: s,
        );
      } else {
        AppLogger.error(
          'Failed to send self-invite',
          subCategory: 'invite',
          error: e,
          stackTrace: s,
        );
      }
    }
  }
}
