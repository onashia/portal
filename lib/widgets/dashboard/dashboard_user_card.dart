import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../../theme/user_status_extension.dart';
import '../user/user_profile_image.dart';
import '../vrchat/vrchat_status_indicator.dart';

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 800;

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                            streamedUser?.displayName ??
                                currentUser.displayName,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: context.m3e.spacing.xs),
                          Text(
                            _resolveUserInfoText(),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: context.m3e.spacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: const VrchatStatusWidget(),
                ),
              ],
            );
          } else {
            return Row(
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
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: context.m3e.spacing.xs),
                      Text(
                        _resolveUserInfoText(),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: context.m3e.spacing.md),
                const VrchatStatusWidget(),
              ],
            );
          }
        },
      ),
    );
  }

  String _resolveUserInfoText() {
    final pronouns = currentUser.pronouns;
    final statusDescription =
        streamedUser?.statusDescription ?? currentUser.statusDescription;

    if (pronouns.isNotEmpty && statusDescription.isNotEmpty) {
      return '$pronouns • $statusDescription';
    }

    if (pronouns.isNotEmpty) {
      return pronouns;
    }

    if (statusDescription.isNotEmpty) {
      return statusDescription;
    }

    return (streamedUser?.status ?? currentUser.status).text;
  }
}
