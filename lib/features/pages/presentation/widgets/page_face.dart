import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/widgets/navigation/yo_server_rail_item.dart';
import 'package:yovoice/shared/widgets/profile/profile_media_image.dart';

/// A Premium Page's face (premium-pages §4.6): the account's own profile
/// photo in the server squircle ([AppRadius.md], 14 at every size) instead
/// of a person's disc, with a 1 px hairline edge.
///
/// The photo comes through the existing viewer-authorized media path
/// ([ProfileMediaImage], the same grant as every avatar, so profile
/// visibility and blocks still apply). Without a photo, or when the grant is
/// refused, it shows the account's initial: in the server face of its kind
/// when [kind] is known (Firma = the Company identity, Społeczność = the
/// Community identity, as on the approved wall A / Find renders), else on
/// the letter-avatar gradient.
///
/// [ring] > 0 adds a solid band in [ringColor] (the page background by
/// default) around the squircle: the Page profile's face 80 with a 3 px ring
/// overlapping the cover.
///
/// Decoration only: the Page's name beside it carries the identity, so the
/// face adds nothing to the semantics tree.
class PageFace extends StatelessWidget {
  const PageFace({
    required this.pageId,
    required this.name,
    required this.size,
    this.ring = 0,
    this.ringColor,
    this.mediaRevision,
    this.mediaService,
    this.kind,
    super.key,
  });

  /// The Page's kind, for the letter fallback's identity.
  final PageKind? kind;

  /// The server template whose face a Page of [kind] borrows.
  static ServerType serverTypeFor(PageKind kind) => switch (kind) {
    PageKind.business => ServerType.company,
    PageKind.community => ServerType.community,
  };

  /// The Page's id, which is its owner's uid.
  final String pageId;

  /// The Page's display name; its first grapheme is the fallback letter.
  final String name;

  /// The squircle's side, excluding [ring].
  final double size;
  final double ring;
  final Color? ringColor;
  final Object? mediaRevision;

  /// Test seam; the app uses the shared service.
  final ProfileMediaService? mediaService;

  /// The squircle's corner radius, identical at every size.
  static const double cornerRadius = 14;

  /// The first grapheme cluster, upper-cased; "?" for an empty name.
  static String initialFor(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final letterDecoration = highContrast
        ? BoxDecoration(color: AppGradients.letterAvatar.colors.last)
        : BoxDecoration(gradient: AppGradients.letterAvatar);
    final kind = this.kind;
    final Widget letter = kind != null
        ? KeyedSubtree(
            key: const ValueKey('page-face-letter'),
            child: YoServerTile(
              initial: initialFor(name),
              type: serverTypeFor(kind),
              size: size,
              bordered: false,
              textStyle: size >= 48
                  ? AppTypography.titleLarge.copyWith(
                      fontWeight: FontWeight.w800,
                    )
                  : null,
            ),
          )
        : DecoratedBox(
            key: const ValueKey('page-face-letter'),
            decoration: letterDecoration,
            child: Center(
              child: Text(
                initialFor(name),
                // Sized to the squircle, not to the reader's text: the scaled name
                // beside it carries the identity.
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: AppColors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: size * .42,
                  height: 1.1,
                ),
              ),
            ),
          );
    Widget face = SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: AppRadius.md,
        child: ProfileMediaImage(
          userId: pageId,
          kind: ProfileMediaKind.avatar,
          fit: BoxFit.cover,
          fallback: SizedBox.expand(child: letter),
          service: mediaService,
          revision: mediaRevision,
        ),
      ),
    );
    face = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: AppRadius.md,
        border: Border.all(
          color: highContrast ? palette.borderStrong : palette.hairline,
        ),
      ),
      child: face,
    );
    if (ring > 0) {
      face = Container(
        key: const ValueKey('page-face-ring'),
        padding: EdgeInsets.all(ring),
        decoration: BoxDecoration(
          color: ringColor ?? palette.background,
          borderRadius: BorderRadius.circular(cornerRadius + ring),
        ),
        child: face,
      );
    }
    return ExcludeSemantics(child: face);
  }
}
