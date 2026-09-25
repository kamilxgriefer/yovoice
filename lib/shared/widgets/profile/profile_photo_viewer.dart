import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/profile_banner.dart';
import 'package:yovoice/shared/widgets/profile/profile_media_image.dart';

/// Opens the private fullscreen viewer for a profile avatar or banner.
///
/// Only uid and a non-secret revision cross this boundary; durable or signed
/// media URLs are deliberately not accepted, so every open re-checks
/// visibility, friendship, blocks and account state server-side.
Future<void> showProfilePhotoViewer(
  BuildContext context, {
  required String userId,
  required String displayName,
  ProfileMediaKind kind = ProfileMediaKind.avatar,
  Object? mediaRevision,
  ProfileMediaService? mediaService,
  ProfileMediaImageProvider? imageProvider,
}) {
  final copy = AppLocalizations.of(context);
  final name = _viewerName(copy, displayName);
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: context.appPalette.scrim.withValues(alpha: .86),
    builder: (dialogContext) => _ProfilePhotoDialog(
      userId: userId,
      displayName: name,
      kind: kind,
      mediaRevision: mediaRevision,
      mediaService: mediaService,
      imageProvider: imageProvider,
    ),
  );
}

/// The single place a missing display name becomes a name.
///
/// The dialog already fell back to "YO Voice member" while the two launchers
/// interpolated the raw value, so a profile whose `displayName` is an empty
/// string announced a dangling "Zdjęcie w tle:" and then opened a dialog
/// titled "Zdjęcie w tle: Użytkownik YO Voice" — two different names for one
/// photo, with nothing for a screen reader to read out. Trimming here also
/// keeps a padded name from being announced with its whitespace.
String _viewerName(AppLocalizations copy, String displayName) {
  final trimmed = displayName.trim();
  return trimmed.isEmpty
      ? copy.text('YO Voice member', 'Użytkownik YO Voice')
      : trimmed;
}

/// Banner ("zdjęcie w tle") flavour of [showProfilePhotoViewer].
Future<void> showProfileBannerViewer(
  BuildContext context, {
  required String userId,
  required String displayName,
  Object? mediaRevision,
  ProfileMediaService? mediaService,
  ProfileMediaImageProvider? imageProvider,
}) => showProfilePhotoViewer(
  context,
  userId: userId,
  displayName: displayName,
  kind: ProfileMediaKind.banner,
  mediaRevision: mediaRevision,
  mediaService: mediaService,
  imageProvider: imageProvider,
);

/// Accessible, keyboard-operable launcher for the private profile-photo
/// viewer. Only uid and a non-secret revision cross this boundary; durable or
/// signed media URLs are deliberately not accepted.
class ProfilePhotoButton extends StatelessWidget {
  const ProfilePhotoButton({
    required this.userId,
    required this.displayName,
    required this.child,
    this.mediaRevision,
    this.mediaService,
    this.imageProvider,
    this.minimumSize = const Size(44, 44),
    super.key,
  });

  final String userId;
  final String displayName;
  final Widget child;
  final Object? mediaRevision;
  final ProfileMediaService? mediaService;
  final ProfileMediaImageProvider? imageProvider;
  final Size minimumSize;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    // The same resolution the dialog applies, so the launcher and the frame
    // it opens can never announce two different names for one photo.
    final name = _viewerName(copy, displayName);
    final label = copy.template(
      'Profile photo of {name}',
      'Zdjęcie profilowe: {name}',
      values: {'name': name},
    );
    final tooltip = copy.template(
      'View profile photo of {name}',
      'Powiększ zdjęcie profilowe: {name}',
      values: {'name': name},
    );
    return AccessibleTapRegion(
      onTap: () => showProfilePhotoViewer(
        context,
        userId: userId,
        displayName: displayName,
        mediaRevision: mediaRevision,
        mediaService: mediaService,
        imageProvider: imageProvider,
      ),
      semanticLabel: label,
      tooltip: tooltip,
      circular: true,
      minimumSize: minimumSize,
      child: ExcludeSemantics(child: child),
    );
  }
}

/// The banner equivalent of [ProfilePhotoButton]: a full-width band, so the
/// region is rectangular and carries the header's 22px corner radius rather
/// than a circle.
class ProfileBannerButton extends StatelessWidget {
  const ProfileBannerButton({
    required this.userId,
    required this.displayName,
    required this.child,
    this.mediaRevision,
    this.mediaService,
    this.imageProvider,
    this.borderRadius = 22,
    this.minimumSize = const Size(44, 44),
    this.focusContrastColor,
    super.key,
  });

