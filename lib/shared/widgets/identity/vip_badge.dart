import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';

/// The VIP entitlement badge — always rendered AFTER the official role
/// badge and never instead of it. VIP is not a role: a moderator stays a
/// moderator and additionally shows VIP; the owner shows
/// `OWNER · SUPER ADMIN` `VIP`.
class VipBadge extends StatelessWidget {
  const VipBadge({this.variant = IdentityBadgeVariant.full, super.key});

  final IdentityBadgeVariant variant;

  static const String label = 'VIP';

  @override
  Widget build(BuildContext context) {
    return IdentityBadgePill(
      label: label,
      color: AppColors.vipGold,
      icon: Icons.diamond_rounded,
      variant: variant,
    );
  }
}
