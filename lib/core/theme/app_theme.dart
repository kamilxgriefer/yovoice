import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_palette.dart';
import 'app_radius.dart';
import 'app_sizing.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  static WidgetStateProperty<Color?> _overlayColor(
    Color primary,
    AppPalette palette,
  ) => WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
    if (states.contains(WidgetState.pressed)) {
      return primary.withValues(alpha: 0.16);
    }
    if (states.contains(WidgetState.hovered)) {
      return primary.withValues(alpha: 0.08);
    }
    if (states.contains(WidgetState.focused)) {
      return palette.focus.withValues(alpha: 0.12);
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
          errorContainer: palette.dangerSurface,
          onErrorContainer: palette.dangerForeground,
          onSurface: palette.textPrimary,
          onSurfaceVariant: palette.textSecondary,
          outline: palette.borderStrong,
          outlineVariant: palette.border,
          surfaceBright: palette.surfaceRaised,
          surfaceDim: palette.surfaceSunken,
          surfaceTint: Colors.transparent,
          surfaceContainerLowest: palette.surfaceSunken,
          surfaceContainerLow: palette.surfaceMuted,
          surfaceContainer: palette.surface,
          surfaceContainerHigh: palette.surfaceRaised,
          surfaceContainerHighest: palette.surfaceRaised,
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
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: palette.background,
      colorScheme: colorScheme,
      textTheme: baseTextTheme,
      dividerColor: palette.border,
      cardColor: palette.surface,
      canvasColor: palette.background,
      extensions: <ThemeExtension<dynamic>>[palette],
      iconTheme: IconThemeData(color: palette.textSecondary),
      focusColor: palette.focus.withValues(alpha: .14),
      hoverColor: primary.withValues(alpha: .08),
      disabledColor: palette.textTertiary,
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
          minimumSize: const WidgetStatePropertyAll(
            Size(AppSizing.minimumTouchTarget, AppSizing.standardControlHeight),
          ),
          overlayColor: _overlayColor(primary, palette),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.disabled)
                ? palette.textTertiary
                : Colors.white;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.disabled)
                ? palette.surfaceSunken
                : primary;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: colorScheme.onPrimary, width: 2);
            }
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(color: palette.border);
            }
            return BorderSide.none;
          }),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(AppSizing.minimumTouchTarget, AppSizing.standardControlHeight),
          ),
          overlayColor: _overlayColor(primary, palette),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.disabled)
                ? palette.textTertiary
                : Colors.white;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.disabled)
                ? palette.surfaceSunken
                : primary;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: colorScheme.onPrimary, width: 2);
            }
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(color: palette.border);
            }
            return BorderSide.none;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(AppSizing.minimumTouchTarget, AppSizing.standardControlHeight),
          ),
          overlayColor: _overlayColor(primary, palette),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.disabled)
                ? palette.textTertiary
                : palette.interactiveForeground;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: palette.focus, width: 2);
            }
            return BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? palette.border
                  : palette.borderStrong,
            );
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(AppSizing.minimumTouchTarget, AppSizing.standardControlHeight),
          ),
          overlayColor: _overlayColor(primary, palette),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.disabled)
                ? palette.textTertiary
                : palette.interactiveForeground;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: palette.focus, width: 2);
            }
            return BorderSide.none;
          }),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.md),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size.square(AppSizing.minimumTouchTarget),
          ),
          overlayColor: _overlayColor(primary, palette),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.disabled)
                ? palette.textTertiary
                : palette.textPrimary;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: palette.focus, width: 2);
            }
            return BorderSide.none;
          }),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.md),
          ),
        ),
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
          borderSide: BorderSide(color: palette.focus, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: error, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.md,
          borderSide: BorderSide(color: palette.border),
        ),
        errorStyle: baseTextTheme.bodySmall?.copyWith(
          color: palette.dangerForeground,
        ),
        helperStyle: baseTextTheme.bodySmall?.copyWith(
          color: palette.textSecondary,
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
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceMuted,
        disabledColor: palette.surfaceSunken,
        selectedColor: colorScheme.primaryContainer,
        secondarySelectedColor: colorScheme.secondaryContainer,
        checkmarkColor: colorScheme.onPrimaryContainer,
        labelStyle: baseTextTheme.labelLarge?.copyWith(
          color: palette.textPrimary,
        ),
        secondaryLabelStyle: baseTextTheme.labelLarge?.copyWith(
          color: colorScheme.onSecondaryContainer,
        ),
        side: BorderSide(color: palette.borderStrong),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pill),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return palette.textTertiary;
          }
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onPrimary;
          }
          return palette.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return palette.surfaceSunken;
          }
          if (states.contains(WidgetState.selected)) return primary;
          return palette.surfaceMuted;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) return palette.focus;
          if (states.contains(WidgetState.disabled)) return palette.border;
          return palette.borderStrong;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return palette.surfaceSunken;
          }
          if (states.contains(WidgetState.selected)) return primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(colorScheme.onPrimary),
        side: BorderSide(color: palette.borderStrong, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return palette.textTertiary;
          }
          if (states.contains(WidgetState.selected)) return primary;
          return palette.textSecondary;
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: palette.interactiveForeground,
        unselectedLabelColor: palette.textSecondary,
        indicatorColor: palette.interactiveForeground,
        dividerColor: palette.border,
        overlayColor: _overlayColor(primary, palette),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: AppRadius.sm,
        ),
        textStyle: baseTextTheme.bodySmall?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
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
      systemNavigationBarDividerColor: palette.navigationOutline,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );
  }
}
