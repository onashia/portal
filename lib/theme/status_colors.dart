import 'package:flutter/material.dart';

@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  final Color active;
  final Color askMe;
  final Color busy;
  final Color joinMe;
  final Color offline;

  const StatusColors({
    required this.active,
    required this.askMe,
    required this.busy,
    required this.joinMe,
    required this.offline,
  });

  @override
  StatusColors copyWith({
    Color? active,
    Color? askMe,
    Color? busy,
    Color? joinMe,
    Color? offline,
  }) {
    return StatusColors(
      active: active ?? this.active,
      askMe: askMe ?? this.askMe,
      busy: busy ?? this.busy,
      joinMe: joinMe ?? this.joinMe,
      offline: offline ?? this.offline,
    );
  }

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) {
      return this;
    }
    return StatusColors(
      active: Color.lerp(active, other.active, t) ?? active,
      askMe: Color.lerp(askMe, other.askMe, t) ?? askMe,
      busy: Color.lerp(busy, other.busy, t) ?? busy,
      joinMe: Color.lerp(joinMe, other.joinMe, t) ?? joinMe,
      offline: Color.lerp(offline, other.offline, t) ?? offline,
    );
  }
}
