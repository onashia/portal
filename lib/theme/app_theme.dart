import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

class AppTheme {
  static ThemeData lightTheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF63A002),
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    brightness: Brightness.light,
  ).toM3EThemeData();

  static ThemeData darkTheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF63A002),
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    brightness: Brightness.dark,
  ).toM3EThemeData();
}
