import 'package:flutter/material.dart';

@immutable
class VrchatStatusColors extends ThemeExtension<VrchatStatusColors> {
  final Color operational;
  final Color degraded;
  final Color outage;

  const VrchatStatusColors({
    required this.operational,
    required this.degraded,
    required this.outage,
  });

  @override
  VrchatStatusColors copyWith({
    Color? operational,
    Color? degraded,
    Color? outage,
  }) {
    return VrchatStatusColors(
      operational: operational ?? this.operational,
      degraded: degraded ?? this.degraded,
      outage: outage ?? this.outage,
    );
  }

  @override
  VrchatStatusColors lerp(ThemeExtension<VrchatStatusColors>? other, double t) {
    if (other is! VrchatStatusColors) {
      return this;
    }
    return VrchatStatusColors(
      operational: Color.lerp(operational, other.operational, t) ?? operational,
      degraded: Color.lerp(degraded, other.degraded, t) ?? degraded,
      outage: Color.lerp(outage, other.outage, t) ?? outage,
    );
  }
}
