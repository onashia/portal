import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

class InstanceLocationRow extends StatelessWidget {
  final String location;

  const InstanceLocationRow({super.key, required this.location});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.location_on,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        SizedBox(width: context.m3e.spacing.xs),
        Expanded(
          child: Text(
            location,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}
