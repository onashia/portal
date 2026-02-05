import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

class AppTheme {
  static ThemeData lightTheme = _buildTheme(Brightness.light);

  static ThemeData darkTheme = _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF63A002),
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
      brightness: brightness,
    );

    final m3e = M3ETheme.defaults(scheme);
    final base = scheme.toM3EThemeData(override: m3e);
    final shapes = m3e.shapes;
    final spacing = m3e.spacing;
    final textTheme = m3e.typography.base;

    final inputBorder = OutlineInputBorder(
      borderRadius: shapes.square.lg,
      borderSide: BorderSide(color: scheme.surfaceContainerHighest, width: 1),
    );

    final focusedBorder = OutlineInputBorder(
      borderRadius: shapes.square.lg,
      borderSide: BorderSide(color: scheme.primary, width: 2),
    );

    final errorBorder = OutlineInputBorder(
      borderRadius: shapes.square.lg,
      borderSide: BorderSide(color: scheme.error, width: 2),
    );

    return base.copyWith(
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: shapes.round.md),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: EdgeInsets.symmetric(
          horizontal: spacing.lg,
          vertical: spacing.md,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: focusedBorder,
        errorBorder: errorBorder,
        focusedErrorBorder: errorBorder,
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        labelStyle: textTheme.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        floatingLabelStyle: textTheme.bodyLarge?.copyWith(
          color: scheme.primary,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
