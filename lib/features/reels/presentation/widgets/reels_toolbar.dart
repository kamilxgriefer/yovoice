import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/shared/widgets/inputs/yo_segmented_pill.dart';

/// The one row of chrome above the Reels stage on a page canvas.
///
/// Immersive widths no longer use this widget: overlaid chrome is built by
/// `ImmersiveFeedChrome`, which carries the format switch and the pool
/// filters as two visually distinct levels. This branch is unchanged.
///
/// Audience is a segmented pill in the app's own switch grammar; Create Reel
/// is the tonal, format-specific action (the single filled-primary control on
/// the destination is the header's CREATE); refresh is a ghost icon. Every
/// control keeps a 44 px target.
///
/// The row folds only for two measured reasons — an accessibility text size,
/// or a viewport too narrow for a labelled action beside the pill — never for
/// a device label.
class ReelsToolbar extends StatelessWidget {
  const ReelsToolbar({
    required this.ownOnly,
    required this.onAudienceSelected,
    required this.onRefresh,
    required this.gutter,
    required this.showCreate,
    this.onCreate,
    super.key,
  });

  /// True while the feed is filtered to this viewer's own Reels.
  final bool ownOnly;
  final ValueChanged<bool> onAudienceSelected;

  /// Null while a load is already running.
  final VoidCallback? onRefresh;

  /// Horizontal gutter, shared with the stage below so the toolbar and the
  /// card sit on the same rhythm.
  final double gutter;

  /// False when this host offers no composer at all. Creation must never be
  /// silently unreachable, so the control is hidden only in that case; a
  /// publish already in flight keeps the button and disables it.
  final bool showCreate;
  final VoidCallback? onCreate;

  static const double _rowHeight = 44;
  static const double _pillIconSize = 16;
  static const double _pillFontSize = 13;
  static const double _pillSegmentPadding = 24;
  static const double _pillIconGap = 7;
  static const double _createIconSize = 18;
  static const double _createIconGap = 8;
  static const double _createPadding = 28;
  static const double _createFontSize = 13.5;

