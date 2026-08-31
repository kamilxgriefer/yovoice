import 'package:flutter/material.dart';

/// Theme-invariant brand, status, identity and primitive colours.
///
/// Brightness-dependent canvas, surface, copy, navigation and interaction
/// roles belong to `AppPalette`; complete immersive-dark routes use
/// `AppImmersiveColors`. The neutral primitives at the bottom are deliberate
/// paint atoms, not substitutes for semantic theme roles.

class AppColors {
  AppColors._();

  // =========================
  // Brand
  // =========================

  static const Color primary = Color(0xFF7B2FF7);
  static const Color secondary = Color(0xFFC026FF);
  static const Color navigationPrimary = Color(0xFF8A2BE2);
  static const Color accent = Color(0xFF5CE1E6);

  /// Readable ink for bright, saturated brand/status fills.
  ///
  /// This is deliberately brightness-independent: custom accent surfaces
  /// (for example a live-room category or an active recording control) use
  /// it only after determining that their fill is light enough to need dark
  /// foreground content.
  static const Color contrastInk = Color(0xFF211629);

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
  static const Color onLive = Color(0xFF16040A);

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
