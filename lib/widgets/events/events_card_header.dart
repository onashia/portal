import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

class EventsCardHeader extends StatelessWidget {
  final String todayLabel;

  const EventsCardHeader({super.key, required this.todayLabel});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Today's Events",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: context.m3e.spacing.xs),
              Text(
                todayLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
