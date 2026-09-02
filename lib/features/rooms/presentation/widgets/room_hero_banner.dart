import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/space_identity.dart';
import 'package:yovoice/core/theme/app_typography.dart';

/// The room's hero: cover image darkened and blurred behind a readable
/// scrim, the type chip, the room name in large type, a one-line topic and
/// an optional right-hand action ("View club ↗") or status pill (the
/// podcast LIVE marker). The photo never competes with the text.
///
/// Shared by all four room families — the [SpaceIdentity] carries the
/// accent, icon and wording; the layout is one system.
class RoomHeroBanner extends StatelessWidget {
  const RoomHeroBanner({
    required this.identity,
    required this.title,
    required this.topic,
    this.imageUrl,
    this.statusPill,
    this.action,
    this.footer,
    super.key,
  });

  final SpaceIdentity identity;
  final String title;
  final String topic;
  final String? imageUrl;

  /// A small pill beside the type chip (podcast: "• LIVE PODCAST").
  final Widget? statusPill;

  /// Right-aligned affordance (Club: outlined "View club ↗"; family: the
  /// compact expand icon).
  final Widget? action;

  /// Extra identity content under the topic (podcast: hosted-by row and
  /// the live waveform).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final accent = identity.primary;
    final image = imageUrl?.trim();
    final accessibilityReflow =
        MediaQuery.sizeOf(context).width <= 360 &&
        MediaQuery.textScalerOf(context).scale(1) >= 1.75;

    return ClipRRect(
      key: ValueKey('room-hero-${identity.kind.name}'),
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: .26),
              identity.surface,
              const Color(0xFF0A0710),
            ],
            stops: const [0, .55, 1],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            if (image != null && image.isNotEmpty) ...[
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                  child: Image.network(
                    image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
              // The readability scrim. Strong on purpose: the image is
              // atmosphere, the words are the content.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                      colors: [
                        Colors.black.withValues(alpha: .78),
                        Colors.black.withValues(alpha: .48),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (accessibilityReflow)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            RoomTypeChip(identity: identity),
                            ?statusPill,
                          ],
                        ),
                        if (action != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: action!,
                          ),
                        ],
                      ],
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              RoomTypeChip(identity: identity),
                              ?statusPill,
                            ],
                          ),
                        ),
                        if (action != null) ...[
                          const Spacer(),
                          const SizedBox(width: 8),
                          action!,
                        ],
                      ],
                    ),
                  const SizedBox(height: 13),
                  Text(
                    key: const ValueKey('room-hero-title'),
                    title,
                    maxLines: accessibilityReflow ? null : 2,
                    overflow: accessibilityReflow
                        ? null
                        : TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.4,
                      height: 1.12,
                    ),
                  ),
                  if (topic.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      key: const ValueKey('room-hero-topic'),
                      topic,
                      maxLines: accessibilityReflow ? null : 2,
                      overflow: accessibilityReflow
                          ? null
                          : TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .74),
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (footer != null) ...[const SizedBox(height: 14), footer!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The identity eyebrow: type icon + uppercase label in the accent.
class RoomTypeChip extends StatelessWidget {
  const RoomTypeChip({required this.identity, super.key});

  final SpaceIdentity identity;

  @override
  Widget build(BuildContext context) {
    final accessibilityReflow =
        MediaQuery.sizeOf(context).width <= 360 &&
        MediaQuery.textScalerOf(context).scale(1) >= 1.75;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .38),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: identity.primary.withValues(alpha: .38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(identity.icon, size: 13, color: identity.accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              identity.label.toUpperCase(),
              maxLines: accessibilityReflow ? null : 1,
              softWrap: accessibilityReflow,
              overflow: accessibilityReflow ? null : TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .9),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A liveness pill for the hero. It renders only real state: the caller
/// passes the label the room document justifies ("LIVE PODCAST",
/// "NOT LIVE YET") — never a decorative badge.
class RoomHeroStatusPill extends StatelessWidget {
  const RoomHeroStatusPill({
    required this.label,
    required this.live,
    required this.identity,
    super.key,
  });

  final String label;
  final bool live;
  final SpaceIdentity identity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: live
            ? identity.primary.withValues(alpha: .2)
            : Colors.black.withValues(alpha: .38),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: live
              ? identity.primary.withValues(alpha: .6)
              : Colors.white.withValues(alpha: .16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: live
                  ? identity.primary
                  : Colors.white.withValues(alpha: .45),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: live ? Colors.white : Colors.white.withValues(alpha: .7),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .9,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The hero's right-hand affordance. Wide layouts get the outlined label
/// button ("View club ↗"); narrow ones collapse to the compact icon so the
/// chip row never fights the room name for space.
class RoomHeroLinkAction extends StatelessWidget {
  const RoomHeroLinkAction({
    required this.label,
    required this.onTap,
    required this.identity,
    this.compact = false,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final SpaceIdentity identity;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: label,
        onPressed: onTap,
        color: identity.accent,
        icon: const Icon(Icons.arrow_outward_rounded, size: 20),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: identity.accent,
        side: BorderSide(color: identity.accent.withValues(alpha: .55)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        // The FAMILY has to be named here. `styleFrom(textStyle:)` REPLACES
        // the button's text style rather than merging with it, so omitting
        // the family drops this one control off the app typeface — onto the
        // platform default in production, and onto the test framework's
        // block-glyph fallback in a screenshot, where it renders as solid
        // rectangles instead of "View club".
        textStyle: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      icon: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      label: const Icon(Icons.arrow_outward_rounded, size: 15),
    );
  }
}