  final String userId;
  final String displayName;
  final Widget child;
  final Object? mediaRevision;
  final ProfileMediaService? mediaService;
  final ProfileMediaImageProvider? imageProvider;
  final double borderRadius;
  final Size minimumSize;

  /// Outer edge of a two-tone focus ring for a band whose photo has unknown
  /// luminance (the full-bleed profile hero). Null keeps the plain ring.
  final Color? focusContrastColor;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    // Same resolution as the dialog — see [_viewerName].
    final name = _viewerName(copy, displayName);
    final label = copy.template(
      'Background photo of {name}',
      'Zdjęcie w tle: {name}',
      values: {'name': name},
    );
    final tooltip = copy.template(
      'View background photo of {name}',
      'Powiększ zdjęcie w tle: {name}',
      values: {'name': name},
    );
    return AccessibleTapRegion(
      onTap: () => showProfileBannerViewer(
        context,
        userId: userId,
        displayName: displayName,
        mediaRevision: mediaRevision,
        mediaService: mediaService,
        imageProvider: imageProvider,
      ),
      semanticLabel: label,
      tooltip: tooltip,
      borderRadius: borderRadius,
      minimumSize: minimumSize,
      focusContrastColor: focusContrastColor,
      child: ExcludeSemantics(child: child),
    );
  }
}

class _ProfilePhotoDialog extends StatefulWidget {
  const _ProfilePhotoDialog({
    required this.userId,
    required this.displayName,
    required this.kind,
    required this.mediaRevision,
    required this.mediaService,
    required this.imageProvider,
  });

  final String userId;
  final String displayName;
  final ProfileMediaKind kind;
  final Object? mediaRevision;
  final ProfileMediaService? mediaService;
  final ProfileMediaImageProvider? imageProvider;

  @override
  State<_ProfilePhotoDialog> createState() => _ProfilePhotoDialogState();
}

class _ProfilePhotoDialogState extends State<_ProfilePhotoDialog> {
  /// What the resolver last reported. The viewer promises a photo, so the
  /// three non-photo outcomes must read differently: still loading, there is
  /// no photo, and we could not load one.
  ProfileMediaResolution _resolution = ProfileMediaResolution.pending;

  bool get _isBanner => widget.kind == ProfileMediaKind.banner;

  void _onResolution(ProfileMediaResolution resolution) {
    if (!mounted || resolution == _resolution) return;
    setState(() => _resolution = resolution);
  }

