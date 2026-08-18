import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  static const _lightBackground = Color(0xFFF8F5FC);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurfaceVariant = Color(0xFFF0EAF6);
  static const _lightBorder = Color(0xFFD8CDE2);
  static const _lightText = Color(0xFF21172A);
  static const _lightMuted = Color(0xFF685B72);

  static WidgetStateProperty<Color?> get _overlayColor =>
      WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
        if (states.contains(WidgetState.pressed)) {
          return AppColors.primary.withValues(alpha: 0.18);
        }
        if (states.contains(WidgetState.hovered)) {
          return AppColors.primary.withValues(alpha: 0.08);
        }
        if (states.contains(WidgetState.focused)) {
          return AppColors.primary.withValues(alpha: 0.1);
        }
        return null;
      });

  static ThemeData get darkTheme => _buildTheme(
    brightness: Brightness.dark,
    background: AppColors.background,
    surface: AppColors.surface,
    surfaceVariant: AppColors.surfaceLight,
    border: AppColors.border,
    divider: AppColors.divider,
    text: AppColors.textPrimary,
    muted: AppColors.textSecondary,
    hint: AppColors.textHint,
  );

  static ThemeData get lightTheme => _buildTheme(
    brightness: Brightness.light,
    background: _lightBackground,
    surface: _lightSurface,
    surfaceVariant: _lightSurfaceVariant,
    border: _lightBorder,
    divider: const Color(0xFFE5DCEB),
    text: _lightText,
    muted: _lightMuted,
    hint: const Color(0xFF897B92),
  );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceVariant,
    required Color border,
    required Color divider,
    required Color text,
    required Color muted,
    required Color hint,
  }) {
    final isDark = brightness == Brightness.dark;
    final baseTextTheme = AppTypography.textTheme.apply(
      bodyColor: text,
      displayColor: text,
      decorationColor: text,
    );
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: surface,
          error: AppColors.error,
        ).copyWith(
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: text,
          outline: border,
          outlineVariant: divider,
          surfaceContainer: surface,
          surfaceContainerLow: background,
          surfaceContainerHigh: surfaceVariant,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: AppTypography.fontFamily,
      scaffoldBackgroundColor: background,
      colorScheme: colorScheme,
      textTheme: baseTextTheme,
      dividerColor: divider,
      cardColor: surface,
      canvasColor: background,
      splashColor: AppColors.primary.withValues(alpha: 0.12),
      highlightColor: AppColors.primary.withValues(alpha: 0.06),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(overlayColor: _overlayColor),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(overlayColor: _overlayColor),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(overlayColor: _overlayColor),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(overlayColor: _overlayColor),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(overlayColor: _overlayColor),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 24,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lg),
        titleTextStyle: baseTextTheme.headlineSmall,
        contentTextStyle: baseTextTheme.bodyMedium?.copyWith(color: muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        modalElevation: 0,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        showDragHandle: true,
        dragHandleColor: border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: baseTextTheme.titleLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: baseTextTheme.bodyMedium?.copyWith(color: hint),
        labelStyle: baseTextTheme.bodyMedium?.copyWith(color: muted),
        prefixIconColor: muted,
        suffixIconColor: muted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: AppColors.error, width: 2),
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: Color(0x667B2FF7),
        selectionHandleColor: AppColors.primary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceVariant,
        contentTextStyle: baseTextTheme.bodyMedium?.copyWith(color: text),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: AppColors.primary.withValues(alpha: .18),
        labelTextStyle: WidgetStatePropertyAll(
          baseTextTheme.labelMedium?.copyWith(color: text),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : muted,
          );
        }),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: text,
        subtitleTextStyle: baseTextTheme.bodySmall?.copyWith(color: muted),
      ),
    );
  }
}
