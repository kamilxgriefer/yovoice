import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_layout.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_vibe_link.dart';

typedef ProfileVibeLinkLauncher = Future<bool> Function(Uri uri);

/// The shared visual treatment for a member's short social headline.
///
/// Both the signed-in profile and another member's full profile use this
/// widget so a saved Vibe and any safe links inside it behave identically on
/// every profile surface.
///
/// Refine-look §8.5: the vibe is the profile's one colour block (the light
/// budget gives Profile no corner tint because this sticker IS the colour).
/// It paints `AppGradients.primaryAction` on a slight diagonal over its
/// primary base, radius `tile` (14 compact), no border and no shadow, with a
/// white @ .14 90 px circle catching light at the top-end corner. All ink on
/// it is white (≥ 5.79:1 across the sweep). Links ride as contrast-ink
/// plates with a white hairline and a 2 px white focus ring. From a
/// [ProfileLayout.vibeCapFromWidth] column the sticker stops at
/// [ProfileLayout.vibeMaxWidth], start-aligned. Under high contrast it is a
/// flat primary plate with a `borderStrong` edge and no circle.
///
/// [compact] is the profile preview sheet's variant, and that sheet
/// inherits nothing from the refine (spec §10): it already carries its own
/// violet primary action, and the light budget's exemption for the sticker
/// covers the Profile page only. So the compact vibe keeps its neutral
/// tinted plate — `surfaceMuted` washed with primary, an
/// `interactiveForeground` edge, page ink and contrast-checked link rows —
/// exactly as before the sticker existed.
class ProfileVibeHeadline extends StatefulWidget {
  const ProfileVibeHeadline({
    required this.vibe,
    this.compact = false,
    this.launcher,
    super.key,
  });

  final String vibe;
  final bool compact;

  /// Test seam. Production opens the HTTPS universal link externally so an
  /// installed music app can claim it and the browser remains the fallback.
  final ProfileVibeLinkLauncher? launcher;

  /// The sticker's ink: white on the violet sweep.
  static const Color ink = AppColors.white;

  @override
  State<ProfileVibeHeadline> createState() => _ProfileVibeHeadlineState();
}

