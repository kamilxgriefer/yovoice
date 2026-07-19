import 'package:flutter/material.dart';

/// Centralne miejsce definiowania kolorów aplikacji.
/// Nie używamy Color(...) bezpośrednio w widgetach.

class AppColors {
  AppColors._();

  // =========================
  // Brand
  // =========================

  static const Color primary = Color(0xFF7B2FF7);
  static const Color secondary = Color(0xFFC026FF);
  static const Color accent = Color(0xFF5CE1E6);

  // =========================
  // Backgrounds
  // =========================

  static const Color background = Color(0xFF0D0618);
  static const Color surface = Color(0xFF191329);
  static const Color surfaceLight = Color(0xFF241B39);

  // =========================
  // Text
  // =========================

  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFB4ADC8);
  static const Color textHint = Color(0xFF7E7895);

  // =========================
  // Borders
  // =========================

  static const Color border = Color(0xFF3A3151);
  static const Color divider = Color(0xFF2B233F);

  // =========================
  // Status
  // =========================

  static const Color success = Color(0xFF35D07F);
  static const Color warning = Color(0xFFFFB547);
  static const Color error = Color(0xFFFF5F6D);
  static const Color info = Color(0xFF4DA3FF);

  // =========================
  // Voice
  // =========================

  static const Color voice = Color(0xFF8D5BFF);
  static const Color live = Color(0xFFFF335C);

  // =========================
  // Misc
  // =========================

  static const Color white = Colors.white;
  static const Color black = Colors.black;
  static const Color transparent = Colors.transparent;
}
