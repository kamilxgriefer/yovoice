import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
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

  /// The first *grapheme cluster*, not the first UTF-16 code unit.
  ///
  /// `name[0]` returns half a surrogate pair for a display name that starts
  /// with an emoji (rendered as a tofu box) and silently drops a decomposed
  /// accent. `characters` is re-exported by `package:flutter/material.dart`.
  String get _initial {
    final name = displayName?.trim() ?? '';
    return name.isEmpty ? '?' : name.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;

    // Eleven list surfaces pass `palette.surfaceSunken` as the fill, which is
    // near-white in Pearl: a white initial on it is invisible. The foreground
    // follows the fill's own brightness — the same estimate Material uses for
    // its foregrounds — so no caller has to know which appearance it is in,
    // and every existing (dark) fill keeps the white it has today.
    //
    // The estimate reads RGB and ignores alpha, so it must be given the
    // colour the user actually sees, not the one the caller passed. Nine
    // Servers surfaces pass `ServerIdentity…iconSurface`, which in Dark is a
    // light accent at 12 % alpha: unblended it reads "light" and the initial
    // was painted in dark ink on a disc that composites to near-black
    // (~1.1:1). `Color.alphaBlend` is the identity for an opaque top colour,
    // so every constant-colour caller — including all eleven `surfaceSunken`
    // ones — resolves exactly as before.
    final resolvedFill = Color.alphaBlend(
      backgroundColor,
      Theme.of(context).colorScheme.surface,
    );
    final onFill =
        ThemeData.estimateBrightnessForColor(resolvedFill) == Brightness.light
        ? AppColors.contrastInk
        : Colors.white;

    // The initial — and the placeholder icon — is decoration. The adjacent
    // name already carries the identity, so leaving the mark in the semantics
    // tree makes a screen reader announce "K, Kamil, online" on every row.
    Widget fallback() {
      final Widget mark =
          fallbackIcon != null && (displayName?.trim().isEmpty ?? true)
          ? Icon(fallbackIcon, color: onFill, size: radius)
          : Text(
              _initial,
              // Sized to the disc, not to the reader's text: at 200 % the
              // scaled glyph outgrew its circle and the ClipOval cropped
              // it. The name beside every avatar carries the scaled text.
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: onFill,
                fontWeight: FontWeight.w900,
                fontSize: radius * 0.9,
              ),
            );
      return ExcludeSemantics(child: mark);
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
