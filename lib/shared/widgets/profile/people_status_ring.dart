import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/presence/user_availability.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Centralized status-ring language from the Home mockup — one place
/// defines what each ring color means, instead of ad-hoc colors per
/// widget.
///
/// Only statuses derivable from REAL data exist here. `speaking` /
/// `inRoom` / `inClub` are defined for when presence carries room
/// context (schema extension tracked in Roadmap) — nothing may pass
/// them speculatively.
enum PeopleStatus {
  speaking,
  inRoom,
  inClub,
  online,
  brb,
  busy,
  away;

  /// The one mapping from projected presence to a ring colour, used by every
  /// surface that shows another person's state (Home strip, Friends, chat
  /// header, profile preview). Offline always wins; the server has already
  /// masked "invisible" to offline, so it never reaches here.
  static PeopleStatus fromPresence({
    required bool isOnline,
    String? availability,
  }) {
    if (!isOnline) return PeopleStatus.away;
    return switch (availability) {
      'away' => PeopleStatus.brb,
      'busy' => PeopleStatus.busy,
      'offline' => PeopleStatus.away,
      _ => PeopleStatus.online,
    };
  }

  /// The ring an account sees for ITSELF, including invisible (grey).
  static PeopleStatus fromOwnAvailability(UserAvailability availability) =>
      switch (availability) {
        UserAvailability.available => PeopleStatus.online,
        UserAvailability.away => PeopleStatus.brb,
        UserAvailability.busy => PeopleStatus.busy,
        UserAvailability.invisible => PeopleStatus.away,
      };

  /// Theme-aware status ink used for both the ring and its visible label.
  ///
  /// The adjacent text label remains the primary status cue; colour reinforces
  /// that meaning without becoming the only way to distinguish the state.
  Color foreground(AppPalette palette) => switch (this) {
    PeopleStatus.speaking => palette.interactiveForeground,
    PeopleStatus.inRoom || PeopleStatus.online => palette.successForeground,
    PeopleStatus.inClub || PeopleStatus.brb => palette.warningForeground,
    PeopleStatus.busy => palette.dangerForeground,
    PeopleStatus.away => palette.textTertiary,
  };

  String get label => switch (this) {
    PeopleStatus.speaking => 'Speaking',
    PeopleStatus.inRoom => 'In a room',
    PeopleStatus.inClub => 'In a club',
    PeopleStatus.online => 'Online',
    PeopleStatus.brb => 'Be right back',
    PeopleStatus.busy => 'Do not disturb',
    PeopleStatus.away => 'Away',
  };

  /// Localized status copy used by both visible text and accessibility.
  /// [label] remains a stable English value for diagnostics and compatibility.
  String localizedLabel(AppLocalizations copy) => switch (this) {
    PeopleStatus.speaking => copy.text('Speaking', 'Mówi'),
    PeopleStatus.inRoom => copy.text('In a room', 'W pokoju'),
    PeopleStatus.inClub => copy.text('In a club', 'W klubie'),
    PeopleStatus.online => copy.text('Online', 'Dostępny'),
    PeopleStatus.brb => copy.text('Be right back', 'Zaraz wracam'),
    PeopleStatus.busy => copy.text('Do not disturb', 'Nie przeszkadzać'),
    PeopleStatus.away => copy.text('Away', 'Nieobecny'),
  };
}

/// Avatar + status ring + name + status label, as one column — the
/// "Your people" row unit.
class PeopleStatusAvatar extends StatelessWidget {
  const PeopleStatusAvatar({
    required this.displayName,
    this.userId,
    required this.status,
    required this.onTap,
    this.photoUrl,
    this.mediaRevision,
    this.radius = 30,
    this.statusLabel,
    this.semanticLabel,
    this.showChangeBadge = false,
    this.labelWidth,
    this.tilePadding = const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    super.key,
  });

