import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/shared/widgets/profile/premium_avatar_frame.dart';
import 'package:yovoice/shared/widgets/profile/profile_media_image.dart';

/// How a [UserAvatar] is finished.
///
/// * [flat] — today's disc, pixel for pixel (the default: the desktop rail's
///   profile card and the profile hero keep it).
/// * [brand] — refine-look R10: the one letter-avatar gradient, a calmer
///   w700 initial and a hairline ring. Opt in per call site.
enum UserAvatarFinish { flat, brand }

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
    this.backgroundColor = defaultFill,
    this.fallbackIcon,
    this.premium = false,
    this.finish = UserAvatarFinish.flat,
    super.key,
  });

  /// The flat finish's default disc (unchanged since the widget shipped).
  /// Under [UserAvatarFinish.brand] this default means "no custom fill" and
  /// resolves to [AppGradients.letterAvatar].
  static const Color defaultFill = Color(0xFF64258E);

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

  /// [UserAvatarFinish.flat] (default, unchanged) or the R10 brand finish.
  final UserAvatarFinish finish;

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
    if (finish == UserAvatarFinish.brand) {
      final avatar = _BrandAvatar(
        radius: radius,
        userId: userId,
        mediaRevision: mediaRevision,
        mediaService: mediaService,
        displayName: displayName,
        initial: _initial,
        backgroundColor: backgroundColor,
        fallbackIcon: fallbackIcon,
      );
      return premium ? PremiumAvatarFrame(child: avatar) : avatar;
    }
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

/// The R10 brand finish (refine-look §3).
///
/// * Fill: the default fill becomes [AppGradients.letterAvatar]; an opaque
///   custom fill gets a soft top light ([fill + white .14] → fill, from
///   (-.6, -.8) to (.6, .8)); a translucent identity fill stays flat.
/// * Initial: w700 at .38 × the diameter, -.3 tracking, never text-scaled,
///   with a faint drop shadow from 40 px up.
/// * Ring (1 px): letters get white @ .08 in Dark and none in Pearl; photos
///   get `palette.hairline` in both themes. Which one shows is decided by
///   whether the fallback is actually on screen, so a photo that fails to
///   load swaps to the letter ring with it.
class _BrandAvatar extends StatefulWidget {
  const _BrandAvatar({
    required this.radius,
    required this.userId,
    required this.mediaRevision,
    required this.mediaService,
    required this.displayName,
    required this.initial,
    required this.backgroundColor,
    required this.fallbackIcon,
  });

  final double radius;
  final String? userId;
  final Object? mediaRevision;
  final ProfileMediaService? mediaService;
  final String? displayName;
  final String initial;
  final Color backgroundColor;
  final IconData? fallbackIcon;

  @override
  State<_BrandAvatar> createState() => _BrandAvatarState();
}

class _BrandAvatarState extends State<_BrandAvatar> {
  /// True while the letter (or icon) fallback is mounted.
  final ValueNotifier<bool> _showsFallback = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _showsFallback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final diameter = widget.radius * 2;
    final fill = widget.backgroundColor;
    final usesLetterGradient = fill == UserAvatar.defaultFill;
    final opaque = fill.a >= 1;

    final Decoration decoration;
    final Color resolvedFill;
    if (usesLetterGradient) {
      decoration = BoxDecoration(gradient: AppGradients.letterAvatar);
      resolvedFill = AppGradients.letterAvatar.colors.first;
    } else if (opaque) {
      decoration = BoxDecoration(
        gradient: LinearGradient(
          begin: const Alignment(-.6, -.8),
          end: const Alignment(.6, .8),
          colors: [Color.lerp(fill, AppColors.white, .14)!, fill],
        ),
      );
      resolvedFill = fill;
    } else {
      decoration = BoxDecoration(color: fill);
      resolvedFill = Color.alphaBlend(
        fill,
        Theme.of(context).colorScheme.surface,
      );
    }
    final onFill =
        ThemeData.estimateBrightnessForColor(resolvedFill) == Brightness.light
        ? AppColors.contrastInk
        : AppColors.white;

    final Widget mark =
        widget.fallbackIcon != null &&
            (widget.displayName?.trim().isEmpty ?? true)
        ? Icon(widget.fallbackIcon, color: onFill, size: widget.radius)
        : Text(
            widget.initial,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              color: onFill,
              fontWeight: FontWeight.w700,
              fontSize: diameter * .38,
              letterSpacing: -.3,
              height: 1.1,
              shadows: diameter >= 40
                  ? <Shadow>[
                      Shadow(
                        color: AppColors.black.withValues(alpha: .25),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
          );

    final letterRing = palette.isDark
        ? AppColors.white.withValues(alpha: .08)
        : null;

    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipOval(
            child: DecoratedBox(
              decoration: decoration,
              child: Center(
                child: ProfileMediaImage(
                  userId: widget.userId,
                  kind: ProfileMediaKind.avatar,
                  fit: BoxFit.cover,
                  fallback: _FallbackPresence(
                    notifier: _showsFallback,
                    child: ExcludeSemantics(child: mark),
                  ),
                  service: widget.mediaService,
                  revision: widget.mediaRevision,
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _AvatarRingPainter(
                showsFallback: _showsFallback,
                letterRing: letterRing,
                photoRing: palette.hairline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reports whether the fallback is on screen to the ring painter.
class _FallbackPresence extends StatefulWidget {
  const _FallbackPresence({required this.notifier, required this.child});

  final ValueNotifier<bool> notifier;
  final Widget child;

  @override
  State<_FallbackPresence> createState() => _FallbackPresenceState();
}

class _FallbackPresenceState extends State<_FallbackPresence> {
  @override
  void initState() {
    super.initState();
    widget.notifier.value = true;
  }

  @override
  void dispose() {
    widget.notifier.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A 1 px ring that repaints (never rebuilds) when the fallback appears or
/// goes: the letter ring while it is shown, the photo hairline otherwise.
class _AvatarRingPainter extends CustomPainter {
  _AvatarRingPainter({
    required this.showsFallback,
    required this.letterRing,
    required this.photoRing,
  }) : super(repaint: showsFallback);

  final ValueNotifier<bool> showsFallback;
  final Color? letterRing;
  final Color photoRing;

  @override
  void paint(Canvas canvas, Size size) {
    final color = showsFallback.value ? letterRing : photoRing;
    if (color == null) return;
    canvas.drawOval(
      (Offset.zero & size).deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_AvatarRingPainter oldDelegate) =>
      oldDelegate.showsFallback != showsFallback ||
      oldDelegate.letterRing != letterRing ||
      oldDelegate.photoRing != photoRing;
}
