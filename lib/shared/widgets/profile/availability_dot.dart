import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';

/// A filled circle in a status colour — the ring colour, as a dot.
///
/// The one source for every presence DOT in the app (Slim redesign, phase 0,
/// ADR-209): online / be right back / do not disturb / offline are always
/// `PeopleStatus.foreground`, the same ink `PeopleStatusAvatar` paints as a
/// ring, so a dot and a ring can never disagree about what green means.
///
/// The caller owns everything but the drawing: the visibility gate (some
/// surfaces hide the dot when offline, some draw it grey), the status
/// derivation (`PeopleStatus.fromPresence` for others,
/// `PeopleStatus.fromOwnAvailability` for the signed-in account), the
/// `Positioned` offset, the size, and the punch-out halo: [borderColor] is the
/// surface the avatar sits on (`background`, `surface`, `surfaceRaised`,
/// `surfaceSunken`) and [borderWidth] 0 draws no halo at all. Defaults
/// reproduce the availability picker's chip and option dots.
///
/// One presence mark per avatar: an avatar carries this dot OR a
/// `PeopleStatusAvatar` ring, never both (`HomeFriendTile`,
/// `test/people_status_ring_theme_test.dart`). The dot carries no semantics
/// and no key of its own — the row or avatar that mounts it already announces
/// "name, online", and a second node would double-announce.
class AvailabilityDot extends StatelessWidget {
  const AvailabilityDot({
    required this.status,
    this.size = 10,
    this.borderColor,
    this.borderWidth = 1.5,
    super.key,
  }) : assert(borderWidth >= 0, 'borderWidth must not be negative');

  final PeopleStatus status;

  /// Diameter, halo included.
  final double size;

  /// The halo colour; `null` means `palette.surfaceRaised`, the picker's
  /// surface. Pass the surface the avatar actually sits on.
  final Color? borderColor;

  /// The halo width; `0` draws a bare disc.
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: status.foreground(palette),
        border: borderWidth > 0
            ? Border.all(
                color: borderColor ?? palette.surfaceRaised,
                width: borderWidth,
              )
            : null,
      ),
    );
  }
}