  void _retry() {
    setState(() => _resolution = ProfileMediaResolution.pending);
    // The sanctioned re-resolution path: it bumps the target epoch and
    // broadcasts a boundary, so every mounted copy re-resolves through the
    // single-flight map and one tap produces one callable.
    ProfileMediaService.evictUser(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final title = _isBanner
        ? copy.template(
            'Background photo of {name}',
            'Zdjęcie w tle: {name}',
            values: {'name': widget.displayName},
          )
        : copy.template(
            'Profile photo of {name}',
            'Zdjęcie profilowe: {name}',
            values: {'name': widget.displayName},
          );
    final closeLabel = _isBanner
        ? copy.text('Close background photo', 'Zamknij zdjęcie w tle')
        : copy.text('Close profile photo', 'Zamknij zdjęcie profilowe');
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: Dialog(
        backgroundColor: palette.surfaceRaised,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: palette.borderStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('profile-photo-viewer-close'),
                      tooltip: closeLabel,
                      onPressed: () => Navigator.of(context).pop(),
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: AspectRatio(
                  // 16:9 mirrors ProfileImageRules.banner, so the fullscreen
                  // frame matches what the upload pipeline actually stores.
                  aspectRatio: _isBanner ? 16 / 9 : 1,
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox.expand(
                      child: ProfileMediaImage(
                        userId: widget.userId,
                        kind: widget.kind,
                        fit: BoxFit.contain,
                        fallback: _fallback(context, copy, palette),
                        onResolution: _onResolution,
                        service: widget.mediaService,
                        revision: widget.mediaRevision,
                        imageProvider: widget.imageProvider,
                        filterQuality: FilterQuality.high,
                        imageKey: const ValueKey('profile-photo-viewer-image'),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shown whenever there is no photo on screen. Which of the three reasons
  /// it explains is decided by the resolver, never guessed: calling a pending
  /// or blocked grant "no photo" is exactly the mislabelling this replaces.
  Widget _fallback(
    BuildContext context,
    AppLocalizations copy,
    AppPalette palette,
  ) {
    final backdrop = _isBanner
        ? const DecoratedBox(
            decoration: BoxDecoration(gradient: kProfileBannerFallbackGradient),
          )
        : ColoredBox(color: palette.surfaceSunken);

    // The banner's backdrop is `kProfileBannerFallbackGradient` — a FIXED
    // dark gradient painted in both appearances — so the copy drawn on it has
    // to be theme-independent too. Taking the theme palette put Pearl's dark
    // inks on that gradient at 1.5:1 (body), 1.5:1 (retry) and 2.0:1 (icon),
    // against the 4.5:1 WCAG 1.4.3 needs for this 15 px w700 copy and the
    // 3:1 1.4.11 needs for the glyph. `AppImmersiveColors` is the token set
    // this app already uses for its fixed-dark routes; on the gradient's
    // brightest stop (#53108C) it reads 11.5:1 (white) and 5.4:1
    // (`textSecondary`). The avatar flavour keeps the palette: its backdrop
    // is `palette.surfaceSunken`, which follows the theme.
    final foreground = _isBanner ? AppImmersiveColors.textPrimary : null;
    final iconForeground = _isBanner
        ? AppImmersiveColors.textSecondary
        : palette.textTertiary;
    final messageForeground = foreground ?? palette.textSecondary;

    return Stack(
      fit: StackFit.expand,
      children: [
        backdrop,
        // The banner frame is a 16:9 box: at 320 dp it is ~157 dp tall, and
        // at 200 % text the icon, the wrapped message and the retry button
        // ask for far more than that. Unscrollable, it painted an overflow
        // stripe over the user's content and clipped the retry button away
        // entirely — the viewer's only recovery affordance. Scrolling keeps
        // the column centred whenever it fits and reachable when it does not.
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(0, constraints.maxHeight - 48),
              ),
              child: Center(
                child: switch (_resolution) {
                  ProfileMediaResolution.pending ||
                  // `available` only reaches the fallback for the frame between a
                  // decode failure and its reported transition to `failed`.
                  ProfileMediaResolution.available => Semantics(
                    label: _isBanner
                        ? copy.text(
                            'Loading background photo',
                            'Wczytywanie zdjęcia w tle',
                          )
                        : copy.text(
                            'Loading profile photo',
                            'Wczytywanie zdjęcia profilowego',
                          ),
                    child: SizedBox(
                      key: const ValueKey('profile-photo-viewer-loading'),
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        // Same reason as the message layer: on the fixed dark
                        // gradient Pearl's focus violet reads 1.5:1, under the
                        // 3:1 WCAG 1.4.11 needs for a non-text indicator.
                        color: foreground ?? palette.focus,
                      ),
                    ),
                  ),
                  ProfileMediaResolution.absent => _message(
                    iconColor: iconForeground,
                    messageColor: messageForeground,
                    key: const ValueKey('profile-photo-viewer-empty'),
                    icon: _isBanner
                        ? Icons.image_outlined
                        : Icons.person_outline_rounded,
                    message: _isBanner
                        ? copy.text(
                            'No background photo yet',
                            'Brak zdjęcia w tle',
                          )
                        : copy.text(
                            'No profile photo yet',
                            'Brak zdjęcia profilowego',
                          ),
                  ),
                  ProfileMediaResolution.failed => _message(
                    iconColor: iconForeground,
                    messageColor: messageForeground,
                    key: const ValueKey('profile-photo-viewer-error'),
                    icon: Icons.error_outline_rounded,
                    message: copy.text(
                      'Photo unavailable',
                      'Nie udało się wczytać zdjęcia',
                    ),
                    action: TextButton(
                      key: const ValueKey('profile-photo-viewer-retry'),
                      onPressed: _retry,
                      style: foreground == null
                          ? null
                          : TextButton.styleFrom(foregroundColor: foreground),
                      child: Text(copy.text('Try again', 'Spróbuj ponownie')),
                    ),
                  ),
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _message({
    required Color iconColor,
    required Color messageColor,
    required Key key,
    required IconData icon,
    required String message,
    Widget? action,
  }) => Column(
    key: key,
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 44, color: iconColor),
      const SizedBox(height: 12),
      Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: messageColor,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (action != null) ...[const SizedBox(height: 4), action],
    ],
  );
}