class _ProfileVibeHeadlineState extends State<ProfileVibeHeadline> {
  bool _opening = false;
  bool _coolingDown = false;
  String? _openError;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _open(ProfileVibeLink link) async {
    if (_opening || _coolingDown) return;
    setState(() {
      _opening = true;
      _openError = null;
    });

    var opened = false;
    try {
      opened = await (widget.launcher ?? _launchExternally)(link.uri);
    } catch (_) {
      opened = false;
    }

    if (!mounted) return;
    final copy = AppLocalizations.of(context);
    setState(() {
      _opening = false;
      _coolingDown = opened;
      _openError = opened
          ? null
          : copy.text(
              "Couldn't open this link.",
              'Nie udało się otworzyć tego linku.',
            );
    });

    if (opened) {
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _coolingDown = false);
      });
      return;
    }
  }

  /// The link rows and the open error, shared by both variants.
  List<Widget> _linksAndError(
    BuildContext context,
    List<ProfileVibeLink> links, {
    required bool onSticker,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return [
      for (final link in links) ...[
        const SizedBox(height: 10),
        _VibeLinkRow(
          link: link,
          busy: _opening,
          enabled: !_opening && !_coolingDown,
          onSticker: onSticker,
          onOpen: () => _open(link),
        ),
      ],
      if (_openError != null) ...[
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Container(
            key: const ValueKey('profile-vibe-error'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: onSticker
                  ? AppRadius.sm
                  : const BorderRadius.all(Radius.circular(10)),
              border: Border.all(color: scheme.error.withValues(alpha: .46)),
            ),
            child: Text(
              _openError!,
              style: TextStyle(
                color: scheme.onErrorContainer,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ];
  }

  /// The preview sheet's neutral plate (see [ProfileVibeHeadline.compact]).
  Widget _plate(
    BuildContext context,
    String description,
    String semanticLabel,
    List<ProfileVibeLink> links,
  ) {
    final palette = context.appPalette;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surface = Color.alphaBlend(
      scheme.primary.withValues(alpha: isDark ? .13 : .055),
      palette.surfaceMuted,
    );
    final border = Color.alphaBlend(
      palette.interactiveForeground.withValues(alpha: isDark ? .44 : .28),
      palette.border,
    );
    return Material(
      key: const ValueKey('profile-vibe-surface'),
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    key: const ValueKey('profile-vibe-accent-icon'),
                    Icons.auto_awesome_rounded,
                    size: 17,
                    color: palette.interactiveForeground,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VIBE',
                        key: const ValueKey('profile-vibe-label'),
                        style: TextStyle(
                          color: palette.interactiveForeground,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.25,
                        ),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Semantics(
                          label: semanticLabel,
                          child: ExcludeSemantics(
                            child: Text(
                              description,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            ..._linksAndError(context, links, onSticker: false),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final value = widget.vibe.trim();
    final links = ProfileVibeLink.fromText(value);
    final description = profileVibeDescription(value, links);
    // One spoken name for the vibe on either variant.
    final semanticLabel = copy.text('Vibe: $description', 'Vibe: $description');
    if (widget.compact) {
      return _plate(context, description, semanticLabel, links);
    }
    const radius = AppRadius.tile;

    final content = Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  key: const ValueKey('profile-vibe-accent-icon'),
                  Icons.auto_awesome_rounded,
                  size: 19,
                  color: ProfileVibeHeadline.ink,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'VIBE',
                      key: ValueKey('profile-vibe-label'),
                      style: TextStyle(
                        color: ProfileVibeHeadline.ink,
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Semantics(
                        label: semanticLabel,
                        child: ExcludeSemantics(
                          child: Text(
                            description,
                            style: const TextStyle(
                              color: ProfileVibeHeadline.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                              letterSpacing: -.1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          ..._linksAndError(context, links, onSticker: true),
        ],
      ),
    );

    final sticker = Material(
      key: const ValueKey('profile-vibe-surface'),
      // The sweep's own first stop, flat: what high contrast shows and what
      // sits under the gradient everywhere else.
      color: scheme.primary,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: highContrast
            ? BorderSide(color: palette.borderStrong)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: highContrast
          ? content
          : Ink(
              key: const ValueKey('profile-vibe-sweep'),
              decoration: BoxDecoration(
                gradient: AppGradients.primaryAction(
                  scheme,
                  begin: const Alignment(-1, -.35),
                  end: const Alignment(1, .35),
                ),
              ),
              child: Stack(
                children: [
                  PositionedDirectional(
                    top: -38,
                    end: -30,
                    width: 90,
                    height: 90,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        key: const ValueKey('profile-vibe-glint'),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ProfileVibeHeadline.ink.withValues(alpha: .14),
                        ),
                      ),
                    ),
                  ),
                  content,
                ],
              ),
            ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < ProfileLayout.vibeCapFromWidth) {
          return sticker;
        }
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ProfileLayout.vibeMaxWidth,
            ),
            child: sticker,
          ),
        );
      },
    );
  }
}

class _VibeLinkRow extends StatefulWidget {
  const _VibeLinkRow({
    required this.link,
    required this.busy,
    required this.enabled,
    required this.onSticker,
    required this.onOpen,
  });

  final ProfileVibeLink link;
  final bool busy;
  final bool enabled;

  /// On the violet sticker (white ink on a contrast-ink plate) or on the
  /// compact neutral plate (page ink, tertiary glyphs, the focus role).
  final bool onSticker;
  final VoidCallback onOpen;

  @override
  State<_VibeLinkRow> createState() => _VibeLinkRowState();
}

class _VibeLinkRowState extends State<_VibeLinkRow> {
  bool _focused = false;

  /// The link plate on the sticker: contrast ink at .28, so white copy
  /// stays ≥ 4.5:1 over either end of the sweep.
  static final Color plate = AppColors.contrastInk.withValues(alpha: .28);

  /// The link host line: white at .86 (≥ 4.5:1 on the plate).
  static final Color hostInk = ProfileVibeHeadline.ink.withValues(alpha: .86);

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final palette = context.appPalette;
    final theme = Theme.of(context);
    final sticker = widget.onSticker;
    // Sticker: white ink on contrast ink. Plate: the page's own roles.
    final ink = sticker ? ProfileVibeHeadline.ink : palette.textPrimary;
    final accent = sticker
        ? ProfileVibeHeadline.ink
        : theme.colorScheme.tertiary;
    final host = sticker ? hostInk : palette.textSecondary;
    final fill = sticker
        ? plate
        : theme.brightness == Brightness.dark
        ? palette.surfaceSunken
        : palette.surfaceRaised;
    final BorderSide side;
    if (sticker) {
      // A 2 px white ring on focus (the sticker is violet, so the violet
      // focus role would vanish on it); a white hairline otherwise, solid
      // under high contrast.
      side = BorderSide(
        color: _focused || highContrast
            ? ProfileVibeHeadline.ink
            : ProfileVibeHeadline.ink.withValues(alpha: .18),
        width: _focused ? 2 : 1,
      );
    } else {
      side = BorderSide(
        color: _focused ? palette.focus : palette.border,
        width: _focused ? 2 : 1,
      );
    }
    final radius = sticker
        ? AppRadius.card
        : const BorderRadius.all(Radius.circular(14));
    return Semantics(
      container: true,
      link: true,
      linkUrl: widget.link.uri,
      label: widget.link.provider == null
          ? copy.text(
              'Open external link, ${widget.link.hostLabel}',
              'Otwórz link zewnętrzny: ${widget.link.hostLabel}',
            )
          : copy.text(
              'Open in ${widget.link.provider}, ${widget.link.hostLabel}',
              'Otwórz w ${widget.link.provider}: ${widget.link.hostLabel}',
            ),
      hint: copy.text('Opens in another app', 'Otwiera się w innej aplikacji'),
      onTap: widget.enabled ? widget.onOpen : null,
      child: ExcludeSemantics(
        child: Material(
          key: ValueKey('profile-vibe-link-surface-${widget.link.uri}'),
          color: fill,
          shape: RoundedRectangleBorder(borderRadius: radius, side: side),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('profile-vibe-link-${widget.link.uri}'),
            onTap: widget.enabled ? widget.onOpen : null,
            onFocusChange: (focused) {
              if (mounted) setState(() => _focused = focused);
            },
            borderRadius: radius,
            overlayColor: sticker
                ? WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return ink.withValues(alpha: .12);
                    }
                    if (states.contains(WidgetState.hovered)) {
                      return ink.withValues(alpha: .07);
                    }
                    // Focus is carried by the ring.
                    return Colors.transparent;
                  })
                : null,
            focusColor: sticker
                ? null
                : theme.colorScheme.primary.withValues(alpha: .16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    if (widget.busy)
                      SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                          backgroundColor: sticker ? Colors.transparent : null,
                        ),
                      )
                    else
                      Icon(
                        key: ValueKey(
                          'profile-vibe-link-leading-${widget.link.uri}',
                        ),
                        Icons.music_note_rounded,
                        size: 20,
                        color: accent,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.busy
                                ? copy.text('Opening…', 'Otwieranie…')
                                : widget.link.provider ??
                                      copy.text(
                                        'External link',
                                        'Link zewnętrzny',
                                      ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ink,
                              fontSize: 13,
                              fontWeight: sticker
                                  ? FontWeight.w700
                                  : FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            widget.link.hostLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: host,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      key: ValueKey(
                        'profile-vibe-link-trailing-${widget.link.uri}',
                      ),
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: accent,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> _launchExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
