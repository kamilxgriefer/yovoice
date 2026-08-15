import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';

/// String-keyed access to the role palette for MANAGEMENT surfaces
/// (Staff Center works with raw role values, where a non-owner
/// `superAdmin` legitimately reads SUPER ADMIN rather than the owner
/// badge). Public identity everywhere else renders through
/// OfficialRoleBadge/VipBadge. The colors themselves live in [AppColors]
/// — the one palette source — and are only aliased here.
abstract final class RoleIdentity {
  static const ownerColor = AppColors.roleOwner; // crimson
  static const superModeratorColor = AppColors.roleSuperModerator; // coral
  static const moderatorColor = AppColors.roleModerator; // violet
  static const auditorColor = AppColors.roleAuditor; // indigo
  static const supportColor = AppColors.roleSupport; // cyan
  static const guideMasterColor = AppColors.roleGuideMaster; // emerald
  static const vipColor = AppColors.vipGold; // gold
  static const userColor = AppColors.roleUser; // neutral

  /// The colour a role wears. The owner outranks the plain superAdmin
  /// label — ownership is confirmed by the server, never assumed here.
  static Color colorFor(String staffRole, {bool isOwner = false}) {
    if (isOwner) return ownerColor;
    return switch (staffRole) {
      'superAdmin' => ownerColor,
      'superModerator' => superModeratorColor,
      'moderator' => moderatorColor,
      'auditor' => auditorColor,
      'support' => supportColor,
      'guideMaster' => guideMasterColor,
      _ => userColor,
    };
  }

  /// The display label. The confirmed owner reads OWNER · SUPER ADMIN —
  /// the distinction the capability model is built on.
  static String labelFor(String staffRole, {bool isOwner = false}) {
    if (isOwner) return 'OWNER · SUPER ADMIN';
    return switch (staffRole) {
      'superAdmin' => 'SUPER ADMIN',
      'superModerator' => 'SUPER MODERATOR',
      'moderator' => 'MODERATOR',
      'auditor' => 'AUDITOR',
      'support' => 'SUPPORT',
      'guideMaster' => 'GUIDE MASTER',
      _ => '',
    };
  }
}
