import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/shared/identity/identity_contrast.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Test/inspection handle for the achievement ring painter.
const Key achievementAvatarRingKey = Key('achievement-avatar-ring');

/// [UserAvatar] plus the identity decoration slot.
///
/// Without an [achievementStyle] it renders exactly what UserAvatar renders
/// (including the existing premium ring, which stays the paid entitlement's
/// frame). With a style carrying frame colours it draws the achievement
/// ring as the OUTERMOST ring — outside the Premium frame and outside any
/// brand ring the host adds — cosmetic only, subordinate to and never a
/// substitute for the official role and VIP badges beside the name.
///
/// Today the only producer of a style is the signed-in account's own
/// selected title (`achievementStyleFor` in the achievements feature), so
/// the ring appears on self-facing surfaces only: the profile header, the
/// More sheet identity row and the desktop sidebar card. Other users'
/// avatars stay undecorated until the public identity projection carries
/// the selection.
///
/// [DecoratedUserAvatar.around] decorates an avatar the host already
/// composed (the profile header wraps its brand ring in it) so the
/// achievement ring is guaranteed to be the outer one.
class DecoratedUserAvatar extends StatelessWidget {
  const DecoratedUserAvatar({
    required this.radius,
    this.userId,
    this.photoUrl,
    this.mediaRevision,
    this.displayName,
    this.backgroundColor,
    this.premium = false,
    this.fallbackIcon,
    this.achievementStyle,
    this.ringWidth = 2,
    this.ringGap = 1.5,
    this.surface,
    super.key,
  }) : child = null;

  /// Decorates [child] (an already composed avatar) with the achievement
  /// ring as its outer ring.
  const DecoratedUserAvatar.around({
    required Widget this.child,
    this.achievementStyle,
    this.ringWidth = 2,
    this.ringGap = 1.5,
    this.surface,
    super.key,
  }) : radius = 0,
       userId = null,
       photoUrl = null,
       mediaRevision = null,
       displayName = null,
       backgroundColor = null,
       premium = false,
       fallbackIcon = null;

  final double radius;
  final String? userId;
  final String? photoUrl;
  final Object? mediaRevision;
  final String? displayName;
  final Color? backgroundColor;
  final bool premium;
  final IconData? fallbackIcon;
  final AchievementStyle? achievementStyle;
  final Widget? child;

  /// Stroke width of the achievement ring.
  final double ringWidth;

  /// Transparent breathing room between the avatar (or its inner rings)
  /// and the achievement ring, so two rings never read as one thick band.
  final double ringGap;

  /// The colour the ring sits on. Frame stops are authored for the dark
  /// identity and are lightness-adjusted to keep 3:1 (WCAG non-text
  /// contrast) on whatever surface hosts them — defaults to the theme's
  /// scaffold background.
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    final avatar =
        child ??
        UserAvatar(
          radius: radius,
          userId: userId,
          photoUrl: photoUrl,
          mediaRevision: mediaRevision,
          displayName: displayName,
          backgroundColor: backgroundColor ?? const Color(0xFF64258E),
          premium: premium,
          fallbackIcon: fallbackIcon,
        );

    final frameColors = achievementStyle?.frameColors;
    if (frameColors == null || frameColors.isEmpty) return avatar;

    final against = surface ?? Theme.of(context).scaffoldBackgroundColor;
    final colors = [
      for (final color in frameColors)
        contrastAdjusted(color, surface: against, minimumRatio: 3),
    ];
    final inset = ringWidth + ringGap;

    return Padding(
      padding: EdgeInsets.all(inset),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            left: -inset,
            top: -inset,
            right: -inset,
            bottom: -inset,
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: CustomPaint(
                  key: achievementAvatarRingKey,
                  painter: _AchievementRingPainter(
                    colors: colors,
                    ringWidth: ringWidth,
                  ),
                ),
              ),
            ),
          ),
          avatar,
        ],
      ),
    );
  }
}

class _AchievementRingPainter extends CustomPainter {
  const _AchievementRingPainter({
    required this.colors,
    required this.ringWidth,
  });

  final List<Color> colors;
  final double ringWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - ringWidth) / 2;
    if (radius <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth;
    if (colors.length == 1) {
      ring.color = colors.single;
    } else {
      // Closed sweep so the seam at 12 o'clock is invisible; the ring is
      // static — identity, not motion.
      ring.shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [...colors, colors.first],
      ).createShader(rect);
    }
    canvas.drawCircle(center, radius, ring);

    // A restrained halo in the frame's first colour; fixed alpha, cheap.
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth * 2
      ..color = colors.first.withValues(alpha: .14)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(center, radius, glow);
  }

  @override
  bool shouldRepaint(_AchievementRingPainter oldDelegate) {
    if (oldDelegate.ringWidth != ringWidth) return true;
    if (oldDelegate.colors.length != colors.length) return true;
    for (var index = 0; index < colors.length; index++) {
      if (oldDelegate.colors[index] != colors[index]) return true;
    }
    return false;
  }
}
