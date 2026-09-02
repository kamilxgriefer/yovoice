import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/profile_media_image.dart';

Future<void> showProfilePhotoViewer(
  BuildContext context, {
  required String userId,
  required String displayName,
  Object? mediaRevision,
  ProfileMediaService? mediaService,
  ProfileMediaImageProvider? imageProvider,
}) {
  final copy = AppLocalizations.of(context);
  final name = displayName.trim().isEmpty
      ? copy.text('YO Voice member', 'Użytkownik YO Voice')
      : displayName.trim();
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: context.appPalette.scrim.withValues(alpha: .86),
    builder: (dialogContext) => _ProfilePhotoDialog(
      userId: userId,
      displayName: name,
      mediaRevision: mediaRevision,
      mediaService: mediaService,
      imageProvider: imageProvider,
    ),
  );
}

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
    final label = copy.template(
      'Profile photo of {name}',
      'Zdjęcie profilowe: {name}',
      values: {'name': displayName},
    );
    final tooltip = copy.template(
      'View profile photo of {name}',
      'Powiększ zdjęcie profilowe: {name}',
      values: {'name': displayName},
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

class _ProfilePhotoDialog extends StatelessWidget {
  const _ProfilePhotoDialog({
    required this.userId,
    required this.displayName,
    required this.mediaRevision,
    required this.mediaService,
    required this.imageProvider,
  });

  final String userId;
  final String displayName;
  final Object? mediaRevision;
  final ProfileMediaService? mediaService;
  final ProfileMediaImageProvider? imageProvider;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final title = copy.template(
      'Profile photo of {name}',
      'Zdjęcie profilowe: {name}',
      values: {'name': displayName},
    );
    final closeLabel = copy.text(
      'Close profile photo',
      'Zamknij zdjęcie profilowe',
    );
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
                  aspectRatio: 1,
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox.expand(
                      child: ProfileMediaImage(
                        userId: userId,
                        kind: ProfileMediaKind.avatar,
                        fit: BoxFit.contain,
                        fallback: ColoredBox(
                          color: palette.surfaceSunken,
                          child: Center(
                            child: Text(
                              displayName.isEmpty
                                  ? '?'
                                  : displayName[0].toUpperCase(),
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 96,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        service: mediaService,
                        revision: mediaRevision,
                        imageProvider: imageProvider,
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
}
