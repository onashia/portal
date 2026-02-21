import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Dedicated visual tokens for side sheets.
///
/// Side sheets represent a higher-emphasis layer than standard dashboard cards,
/// so they use their own container, outline, and elevation semantics.
@immutable
class SideSheetTheme extends ThemeExtension<SideSheetTheme> {
  final Color containerColor;
  final Color outlineColor;
  final double elevation;
  final Color shadowColor;

  const SideSheetTheme({
    required this.containerColor,
    required this.outlineColor,
    required this.elevation,
    required this.shadowColor,
  });

  @override
  SideSheetTheme copyWith({
    Color? containerColor,
    Color? outlineColor,
    double? elevation,
    Color? shadowColor,
  }) {
    return SideSheetTheme(
      containerColor: containerColor ?? this.containerColor,
      outlineColor: outlineColor ?? this.outlineColor,
      elevation: elevation ?? this.elevation,
      shadowColor: shadowColor ?? this.shadowColor,
    );
  }

  @override
  SideSheetTheme lerp(ThemeExtension<SideSheetTheme>? other, double t) {
    if (other is! SideSheetTheme) {
      return this;
    }
    return SideSheetTheme(
      containerColor:
          Color.lerp(containerColor, other.containerColor, t) ?? containerColor,
      outlineColor:
          Color.lerp(outlineColor, other.outlineColor, t) ?? outlineColor,
      elevation: lerpDouble(elevation, other.elevation, t) ?? elevation,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t) ?? shadowColor,
    );
  }
}