  final String displayName;
  final String? userId;
  final PeopleStatus status;
  final VoidCallback onTap;
  final String? photoUrl;

  /// Cache-busting revision for the avatar, as the Home header passes it —
  /// the signed-in account's own tile must show a freshly saved photo.
  final Object? mediaRevision;
  final double radius;

  /// Overrides `status.localizedLabel`. The signed-in account's own tile
  /// prints its chosen availability ("Invisible"), where the projected
  /// status would say "Away".
  final String? statusLabel;

  /// Replaces the default "name, status" semantics with one phrase — the
  /// own tile announces the same "Availability: …. Change" as
  /// `AvailabilityChip`, so one action has one label everywhere.
  final String? semanticLabel;

  /// Adds the caret to the tile's own status line — the same
  /// "caret = change availability" grammar the chip uses.
  ///
  /// It used to be an 18 px disc overlapping the status ring: grey on grey,
  /// covering the one element that carries the tile's meaning, and implying
  /// a 16 px target that never existed (the whole tile is the target). The
  /// affordance now rides the status label, where it is legible and cannot
  /// smudge the avatar.
  final bool showChangeBadge;

  /// Width of the name/status column. Defaults to `radius * 2.4`; the
  /// desktop rail widens it so full names ellipsise less.
  final double? labelWidth;

