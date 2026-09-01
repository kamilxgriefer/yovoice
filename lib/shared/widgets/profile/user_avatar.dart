import 'package:flutter/material.dart';

import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/shared/widgets/profile/premium_avatar_frame.dart';
import 'package:yovoice/shared/widgets/profile/profile_media_image.dart';

/// The one way to render a user's avatar.
///
/// Replaces the ad-hoc `CircleAvatar(backgroundImage: NetworkImage(...))`
/// pattern, which has no error state: a broken or revoked URL painted an
/// empty purple disc with no fallback. This widget always resolves to
/// something intentional — image, or initial on brand color — and fades
/// the image in instead of popping.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    required this.radius,
    this.userId,
    this.photoUrl,
    this.mediaRevision,
    this.mediaService,
    this.displayName,
    this.backgroundColor = const Color(0xFF64258E),
    this.fallbackIcon,
    this.premium = false,
    super.key,
  });

  final double radius;

  /// Canonical identity used by the viewer-authorized media resolver.
  final String? userId;

  /// Legacy display hint retained for source compatibility. It is never
  /// dereferenced: durable/external URLs copied into denormalized snapshots
  /// must not bypass live profile visibility or block checks.
  final String? photoUrl;
  final Object? mediaRevision;
  final ProfileMediaService? mediaService;
  final String? displayName;
  final Color backgroundColor;

  /// Shown when there is no usable image AND no name to take an initial
  /// from (e.g. Home's header before the profile stream emits).
  final IconData? fallbackIcon;

  /// Wraps the avatar in the canonical [PremiumAvatarFrame]. Callers pass
  /// `profile.premiumIdentity` — the server-written public mirror of the
  /// entitlement — never a locally computed flag.
  final bool premium;

  String get _initial {
    final name = displayName?.trim() ?? '';
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;

    Widget fallback() {
      if (fallbackIcon != null && (displayName?.trim().isEmpty ?? true)) {
        return Icon(fallbackIcon, color: Colors.white, size: radius);
      }
      return Text(
        _initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: radius * 0.9,
        ),
      );
    }

    final avatar = ClipOval(
      child: Container(
        width: diameter,
        height: diameter,
        color: backgroundColor,
        alignment: Alignment.center,
        child: ProfileMediaImage(
          userId: userId,
          kind: ProfileMediaKind.avatar,
          fit: BoxFit.cover,
          fallback: fallback(),
          service: mediaService,
          revision: mediaRevision,
        ),
      ),
    );

    if (!premium) return avatar;
    return PremiumAvatarFrame(child: avatar);
  }
}
