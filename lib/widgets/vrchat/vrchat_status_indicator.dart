import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/vrchat_status_provider.dart';
import 'vrchat_status_compact_view.dart';
import 'vrchat_status_dialog.dart';

class VrchatStatusWidget extends ConsumerWidget {
  const VrchatStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusState = ref.watch(vrchatStatusProvider);
    final state = statusState.value;

    return VrchatStatusCompactView(
      state: state,
      onTap: () => _showStatusDialog(context, state),
    );
  }

  void _showStatusDialog(BuildContext context, VrchatStatusState? state) {
    if (state == null || state.status == null) {
      return;
    }

    showVrchatStatusDialog(context, state.status!);
  }
}
