import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';

/// The official-role vocabulary as the PUBLIC badge mirror publishes it.
///
/// Three concepts stay strictly separate across the whole app:
///
///  1. OFFICIAL ROLE — server-authoritative, connected to permissions.
///     This enum is its display form and nothing more: rendering a badge
///     never authorizes anything, and no client value feeds back into a
///     permission decision.
///  2. VIP — an entitlement that coexists with EVERY role (an owner can
///     be VIP, a moderator can be VIP). Deliberately not a member of
///     this enum.
///  3. ACHIEVEMENT RANK — cosmetics only (see [AchievementStyle]); it
///     never appears in this vocabulary and can never imitate it.
///
/// `superAdmin` on the wire is the owner badge: the server publishes it
/// only for the confirmed protected-owner uid (a forged or stale value
/// is demoted server-side before it ever reaches a client).
enum OfficialRole {
  user('user', 'USER'),
  guideMaster('guideMaster', 'GUIDE MASTER'),
  support('support', 'SUPPORT'),
  auditor('auditor', 'AUDITOR'),
  moderator('moderator', 'MODERATOR'),
  superModerator('superModerator', 'SUPER MODERATOR'),
  ownerSuperAdmin('superAdmin', 'OWNER · SUPER ADMIN');

  const OfficialRole(this.wire, this.label);

  /// The value as the publicBadges mirror carries it.
  final String wire;

  /// The exact badge label. Never abbreviated, never re-cased.
  final String label;

  /// Localized presentation copy for the badge.
  ///
  /// [label] deliberately remains the stable English vocabulary used by
  /// diagnostics and compatibility tests. Surfaces render this value instead,
  /// keeping role authorization/wire data entirely separate from UI language.
  String localizedLabel(AppLocalizations copy) => switch (this) {
    OfficialRole.user => copy.text('USER', 'UŻYTKOWNIK'),
    OfficialRole.guideMaster => copy.text('GUIDE MASTER', 'GŁÓWNY PRZEWODNIK'),
    OfficialRole.support => copy.text('SUPPORT', 'WSPARCIE'),
    OfficialRole.auditor => copy.text('AUDITOR', 'AUDYTOR'),
    OfficialRole.moderator => copy.text('MODERATOR', 'MODERATOR'),
    OfficialRole.superModerator => copy.text(
      'SUPER MODERATOR',
      'SUPER MODERATOR',
    ),
    OfficialRole.ownerSuperAdmin => copy.text(
      'OWNER · SUPER ADMIN',
      'WŁAŚCICIEL · SUPERADMIN',
    ),
  };

  /// The authoritative badge color, defined once in the theme.
  Color get color => switch (this) {
    OfficialRole.user => AppColors.roleUser,
    OfficialRole.guideMaster => AppColors.roleGuideMaster,
    OfficialRole.support => AppColors.roleSupport,
    OfficialRole.auditor => AppColors.roleAuditor,
    OfficialRole.moderator => AppColors.roleModerator,
    OfficialRole.superModerator => AppColors.roleSuperModerator,
    OfficialRole.ownerSuperAdmin => AppColors.roleOwner,
  };

  /// Parses a wire value, failing SAFELY: anything unknown — including a
  /// value a future server version might add — renders as USER rather
  /// than guessing at a staff claim.
  static OfficialRole fromWire(String? raw) {
    final value = raw?.trim() ?? '';
    for (final role in OfficialRole.values) {
      if (role.wire == value) return role;
    }
    return OfficialRole.user;
  }
}

/// What everyone is allowed to know about an account's identity: the
/// official role and whether VIP applies. Nothing else crosses the
/// mirror — no email, no ban state, no VIP source.
@immutable
class PublicIdentity {
  const PublicIdentity({required this.role, required this.isVip});

  /// The safe answer whenever resolution fails or hasn't landed yet: an
  /// ordinary user with no VIP. Every account displays at least this.
  static const PublicIdentity fallback = PublicIdentity(
    role: OfficialRole.user,
    isVip: false,
  );

  factory PublicIdentity.fromWire(Map<String, dynamic> data) => PublicIdentity(
    role: OfficialRole.fromWire(data['staffRole'] as String?),
    isVip: data['isVip'] == true,
  );

  final OfficialRole role;
  final bool isVip;

  @override
  bool operator ==(Object other) =>
      other is PublicIdentity && other.role == role && other.isVip == isVip;

  @override
  int get hashCode => Object.hash(role, isVip);
}

/// The cosmetic an achievement title produces (Achievement Rank milestone).
///
/// Constructed today by `achievementStyleFor` in the achievements feature
/// from the signed-in account's own `selectedTitleId` — the server-
/// validated selection (`selectMyAchievementTitle` refuses a title that is
/// not unlocked). It decorates SELF-FACING surfaces only until the public
/// identity projection carries the selection for other viewers. The
/// contract it honors:
///
///  * changes ONLY cosmetic rank text, rank color and the avatar frame;
///  * never touches the official role badge, the VIP badge, permissions
///    or moderation capabilities — official badges always render first
///    and cannot be replaced or restyled by a cosmetic;
///  * labels can never use reserved names (Owner, Admin, Moderator,
///    Support, or any official role variant) — enforced server-side at
///    selection time, not trusted from a client;
///  * removing or invalidating the achievement resets the style safely
///    (absence of a style is always valid);
///  * other users receive it through the public identity projection,
///    never from client-supplied fields.
@immutable
class AchievementStyle {
  const AchievementStyle({
    this.rankLabel,
    this.rankColor,
    this.frameColors,
    this.frameAsset,
  });

  /// Custom achievement rank text (cosmetic only, reserved-name checked
  /// server-side).
  final String? rankLabel;

  /// Rank text color.
  final Color? rankColor;

  /// Approved avatar-frame color/gradient stops.
  final List<Color>? frameColors;

  /// Approved avatar-frame asset or effect identifier.
  final String? frameAsset;
}
