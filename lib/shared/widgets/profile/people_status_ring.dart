import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
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
  away;

  /// Theme-aware status ink used for both the ring and its visible label.
  ///
  /// The adjacent text label remains the primary status cue; colour reinforces
  /// that meaning without becoming the only way to distinguish the state.
  Color foreground(AppPalette palette) => switch (this) {
    PeopleStatus.speaking => palette.interactiveForeground,
    PeopleStatus.inRoom || PeopleStatus.online => palette.successForeground,
    PeopleStatus.inClub => palette.warningForeground,
    PeopleStatus.away => palette.textTertiary,
  };

  String get label => switch (this) {
    PeopleStatus.speaking => 'Speaking',
    PeopleStatus.inRoom => 'In a room',
    PeopleStatus.inClub => 'In a club',
    PeopleStatus.online => 'Online',
    PeopleStatus.away => 'Away',
  };

  /// Localized status copy used by both visible text and accessibility.
  /// [label] remains a stable English value for diagnostics and compatibility.
  String localizedLabel(AppLocalizations copy) => switch (this) {
    PeopleStatus.speaking => copy.text('Speaking', 'Mówi'),
    PeopleStatus.inRoom => copy.text('In a room', 'W pokoju'),
    PeopleStatus.inClub => copy.text('In a club', 'W klubie'),
    PeopleStatus.online => copy.text('Online', 'Dostępny'),
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
    this.radius = 30,
    super.key,
  });

  final String displayName;
  final String? userId;
  final PeopleStatus status;
  final VoidCallback onTap;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final active = status != PeopleStatus.away;
    final statusForeground = status.foreground(palette);
    final statusLabel = status.localizedLabel(copy);
    final borderRadius = BorderRadius.circular(18);

    return Semantics(
      excludeSemantics: true,
      button: true,
      label: displayName,
      value: statusLabel,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        excludeFromSemantics: true,
        borderRadius: borderRadius,
        focusColor: palette.focus.withValues(alpha: .14),
        hoverColor: palette.interactiveForeground.withValues(alpha: .08),
        highlightColor: palette.interactiveForeground.withValues(alpha: .10),
        splashColor: palette.interactiveForeground.withValues(alpha: .12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  shape: BoxShape.circle,
                  // A hairline ring in the palette-owned status colour: the
                  // label next to it carries the meaning, the ring only
                  // reinforces it. The colour stays the exact semantic token
                  // (it is contrast-checked at 3:1 against this surface);
                  // what changed is the weight — 2.2/1.4 px rings read as
                  // heavy and cheap against the dark surfaces.
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
                  displayName: displayName,
                ),
              ),
              const SizedBox(height: 7),
              SizedBox(
                width: radius * 2.4,
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
                    const SizedBox(height: 2),
                    Text(
                      statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: statusForeground,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
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
