import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/shared/identity/public_identity.dart';

/// How much room the surface has for a badge. None of the variants ever
/// hides the official role — the tightest one shrinks to an icon that
/// still names the role in its tooltip.
enum IdentityBadgeVariant {
  /// Label pill — profile headers, sheets, management screens.
  full,

  /// Smaller label pill — list tiles, chat message rows.
  compact,

  /// Icon-only dot with the label in a tooltip — the narrowest surfaces
  /// (stage tiles, dense rails) where even a compact pill would clip.
  icon,
}

/// The one rendering of an official role badge.
///
/// Every surface in the app shows roles through this widget: the label
/// and color come from [OfficialRole] alone, so no screen can drift its
/// own vocabulary or palette. Rendering is display only — the badge
/// never gates anything.
class OfficialRoleBadge extends StatelessWidget {
  const OfficialRoleBadge({
    required this.role,
    this.variant = IdentityBadgeVariant.full,
    super.key,
  });

  final OfficialRole role;
  final IdentityBadgeVariant variant;

  static IconData iconFor(OfficialRole role) => switch (role) {
    OfficialRole.user => Icons.person_rounded,
    OfficialRole.guideMaster => Icons.auto_awesome_rounded,
    OfficialRole.support => Icons.support_agent_rounded,
    OfficialRole.auditor => Icons.fact_check_rounded,
    OfficialRole.moderator => Icons.shield_rounded,
    OfficialRole.superModerator => Icons.local_police_rounded,
    OfficialRole.ownerSuperAdmin => Icons.workspace_premium_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return IdentityBadgePill(
      label: role.localizedLabel(copy),
      color: role.color,
      icon: iconFor(role),
      variant: variant,
    );
  }
}

/// Shared pill/icon chrome for identity badges (official role and VIP).
/// Kept in one place so the two always match in shape and density.
class IdentityBadgePill extends StatelessWidget {
  const IdentityBadgePill({
    required this.label,
    required this.color,
    required this.icon,
    required this.variant,
    super.key,
  });

  final String label;
  final Color color;
  final IconData icon;
  final IdentityBadgeVariant variant;

  Color _foreground(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark) return color;
    // Bright role swatches are excellent accents on Dark, but several are
    // below text contrast on Pearl. Preserve their hue while moving the
    // display foreground into an AA-safe range; the canonical role colour
    // itself remains unchanged and still owns the tint/border.
    return Color.lerp(color, Colors.black, .50)!;
  }

  @override
  Widget build(BuildContext context) {
    final foreground = _foreground(context);
    if (variant == IdentityBadgeVariant.icon) {
      return Tooltip(
        message: label,
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .16),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: .5), width: .8),
          ),
          child: Icon(icon, size: 10, color: foreground),
        ),
      );
    }

    final compact = variant == IdentityBadgeVariant.compact;
    return Container(
      constraints: BoxConstraints(minHeight: compact ? 24 : 28),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 9,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 10 : 12, color: foreground),
          SizedBox(width: compact ? 3 : 4),
          // Flexible so a pill wider than its surface ellipsizes instead
          // of overflowing — the badge itself is the last line of the
          // no-overflow guarantee.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: compact ? 9.5 : 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
