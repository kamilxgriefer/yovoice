import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_palette.dart';
import 'app_radius.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

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

  static ThemeData get darkTheme =>
      _buildTheme(brightness: Brightness.dark, palette: AppPalette.dark);

  static ThemeData get lightTheme =>
      _buildTheme(brightness: Brightness.light, palette: AppPalette.light);

  static ThemeData _buildTheme({
    required Brightness brightness,
    required AppPalette palette,
  }) {
    final isDark = brightness == Brightness.dark;
    final primary = isDark ? AppColors.primary : const Color(0xFF6F1FD1);
    // A slightly deeper magenta than the raw brand swatch keeps white labels
    // AA-safe across the full primary-button gradient in both themes.
    const secondary = Color(0xFFA117D8);
    final error = isDark ? const Color(0xFFFF7B88) : const Color(0xFFB4233F);
    final baseTextTheme = AppTypography.textTheme.apply(
      bodyColor: palette.textPrimary,
      displayColor: palette.textPrimary,
      decorationColor: palette.textPrimary,
    );
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
          primary: primary,
          secondary: secondary,
          surface: palette.surface,
          error: error,
        ).copyWith(
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          tertiary: isDark ? AppColors.accent : const Color(0xFF007C83),
          onTertiary: isDark ? const Color(0xFF002022) : Colors.white,
          onError: isDark ? const Color(0xFF310009) : Colors.white,
          errorContainer: isDark
              ? const Color(0xFF4A1720)
              : const Color(0xFFFDE7EC),
          onErrorContainer: isDark
              ? const Color(0xFFFFD9DE)
              : const Color(0xFF6D1027),
          onSurface: palette.textPrimary,
          onSurfaceVariant: palette.textSecondary,
          outline: palette.borderStrong,
          outlineVariant: palette.border,
          surfaceContainerLowest: palette.background,
          surfaceContainerLow: palette.surfaceRaised,
          surfaceContainer: palette.surface,
          surfaceContainerHigh: palette.surfaceMuted,
          surfaceContainerHighest: palette.surfaceSunken,
          primaryContainer: isDark
              ? primary.withValues(alpha: .24)
              : const Color(0xFFEEDFFF),
          onPrimaryContainer: isDark
              ? palette.textPrimary
              : const Color(0xFF341050),
          secondaryContainer: isDark
              ? secondary.withValues(alpha: .2)
              : const Color(0xFFF6E4FF),
          onSecondaryContainer: isDark
              ? palette.textPrimary
              : const Color(0xFF431050),
          inverseSurface: isDark
              ? AppPalette.light.textPrimary
              : AppPalette.dark.surfaceRaised,
          onInverseSurface: isDark
              ? AppPalette.light.surface
              : AppPalette.dark.textPrimary,
          shadow: palette.shadow,
          scrim: palette.scrim,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: AppTypography.fontFamily,
      scaffoldBackgroundColor: palette.background,
      colorScheme: colorScheme,
      textTheme: baseTextTheme,
      dividerColor: palette.border,
      cardColor: palette.surface,
      canvasColor: palette.background,
      extensions: <ThemeExtension<dynamic>>[palette],
      iconTheme: IconThemeData(color: palette.textSecondary),
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
        style: ButtonStyle(
          overlayColor: _overlayColor,
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          backgroundColor: WidgetStatePropertyAll(primary),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          overlayColor: _overlayColor,
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          backgroundColor: WidgetStatePropertyAll(primary),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          overlayColor: _overlayColor,
          foregroundColor: WidgetStatePropertyAll(primary),
          side: WidgetStatePropertyAll(BorderSide(color: palette.borderStrong)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          overlayColor: _overlayColor,
          foregroundColor: WidgetStatePropertyAll(primary),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(overlayColor: _overlayColor),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 24,
        shadowColor: palette.shadow.withValues(alpha: isDark ? 0.5 : 0.16),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lg),
        titleTextStyle: baseTextTheme.headlineSmall,
        contentTextStyle: baseTextTheme.bodyMedium?.copyWith(
          color: palette.textSecondary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: palette.surfaceRaised,
        modalElevation: 0,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        // Modal surfaces own one explicit, responsive chrome row. Leaving
        // this implicit used to stack a detached framework handle above the
        // handle drawn by custom sheets (most visibly New message).
        showDragHandle: false,
        dragHandleColor: palette.borderStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: palette.textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: baseTextTheme.titleLarge,
        systemOverlayStyle: systemOverlayStyle(brightness, palette),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceRaised,
        hintStyle: baseTextTheme.bodyMedium?.copyWith(
          color: palette.textTertiary,
        ),
        labelStyle: baseTextTheme.bodyMedium?.copyWith(
          color: palette.textSecondary,
        ),
        prefixIconColor: palette.textSecondary,
        suffixIconColor: palette.textSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: palette.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: error, width: 2),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: primary.withValues(alpha: .24),
        selectionHandleColor: primary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: baseTextTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.navigationSurface,
        indicatorColor: AppColors.primary.withValues(alpha: .18),
        labelTextStyle: WidgetStatePropertyAll(
          baseTextTheme.labelMedium?.copyWith(color: palette.textPrimary),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : palette.navigationInactive,
          );
        }),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.textSecondary,
        textColor: palette.textPrimary,
        subtitleTextStyle: baseTextTheme.bodySmall?.copyWith(
          color: palette.textSecondary,
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lg,
          side: BorderSide(color: palette.border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        textStyle: baseTextTheme.bodyMedium,
        elevation: isDark ? 14 : 8,
        shadowColor: palette.shadow.withValues(alpha: isDark ? .5 : .16),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.md,
          side: BorderSide(color: palette.border),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: palette.surfaceSunken,
        circularTrackColor: palette.surfaceSunken,
      ),
    );
  }

  static SystemUiOverlayStyle systemOverlayStyle(
    Brightness brightness,
    AppPalette palette,
  ) {
    final isDark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      // iOS names this property from the status bar background's point of
      // view, so it is intentionally the inverse of Android icon brightness.
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: palette.background,
      systemNavigationBarDividerColor: palette.border,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );
  }
}