  /// The tile's own outer padding. A rail that owns its pitch (Home's
  /// people strip) passes [EdgeInsets.zero] so the tile's layout box equals
  /// its ink box and the gap between tiles is the only spacing there is.
  final EdgeInsets tilePadding;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final active = status != PeopleStatus.away;
    final statusForeground = status.foreground(palette);
    final statusLabel = this.statusLabel ?? status.localizedLabel(copy);
    final borderRadius = BorderRadius.circular(18);
    final semanticLabel = this.semanticLabel;

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: semanticLabel ?? displayName,
      value: semanticLabel == null ? statusLabel : null,
      onTap: onTap,
      child: PeopleTileInk(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Padding(
          padding: tilePadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  shape: BoxShape.circle,
                  // A hairline ring in the palette-owned status colour:
                  // the label next to it carries the meaning, the ring
                  // only reinforces it. The colour stays the exact
                  // semantic token (it is contrast-checked at 3:1
                  // against this surface); what changed is the weight —
                  // 2.2/1.4 px rings read as heavy and cheap against the
                  // dark surfaces.
                  border: Border.all(
                    color: statusForeground,
                    width: active ? 1.5 : 1.1,
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: palette.shadow.withValues(alpha: .18),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: UserAvatar(
                  radius: radius,
                  userId: userId,
                  photoUrl: photoUrl,
                  mediaRevision: mediaRevision,
                  displayName: displayName,
                ),
              ),
              const SizedBox(height: AppRhythm.tight),
              SizedBox(
                // The column grows with the reader's text preference, the
                // same way the Moment story tile does: a fixed 62 px at
                // 200 % text left every name and status as an ellipsis.
                //
                // It is never narrower than the status's longest word:
                // Flutter breaks a word wider than its line, so "Nie
                // przeszkadzać" used to render as "Nie przesz / kadzać".
                width: math.max(
                  (labelWidth ?? radius * 2.4) +
                      (MediaQuery.textScalerOf(context).scale(10) / 10)
                              .clamp(1, 2)
                              .toDouble() *
                          36 -
                      36,
                  _StatusLine.minimumWidth(
                    context,
                    statusLabel,
                    showCaret: showChangeBadge,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppRhythm.hairline),
                    _StatusLine(
                      // Two lines: "Be right back" and "Do not disturb"
                      // do not fit one line inside the 62 px label column,
                      // and a status truncated to "Be right b…" is the one
                      // word the ring cannot say on its own.
                      label: statusLabel,
                      foreground: statusForeground,
                      // "Available ⌄" — the caret rides the words it is
                      // about rather than the avatar it used to smudge.
                      showCaret: showChangeBadge,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tile's status line, with the optional "change availability" caret.
///
/// The caret sits beside the status words, in the exact grammar
/// [AvailabilityChip] already ships (a `Flexible` label and an
/// `expand_more_rounded` glyph): legible, always present, and never over
/// the avatar. It used to be an 18 px disc overlapping the status ring —
/// grey on grey, covering the one element that carries the tile's meaning.
///
/// Deliberately NOT an inline `WidgetSpan` in the label's own paragraph:
/// an ellipsised line drops the span (the affordance would vanish exactly
/// when the label is longest), and an inline widget's global transform is
/// unresolvable at enlarged text, which quietly breaks anything that
/// measures the tile.
///
/// It carries no semantics of its own — the tile already announces
/// "You. Availability: {status}. Change".
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    required this.foreground,
    required this.showCaret,
  });

  final String label;
  final Color foreground;
  final bool showCaret;

  static const double _fontSize = 10.5;

  static const TextStyle _baseStyle = TextStyle(
    fontSize: _fontSize,
    fontWeight: FontWeight.w600,
  );

  /// The narrowest column in which no single word of [label] has to break,
  /// measured in the same style and text scale the line renders with, plus
  /// the caret when it rides the line.
  static double minimumWidth(
    BuildContext context,
    String label, {
    required bool showCaret,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    final style = DefaultTextStyle.of(context).style.merge(_baseStyle);
    final direction = Directionality.of(context);
    var widest = 0.0;
    for (final word in label.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    final caret = showCaret ? scaler.scale(12) + 2 : 0.0;
    return (widest + caret).ceilToDouble() + 1;
  }

  @override
  Widget build(BuildContext context) {
    final style = _baseStyle.copyWith(color: foreground);
    final text = Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: style,
    );
    if (!showCaret) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(child: text),
        const SizedBox(width: 2),
        ExcludeSemantics(
          child: Icon(
            Icons.expand_more_rounded,
            // Tracks the reader's text preference, the way the words do.
            size: MediaQuery.textScalerOf(context).scale(12),
            color: foreground,
          ),
        ),
      ],
    );
  }
}

/// The people rail's tap surface: the ink wash the tiles already had, plus
/// the app's semantic focus boundary.
///
/// A 14 % focus wash is a 1.2:1 change against the rail's own background —
/// invisible as an indicator. Keyboard focus therefore also paints the same
/// 2 px `palette.focus` boundary `AccessibleTapRegion` draws everywhere else,
/// on the tile's own rounded rect and without touching layout (the ring is a
/// non-hit-testing overlay, so the tile keeps its size and the wash stays as
/// a secondary cue).
///
/// It contributes no semantics of its own — the caller owns the button node.
class PeopleTileInk extends StatefulWidget {
  const PeopleTileInk({
    required this.onTap,
    required this.child,
    this.borderRadius,
    super.key,
  });

  final VoidCallback onTap;
  final Widget child;

  /// Defaults to the rail's 18 px tile radius.
  final BorderRadius? borderRadius;

  @override
  State<PeopleTileInk> createState() => _PeopleTileInkState();
}

class _PeopleTileInkState extends State<PeopleTileInk> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final borderRadius = widget.borderRadius ?? BorderRadius.circular(18);
    return Stack(
      children: [
        InkWell(
          onTap: widget.onTap,
          excludeFromSemantics: true,
          borderRadius: borderRadius,
          onFocusChange: (focused) {
            if (_focused != focused) setState(() => _focused = focused);
          },
          focusColor: palette.focus.withValues(alpha: .14),
          hoverColor: palette.interactiveForeground.withValues(alpha: .08),
          highlightColor: palette.interactiveForeground.withValues(alpha: .10),
          splashColor: palette.interactiveForeground.withValues(alpha: .12),
          child: widget.child,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(
                  color: _focused ? palette.focus : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
