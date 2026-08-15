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
  // Identity badges
  // =========================
  // The official-role palette. One color per role in the staff
  // vocabulary, plus VIP — an entitlement rendered separately, never a
  // role. Referenced only through OfficialRoleBadge/VipBadge; no surface
  // may define its own role color.

  static const Color roleUser = Color(0xFF9189A6);
  static const Color roleGuideMaster = Color(0xFF35E58D);
  static const Color roleSupport = Color(0xFF38BDF8);
  static const Color roleAuditor = Color(0xFF818CF8);
  static const Color roleModerator = Color(0xFFA855F7);
  static const Color roleSuperModerator = Color(0xFFFF6B81);
  static const Color roleOwner = Color(0xFFFF3344);
  static const Color vipGold = Color(0xFFFFD166);

  // =========================
  // Misc
  // =========================

  static const Color white = Colors.white;
  static const Color black = Colors.black;
  static const Color transparent = Colors.transparent;
}
