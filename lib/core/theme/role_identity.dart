import 'package:flutter/material.dart';

/// The visual identity of each staff tier and of VIP — colours and labels
/// only. Capabilities come from the server; this file just knows how a
/// role looks once the server has said it exists.
abstract final class RoleIdentity {
  static const ownerColor = Color(0xFFFF3344); // crimson
  static const superModeratorColor = Color(0xFFFF6B81); // coral
  static const moderatorColor = Color(0xFFA855F7); // violet
  static const auditorColor = Color(0xFF818CF8); // indigo
  static const supportColor = Color(0xFF38BDF8); // cyan
  static const guideMasterColor = Color(0xFF35E58D); // emerald
  static const vipColor = Color(0xFFFFD166); // gold
  static const userColor = Color(0xFF9189A6); // neutral

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