  double _textWidth(BuildContext context, String value, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final palette = context.appPalette;
    final textScaler = MediaQuery.textScalerOf(context);
    final discoverLabel = copy.text('Discover', 'Odkrywaj');
    final ownLabel = copy.text('Your Reels', 'Twoje Reels');
    final createLabel = copy.text('Create Reel', 'Utwórz Reel');
    final refreshLabel = copy.text('Refresh', 'Odśwież');

    // Measured with the very style each control renders in — family, fallback
    // and letter spacing included. A fit decision taken against a different
    // typeface than the one that ships is not a measurement, it is a guess.
    final pillTextStyle = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(
          fontSize: _pillFontSize,
          fontWeight: FontWeight.w700,
          height: 1.2,
        );
    final createTextStyle = (theme.textTheme.labelLarge ?? const TextStyle())
        .copyWith(fontSize: _createFontSize, fontWeight: FontWeight.w700);

    YoSegmentedPill pill({
      double? width,
      int labelMaxLines = 1,
      bool showIcons = true,
    }) {
      return YoSegmentedPill(
        segments: <YoSegmentedPillSegment>[
          YoSegmentedPillSegment(
            key: const ValueKey<String>('reels-discover-filter'),
            label: discoverLabel,
            icon: showIcons ? Icons.explore_outlined : null,
          ),
          YoSegmentedPillSegment(
            key: const ValueKey<String>('reels-own-filter'),
            label: ownLabel,
            icon: showIcons ? Icons.person_outline_rounded : null,
          ),
        ],
        selectedIndex: ownOnly ? 1 : 0,
        onSelected: (index) => onAudienceSelected(index == 1),
        width: width,
        iconSize: _pillIconSize,
        fontSize: _pillFontSize,
        labelMaxLines: labelMaxLines,
      );
    }

    final refreshButton = IconButton(
      key: const ValueKey('reels-refresh'),
      tooltip: refreshLabel,
      onPressed: onRefresh,
      iconSize: 22,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      style: IconButton.styleFrom(
        foregroundColor: palette.textSecondary,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.refresh_rounded),
    );

    // The app's FilledButton theme paints every filled button — tonal
    // included — in the primary brand fill. Left alone this action would be a
    // second primary control on a destination that already has exactly one
    // (the header's CREATE), so the secondary container is asked for by name.
    ButtonStyle createStyle({required bool iconOnly}) {
      return FilledButton.styleFrom(
        backgroundColor: colors.secondaryContainer,
        foregroundColor: colors.onSecondaryContainer,
        disabledBackgroundColor: palette.surfaceSunken,
        disabledForegroundColor: palette.textTertiary,
        minimumSize: iconOnly
            ? const Size(_rowHeight, _rowHeight)
            : const Size(0, _rowHeight),
        fixedSize: iconOnly ? const Size(_rowHeight, _rowHeight) : null,
        padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 14),
        shape: const StadiumBorder(),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: createTextStyle,
      ).copyWith(
        // The theme's focus ring is white, for a primary fill. On this one
        // it would vanish in Pearl.
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return BorderSide(color: palette.focus, width: 2);
          }
          // In Pearl the secondary container sits very close to the page,
          // so the hairline every other chip on this row carries is what
          // makes this one read as a control rather than a tint.
          return BorderSide(color: palette.border);
        }),
      );
    }

    // Icon-only keeps the key, the FilledButton type and — through the icon's
    // own semantic label plus the tooltip — the spoken name of the action.
    Widget createButton({required bool labelled}) {
      if (!labelled) {
        return Tooltip(
          message: createLabel,
          child: FilledButton.tonal(
            key: const ValueKey('reels-create-persistent'),
            onPressed: onCreate,
            style: createStyle(iconOnly: true),
            child: Icon(
              Icons.video_call_rounded,
              size: 20,
              semanticLabel: createLabel,
            ),
          ),
        );
      }
      return FilledButton.tonalIcon(
        key: const ValueKey('reels-create-persistent'),
        onPressed: onCreate,
        style: createStyle(iconOnly: false),
        icon: const Icon(Icons.video_call_rounded, size: _createIconSize),
        label: Text(createLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 6, gutter, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth;
          // Measured, not guessed: the same painter the row will use decides
          // whether the label fits beside the pill in this locale at this
          // text size.
          final segment =
              _pillIconSize +
              _pillIconGap +
              _pillSegmentPadding +
              math.max(
                _textWidth(context, discoverLabel, pillTextStyle),
                _textWidth(context, ownLabel, pillTextStyle),
              );
          final pillWidth = 2 * segment;
          final createWidth =
              _createIconSize +
              _createIconGap +
              _createPadding +
              _textWidth(context, createLabel, createTextStyle);
          final trailing = showCreate ? createWidth + 8 : 0;
          final labelledFits = pillWidth + trailing + 8 + 44 <= available;
          // The narrowest honest single row: the pill at the width its own
          // labels need, the action reduced to a glyph, and refresh. When even
          // that does not fit, the row folds — measured in this locale at this
          // text size rather than guessed from a breakpoint.
          final minimumRow =
              pillWidth + (showCreate ? _rowHeight + 8 : 0) + 8 + 44;
          final accessibilityLayout =
              textScaler.scale(1) >= 1.6 || minimumRow > available;

          if (accessibilityLayout) {
            // At large text sizes the labels carry the meaning; removing
            // decorative icons gives each word room before adding a second
            // line. If even a complete word cannot fit, preserve readable
            // labels in a horizontally scrollable switch, never mid-word
            // fragments or a smaller accessibility font.
            final longestWord =
                <String>[
                  ...discoverLabel.split(RegExp(r'\s+')),
                  ...ownLabel.split(RegExp(r'\s+')),
                ].fold<double>(
                  0,
                  (width, word) =>
                      math.max(width, _textWidth(context, word, pillTextStyle)),
                );
            final wholeWordsFit =
                2 * (_pillSegmentPadding + longestWord) <= available;
            final audienceSwitch = wholeWordsFit
                ? pill(
                    width: double.infinity,
                    labelMaxLines: 2,
                    showIcons: pillWidth <= available,
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: pill(width: pillWidth),
                  );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                audienceSwitch,
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    if (showCreate) ...<Widget>[
                      Flexible(child: createButton(labelled: true)),
                      const SizedBox(width: 8),
                    ],
                    refreshButton,
                  ],
                ),
              ],
            );
          }

          return SizedBox(
            height: _rowHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                // The pill keeps its intrinsic width while there is room and
                // gives way to the actions before anything can overflow.
                Flexible(child: pill()),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (showCreate) ...<Widget>[
                        createButton(labelled: labelledFits),
                        const SizedBox(width: 8),
                      ],
                      refreshButton,
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
