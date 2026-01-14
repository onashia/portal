import 'package:flutter/material.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

class GroupUtils {
  static String getInitials(LimitedUserGroups group) {
    if (group.name != null && group.name!.isNotEmpty) {
      final parts = group.name!.split(' ');
      if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
        return (parts[0][0] + parts[1][0]).toUpperCase();
      } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
        final name = parts[0];
        return name.substring(0, name.length > 1 ? 2 : 1).toUpperCase();
      }
    }
    if (group.discriminator != null &&
        group.discriminator!.isNotEmpty) {
      return group.discriminator!.toUpperCase();
    }
    if (group.groupId != null && group.groupId!.isNotEmpty) {
      return group.groupId!.substring(0, 4).toUpperCase();
    }
    return 'GRP';
  }

  static Color getAvatarColor(LimitedUserGroups group) {
    final name = group.name ?? '';
    final discriminator = group.discriminator ?? '';

    String? inputString;
    if (name.isNotEmpty) {
      inputString = name;
    } else if (discriminator.isNotEmpty) {
      inputString = discriminator;
    } else if (group.groupId != null) {
      inputString = group.groupId;
    }

    if (inputString == null) {
      return Colors.grey;
    }

    final hash = inputString.hashCode;
    final hue = (hash.abs() % 360).toDouble();

    return HSLColor.fromAHSL(1.0, hue / 360, 0.7, 0.6).toColor();
  }
}
