import 'package:flutter/material.dart';

import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// [UserAvatar] plus the identity decoration slot.
///
/// Today it renders exactly what UserAvatar renders (including the
/// existing premium ring, which stays the paid entitlement's frame).
/// [achievementStyle] is the reserved extension point for the
/// Achievement Rank milestone's APPROVED avatar frames: when a style
/// with frame colors arrives through the public identity projection, it
/// draws as an outer ring — cosmetic only, subordinate to and never a
/// substitute for the official role and VIP badges beside the name.
/// Nothing constructs a style yet.
class DecoratedUserAvatar extends StatelessWidget {
  const DecoratedUserAvatar({
    required this.radius,
    this.photoUrl,
    this.displayName,
    this.premium = false,
    this.fallbackIcon,
    this.achievementStyle,
    super.key,
  });

  final double radius;
  final String? photoUrl;
  final String? displayName;
  final bool premium;
  final IconData? fallbackIcon;
  final AchievementStyle? achievementStyle;

  @override
  Widget build(BuildContext context) {
    final avatar = UserAvatar(
      radius: radius,
      photoUrl: photoUrl,
      displayName: displayName,
      premium: premium,
      fallbackIcon: fallbackIcon,
    );

    final frameColors = achievementStyle?.frameColors;
    if (frameColors == null || frameColors.isEmpty) return avatar;

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: frameColors.length > 1
            ? LinearGradient(colors: frameColors)
            : null,
        color: frameColors.length == 1 ? frameColors.single : null,
      ),
      child: avatar,
    );
  }
}
