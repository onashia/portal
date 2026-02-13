import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../../providers/auth_provider.dart';
import '../../theme/user_status_extension.dart';
import '../user/user_profile_image.dart';
import '../vrchat/vrchat_status_indicator.dart';

class DashboardUserCard extends ConsumerWidget {
  final CurrentUser currentUser;

  const DashboardUserCard({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streamedUser = ref.watch(authStreamedUserProvider);
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
                            _resolveUserInfoText(streamedUser),
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
                        _resolveUserInfoText(streamedUser),
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

  String _resolveUserInfoText(StreamedCurrentUser? streamedUser) {
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
