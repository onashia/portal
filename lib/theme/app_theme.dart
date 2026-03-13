import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import 'side_sheet_theme.dart';
import 'status_colors.dart';
import 'vrchat_status_colors.dart';

const double _sideSheetElevation = 8.0;
const double _sideSheetOutlineAlphaLight = 0.50;
const double _sideSheetOutlineAlphaDark = 0.65;

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
    final sideSheetOutlineAlpha = brightness == Brightness.dark
        ? _sideSheetOutlineAlphaDark
        : _sideSheetOutlineAlphaLight;

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
      extensions: <ThemeExtension<dynamic>>[
        // Material 500-level saturated tones to match VRChat's in-app status
        // indicator colors. These are primary, attention-worthy UI elements
        // (user availability) so higher saturation is intentional.
        StatusColors(
          active: const Color(0xFF4CAF50), // green
          askMe: const Color(0xFFFF9800), // orange
          busy: const Color(0xFFF44336), // red
          joinMe: const Color(0xFF2196F3), // blue
          offline: const Color(0xFF9E9E9E), // grey
        ),
        // Material 300-level muted tones — intentionally softer than
        // StatusColors above. VRChat API health is ambient/informational,
        // not a primary action-driving signal, so lower saturation keeps
        // these indicators visually subordinate.
        VrchatStatusColors(
          operational: const Color(0xFF81C784), // green
          degraded: const Color(0xFFFFB74D), // orange/yellow
          outage: const Color(0xFFE57373), // red
        ),
        SideSheetTheme(
          containerColor: scheme.surfaceContainerHigh,
          outlineColor: scheme.outlineVariant.withValues(
            alpha: sideSheetOutlineAlpha,
          ),
          elevation: _sideSheetElevation,
          shadowColor: scheme.shadow,
        ),
      ],
      textTheme: textTheme,
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: shapes.round.sm,
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
        waitDuration: const Duration(milliseconds: 500),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
        thickness: 1,
        space: 1,
      ),
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
