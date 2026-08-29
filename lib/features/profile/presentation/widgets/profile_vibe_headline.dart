import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_vibe_link.dart';

typedef ProfileVibeLinkLauncher = Future<bool> Function(Uri uri);

/// The shared visual treatment for a member's short social headline.
///
/// Both the signed-in profile and another member's full profile use this
/// widget so a saved Vibe and any safe links inside it behave identically on
/// every profile surface.
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
    setState(() {
      _opening = false;
      _coolingDown = opened;
      _openError = opened ? null : "Couldn't open this link.";
    });

    if (opened) {
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _coolingDown = false);
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final value = widget.vibe.trim();
    final links = ProfileVibeLink.fromText(value);
    final description = profileVibeDescription(value, links);
    final radius = BorderRadius.circular(widget.compact ? 14 : 16);
    final surface = Color.alphaBlend(
      scheme.primary.withValues(alpha: isDark ? .13 : .055),
      palette.surfaceMuted,
    );
    final border = Color.alphaBlend(
      palette.focus.withValues(alpha: isDark ? .44 : .28),
      palette.border,
    );

    return Material(
      key: const ValueKey('profile-vibe-surface'),
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(widget.compact ? 11 : 13),
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
                    size: widget.compact ? 17 : 19,
                    color: palette.focus,
                  ),
                ),
                SizedBox(width: widget.compact ? 8 : 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VIBE',
                        key: const ValueKey('profile-vibe-label'),
                        style: TextStyle(
                          color: palette.focus,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.25,
                        ),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Semantics(
                          label: 'Vibe: $description',
                          child: ExcludeSemantics(
                            child: Text(
                              description,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: widget.compact ? 14 : 15,
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
            for (final link in links) ...[
              const SizedBox(height: 10),
              _VibeLinkRow(
                link: link,
                busy: _opening,
                enabled: !_opening && !_coolingDown,
                onOpen: () => _open(link),
              ),
            ],
            if (_openError != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Container(
                  key: const ValueKey('profile-vibe-error'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: scheme.error.withValues(alpha: .46),
                    ),
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
          ],
        ),
      ),
    );
  }
}

class _VibeLinkRow extends StatefulWidget {
  const _VibeLinkRow({
    required this.link,
    required this.busy,
    required this.enabled,
    required this.onOpen,
  });

  final ProfileVibeLink link;
  final bool busy;
  final bool enabled;
  final VoidCallback onOpen;

  @override
  State<_VibeLinkRow> createState() => _VibeLinkRowState();
}

class _VibeLinkRowState extends State<_VibeLinkRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final linkAccent = scheme.tertiary;
    final linkSurface = theme.brightness == Brightness.dark
        ? palette.surfaceSunken
        : palette.surfaceRaised;
    const radius = BorderRadius.all(Radius.circular(14));
    return Semantics(
      container: true,
      link: true,
      linkUrl: widget.link.uri,
      label: widget.link.semanticLabel,
      hint: 'Opens in another app',
      onTap: widget.enabled ? widget.onOpen : null,
      child: ExcludeSemantics(
        child: Material(
          key: ValueKey('profile-vibe-link-surface-${widget.link.uri}'),
          color: linkSurface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: _focused ? palette.focus : palette.border,
              width: _focused ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('profile-vibe-link-${widget.link.uri}'),
            onTap: widget.enabled ? widget.onOpen : null,
            onFocusChange: (focused) {
              if (mounted) setState(() => _focused = focused);
            },
            borderRadius: radius,
            focusColor: scheme.primary.withValues(alpha: .16),
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
                          color: linkAccent,
                        ),
                      )
                    else
                      Icon(
                        key: ValueKey(
                          'profile-vibe-link-leading-${widget.link.uri}',
                        ),
                        Icons.music_note_rounded,
                        size: 20,
                        color: linkAccent,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.busy ? 'Opening…' : widget.link.actionLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            widget.link.hostLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textSecondary,
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
                      color: linkAccent,
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
