import 'package:flutter/material.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'status_colors.dart';

extension UserStatusExtension on UserStatus {
  IconData get icon {
    switch (this) {
      case UserStatus.askMe:
      case UserStatus.busy:
      case UserStatus.joinMe:
        return Icons.circle;
      case UserStatus.offline:
        return Icons.offline_bolt;
      case UserStatus.active:
        return Icons.play_circle;
    }
  }

  String get text {
    switch (this) {
      case UserStatus.active:
        return 'Active';
      case UserStatus.askMe:
        return 'Ask Me';
      case UserStatus.busy:
        return 'Busy';
      case UserStatus.joinMe:
        return 'Join Me';
      case UserStatus.offline:
        return 'Offline';
    }
  }

  Color getColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColors = Theme.of(context).extension<StatusColors>();

    switch (this) {
      case UserStatus.active:
        return statusColors?.active ?? scheme.primary;
      case UserStatus.askMe:
        return statusColors?.askMe ?? scheme.tertiary;
      case UserStatus.busy:
        return statusColors?.busy ?? scheme.error;
      case UserStatus.joinMe:
        return statusColors?.joinMe ?? scheme.secondary;
      case UserStatus.offline:
        return statusColors?.offline ?? scheme.outline;
    }
  }
}
