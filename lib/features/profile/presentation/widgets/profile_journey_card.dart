import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/profile/presentation/widgets/profile_layout.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';

/// A width-independent summary of the member's activity on YO Voice.
///
/// Refine-look §8.5: the card is an R2 block (top-lit fill, hairline edge,
/// radius 20, Pearl's soft lift). Its layout follows the width it is given,
/// never a device label:
///
/// * below [ProfileLayout.journeyCellsFromWidth], and at any width once body
///   text is large (≈150 % and up), one compact row per counter — label at
///   the start, value at the end — separated by hairlines;
/// * from that width, four cells side by side: a 16 px glyph and a 12 w600
///   label, then the value at 22 w700 in tabular figures, with hairline
///   dividers between the cells.
///
/// Rows and cells keep an intrinsic height instead of deriving it from the
/// width, so the card is equally compact in the phone feed and on desktop.
class ProfileJourneyCard extends StatelessWidget {
  const ProfileJourneyCard({
    required this.communitiesCount,
    required this.messageCount,
    required this.voiceMinutes,
    required this.roomCount,
    super.key,
  });

  final int communitiesCount;
  final int messageCount;
  final int voiceMinutes;
  final int roomCount;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final divider = highContrast ? palette.borderStrong : palette.hairline;
    final items = <_JourneyItem>[
      _JourneyItem(
        icon: Icons.hub_rounded,
        label: copy.text('Servers joined', 'Serwery użytkownika'),
        value: '$communitiesCount',
        keyName: 'communities',
      ),
      _JourneyItem(
        icon: Icons.forum_rounded,
        label: copy.text('Messages', 'Wiadomości'),
        value: '$messageCount',
        keyName: 'messages',
      ),
      _JourneyItem(
        icon: Icons.graphic_eq_rounded,
        label: copy.text('Voice time', 'Czas rozmów'),
        value: _formatVoiceTime(voiceMinutes, copy),
        keyName: 'voice-time',
      ),
      _JourneyItem(
        icon: Icons.add_circle_outline_rounded,
        label: copy.text('Servers created', 'Utworzone serwery'),
        value: '$roomCount',
        keyName: 'rooms-created',
      ),
    ];

    return SizedBox(
      width: double.infinity,
      child: YoCard(
        key: const ValueKey('profile-journey-card'),
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The card's own width (its padding included) decides the form.
            final cardWidth = constraints.maxWidth + 32;
            final cells =
                cardWidth >= ProfileLayout.journeyCellsFromWidth &&
                !ProfileLayout.largeText(context);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: palette.interactiveForeground,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        copy.text(
                          'Your YO Voice journey',
                          'Twoja historia w YO Voice',
                        ),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 16,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.25,
                        ),
                      ),
                    ),
                  ],
                ),
                if (cells) ...[
                  const SizedBox(height: 14),
                  IntrinsicHeight(
                    key: const ValueKey('profile-journey-cells'),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var index = 0; index < items.length; index++) ...[
                          if (index > 0)
                            VerticalDivider(
                              width: 25,
                              thickness: 1,
                              color: divider,
                            ),
                          Expanded(child: _JourneyCell(item: items[index])),
                        ],
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  for (var index = 0; index < items.length; index++) ...[
                    if (index > 0)
                      Divider(height: 1, indent: 34, color: divider),
                    _JourneyRow(item: items[index]),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  static String _formatVoiceTime(int minutes, AppLocalizations copy) {
    if (minutes < 60) {
      return copy.text('${minutes}m', '$minutes min');
    }
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) return copy.text('${hours}h', '$hours godz.');
    return copy.text('${hours}h ${rest}m', '$hours godz. $rest min');
  }
}

/// A counter's value in tabular figures, so digits never jitter between
/// profiles.
const List<FontFeature> _tabular = <FontFeature>[FontFeature.tabularFigures()];

class _JourneyRow extends StatelessWidget {
  const _JourneyRow({required this.item});

  final _JourneyItem item;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final label = Text(
      item.label,
      style: TextStyle(
        color: palette.textSecondary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
    final value = Text(
      item.value,
      style: TextStyle(
        color: palette.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        fontFeatures: _tabular,
      ),
    );
    final icon = SizedBox(
      width: 24,
      child: Icon(item.icon, color: palette.interactiveForeground, size: 20),
    );
    // At large text a label and a long value ("21 godz. 5 min") cannot
    // share one line on a phone: the value goes under its label and both
    // keep every word.
    final stacked = ProfileLayout.largeText(context);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: item.label,
      value: item.value,
      child: ConstrainedBox(
        key: ValueKey('profile-journey-row-${item.keyName}'),
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: stacked
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: icon,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [label, const SizedBox(height: 2), value],
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    icon,
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: label.style,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      item.value,
                      maxLines: 1,
                      textAlign: TextAlign.end,
                      style: value.style,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// One of the four side-by-side counters: glyph and label on top, the value
/// below. Labels may take two lines on a narrow cell; the values of all four
/// cells stay on one line at the foot of the row.
class _JourneyCell extends StatelessWidget {
  const _JourneyCell({required this.item});

  final _JourneyItem item;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: item.label,
      value: item.value,
      child: Column(
        key: ValueKey('profile-journey-row-${item.keyName}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(item.icon, color: palette.interactiveForeground, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12,
                    height: 16 / 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // A long duration ("21 godz. 5 min") still fits a narrow cell:
          // its units drop to the label size, and a pathological value
          // scales down rather than truncating a real count.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text.rich(
              TextSpan(children: _valueSpans(item.value, palette)),
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
  }

  /// The value with its digits at 22 w700 (tabular) and any unit between
  /// them ("godz.", "min", "h") at 13 w600 in `textSecondary`. The plain
  /// text is exactly [value].
  static List<TextSpan> _valueSpans(String value, AppPalette palette) {
    final number = TextStyle(
      color: palette.textPrimary,
      fontSize: 22,
      height: 1.15,
      fontWeight: FontWeight.w700,
      letterSpacing: -.3,
      fontFeatures: _tabular,
    );
    final unit = TextStyle(
      color: palette.textSecondary,
      fontSize: 13,
      height: 1.15,
      fontWeight: FontWeight.w600,
    );
    return [
      for (final match in RegExp(r'\d+|\D+').allMatches(value))
        TextSpan(
          text: match[0],
          style: RegExp(r'^\d').hasMatch(match[0]!) ? number : unit,
        ),
    ];
  }
}

class _JourneyItem {
  const _JourneyItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.keyName,
  });

  final IconData icon;
  final String label;
  final String value;
  final String keyName;
}
