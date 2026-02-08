import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../user/user_profile_image.dart';
import '../user/user_status_badge.dart';

class DashboardUserCard extends StatelessWidget {
  final CurrentUser currentUser;
  final StreamedCurrentUser? streamedUser;

  const DashboardUserCard({
    super.key,
    required this.currentUser,
    this.streamedUser,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.m3e.spacing.lg),
      child: Row(
        children: [
          UserProfileImage(
            currentUser: currentUser,
            streamedUser: streamedUser,
          ),
          SizedBox(width: context.m3e.spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  streamedUser?.displayName ?? currentUser.displayName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: context.m3e.spacing.xs),
                UserStatusBadge(
                  status: streamedUser?.status ?? currentUser.status,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
