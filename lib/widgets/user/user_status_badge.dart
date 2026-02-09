import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../../constants/icon_sizes.dart';
import '../../theme/user_status_extension.dart';

class UserStatusBadge extends StatelessWidget {
  final UserStatus status;

  const UserStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(status.icon, size: IconSizes.xs, color: status.getColor(context)),
        SizedBox(width: context.m3e.spacing.sm),
        Text(
          status.text,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: status.getColor(context)),
        ),
      ],
    );
  }
}
