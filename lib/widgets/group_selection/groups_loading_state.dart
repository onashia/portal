import 'package:flutter/material.dart';

import '../common/loading_state.dart';

class GroupsLoadingState extends StatelessWidget {
  const GroupsLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const LoadingState(
      semanticLabel: 'Loading available groups',
      message: 'Loading available groups...',
    );
  }
}
