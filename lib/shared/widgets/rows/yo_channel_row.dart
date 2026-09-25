import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// One channel in a channel list (Slim redesign, phase 0).
///
/// The promotion of the server panel's `_ChannelTile`: a `ListTile` with the
/// panel's selected chrome (identity foreground over identity wash, 48 px
/// floor, 12 px content padding, `AppRadius.md`), a 21 px glyph the caller
/// resolves (`serverChannelIcon`, or a lock for a restricted channel) and a
/// name that takes one unwrapped line and elides — the trailing marker takes
/// its intrinsic width first, so a wrapped name broke mid-word in a 240 px
/// column.
///
/// The row owns drawing only. The caller owns the key (passed as [tileKey] so
/// it lands on the `ListTile` itself, which `test/server_workspace_test.dart`
/// reads by type), the glyph, every string, the selection colours and the tap
/// — which selects a channel and never joins one. The row adds no `Material`
/// of its own: the list's surface is what the selected wash composites over.
class YoChannelRow extends StatefulWidget {
  const YoChannelRow({
    required this.label,
    required this.icon,
    this.onTap,
    this.selected = false,
    this.selectedForeground,
    this.selectedWash,
    this.iconSemanticLabel,
    this.iconColor,
    this.subtitle,
    this.trailing,
    this.labelMaxLines = 1,
    this.minHeight = 48,
    this.tileKey,
    super.key,
  });

  /// The channel name, in the nominative, exactly as the document carries it.
  final String label;

  /// Already resolved by the caller: `serverChannelIcon(kind)`, or
  /// `Icons.lock_outline` for a restricted channel.
  final IconData icon;

  /// Selects the channel. Null draws an inert row (a template preview).
  final VoidCallback? onTap;

  final bool selected;

  /// The server template's identity ink and wash for the selected row.
  final Color? selectedForeground;
  final Color? selectedWash;

  /// Voiced by the glyph when it carries meaning on its own (the lock).
  final String? iconSemanticLabel;

  /// Overrides the glyph ink. Null lets the tile colour it (and lets
  /// [selectedForeground] take over while the row is selected).
  final Color? iconColor;

  /// A second line under the name: the access line in the management sheet,
  /// the live clock or the connected roster on a voice row.
  final Widget? subtitle;

  /// The live marker, the connection marker, a menu — never a participant
  /// count (ADR-177).
  final Widget? trailing;

  /// One line in a channel column, two on the home board, whose label is a
  /// sentence rather than a channel name.
  final int labelMaxLines;

  /// The floor, not the height: a subtitle grows the row past it.
  final double minHeight;

  /// The row's contract key. It is forwarded to the `ListTile` rather than
  /// held by this widget, because the finders that address a channel row read
  /// the tile's own fields.
  final Key? tileKey;

  @override
  State<YoChannelRow> createState() => _YoChannelRowState();
}

/// Keyboard focus is a 2 px [AppPalette.focus] edge on the row's own shape.
/// The theme's focus tint alone is about 1.25:1 against the list surface, so
/// a desktop or web user tabbing through a channel column could not see
/// where they were (WCAG 2.4.7); the server rail beside it already draws the
/// same ring through `AccessibleTapRegion`.
class _YoChannelRowState extends State<YoChannelRow> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'YoChannelRow');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    final focused = _focusNode.hasPrimaryFocus;
    if (focused != _focused) setState(() => _focused = focused);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListTile(
    key: widget.tileKey,
    focusNode: _focusNode,
    selected: widget.selected,
    selectedColor: widget.selectedForeground,
    selectedTileColor: widget.selectedWash,
    minTileHeight: widget.minHeight,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    shape: _focused
        ? RoundedRectangleBorder(
            borderRadius: AppRadius.md,
            side: BorderSide(color: context.appPalette.focus, width: 2),
          )
        : const RoundedRectangleBorder(borderRadius: AppRadius.md),
    leading: Icon(
      widget.icon,
      size: 21,
      color: widget.iconColor,
      semanticLabel: widget.iconSemanticLabel,
    ),
    title: Text(
      widget.label,
      style: AppTypography.bodyMedium,
      maxLines: widget.labelMaxLines,
      softWrap: widget.labelMaxLines > 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: widget.subtitle,
    trailing: widget.trailing,
    onTap: widget.onTap,
  );
}

/// One media channel (voice, stage, meeting) in a channel list.
///
/// [YoChannelRow] plus the liveness contract of ADR-177. **Before joining the
/// row draws only what the channel document carries**: the glyph, the name,
/// the `NA ŻYWO` marker the caller builds ([liveBadge], so the counted
/// `server-live-pill` key stays attached exactly once, inside its own
/// widget), the clock line ([liveSince]) and an optional join affordance.
/// Never an avatar, never a head count — `rooms/{roomId}`, `participants` and
/// `channelSessions` are closed to the client, so any face before joining
/// would be invented.
///
/// [participants] are drawn only while [connected] is true, because only then
/// do they come from `ServerSessionController.participants` — the provider's
/// own roster. The speaking ring is [AppColors.success] (Slim brief, Discord
/// section) and a muted microphone is a crossed glyph on the avatar's corner.
///
/// The row's own tap still only selects. Joining is the separate [onJoin]
/// control, which carries its own key so the channel scene's single
/// `server-join` CTA stays countable, and which steps aside when the row is
/// too narrow or the text too large to hold both the name and a button — the
/// scene's full-size CTA is one tap away and never hides. On a narrow row the
/// live marker itself moves under the name, beside the clock, so the name
/// always keeps [minLabelWidth].
class YoVoiceChannelRow extends StatelessWidget {
  const YoVoiceChannelRow({
    required this.label,
    required this.icon,
    this.onTap,
    this.selected = false,
    this.selectedForeground,
    this.selectedWash,
    this.iconSemanticLabel,
    this.liveBadge,
    this.liveSince,
    this.connected = false,
    this.connectedLabel,
    this.participants = const <YoVoiceRowParticipant>[],
    this.avatarBackground,
    this.onJoin,
    this.joinLabel,
    this.joinIcon = Icons.mic_none_rounded,
    this.joinKey,
    this.tileKey,
    this.attention,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool selected;
  final Color? selectedForeground;
  final Color? selectedWash;
  final String? iconSemanticLabel;

  /// A small marker the caller builds when something in this channel waits
  /// for this person (the Servers "waiting" dot over a stage's raised hands).
  /// Drawn first among the trailing markers, and carrying its own spoken
  /// label. Null draws nothing.
  final Widget? attention;

  /// The `NA ŻYWO` marker, built by the caller so its counted key lives in
  /// one place. Null when the channel document does not say live.
  final Widget? liveBadge;

  /// `od 19:40`, formatted by the caller from `liveness.startedAt`. Drawn
  /// verbatim under the name, never the quiet copy: a row that is not live
  /// says nothing rather than announcing silence.
  final String? liveSince;

  /// This person is in this channel right now.
  final bool connected;

  /// Voices the connection marker (`połączono`).
  final String? connectedLabel;

  /// The provider's roster. Ignored unless [connected].
  final List<YoVoiceRowParticipant> participants;

  /// The fill behind an avatar's initial (the template's icon surface).
  final Color? avatarBackground;

  /// Joins through the caller's existing session path. Null hides the
  /// control: a held server, a stage nobody may start, or a channel this
  /// person is already in.
  final VoidCallback? onJoin;

  /// Voices the join control (`Dołącz do rozmowy`, `Słuchaj`, `Oglądaj`,
  /// `Dołącz do spotkania`). It is a tooltip and a semantics label, so the
  /// control keeps its 44 px target at every text size.
  final String? joinLabel;
  final IconData joinIcon;
  final Key? joinKey;
  final Key? tileKey;

  /// Faces beyond this many collapse into a `+n` on the same line.
  static const int maxAvatars = 4;

  /// Below this row width the join control steps aside so the channel name
  /// keeps a readable measure. The phone sheet (296 px of row) and the
  /// desktop panel (240 / 256) are both on or above it; a 216 px tablet
  /// column is below it.
  static const double joinFloorWidth = 240;

  /// The `NA ŻYWO` marker sits beside the name only from this row width
  /// (scaled with the text). Below it the marker moves onto the line under
  /// the name, next to the clock: beside the name it takes about 90 px,
  /// which left a live channel's name 53 px wide in the 240 px desktop
  /// panel, and 3 px once the join control was added too.
  static const double liveTrailingFloorWidth = 288;

  /// The join control joins a live marker beside the name only from this
  /// row width (scaled with the text): marker, gap and 44 px control take
  /// about 150 px. Below it the scene's full-size CTA stays one tap away.
  static const double liveJoinFloorWidth = 340;

  /// The least width the name keeps next to every trailing marker at 1.0
  /// text. Pinned by `test/yo_channel_row_test.dart` at the panel and sheet
  /// widths.
  static const double minLabelWidth = 96;

  /// And above this scaled body size, where a 44 px control and a marker
  /// together leave a name of two or three letters.
  static const double joinFloorTextScale = 1.5;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final roster = connected ? participants : const <YoVoiceRowParticipant>[];
    final clock = liveSince;
    final clockText = clock == null
        ? null
        : Text(
            clock,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelSmall.copyWith(
              color: palette.textTertiary,
            ),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final width = constraints.maxWidth;
        final badge = connected ? null : liveBadge;
        final badgeBesideName =
            badge != null && width >= liveTrailingFloorWidth * textScale;
        final roomForJoin =
            onJoin != null &&
            width >= joinFloorWidth &&
            textScale <= joinFloorTextScale &&
            (badge == null || width >= liveJoinFloorWidth * textScale);
        final Widget? subtitle = roster.isNotEmpty
            ? _Roster(people: roster, background: avatarBackground)
            : badge != null && !badgeBesideName
            ? Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(child: badge),
                    if (clockText != null) ...[
                      const SizedBox(width: 6),
                      Flexible(child: clockText),
                    ],
                  ],
                ),
              )
            : clockText;
        final markers = <Widget>[
          if (attention != null) ...[attention!, const SizedBox(width: 6)],
          if (connected)
            Icon(
              Icons.graphic_eq_rounded,
              size: 18,
              color: palette.audioAccent,
              semanticLabel: connectedLabel,
            )
          else if (badgeBesideName)
            Flexible(child: badge),
          if (roomForJoin) ...[
            const SizedBox(width: 6),
            IconButton.filledTonal(
              key: joinKey,
              onPressed: onJoin,
              tooltip: joinLabel,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              style: IconButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
              ),
              icon: Icon(joinIcon, size: 18),
            ),
          ],
        ];

        return YoChannelRow(
          tileKey: tileKey,
          label: label,
          icon: icon,
          iconSemanticLabel: iconSemanticLabel,
          selected: selected,
          selectedForeground: selectedForeground,
          selectedWash: selectedWash,
          subtitle: subtitle,
          trailing: markers.isEmpty
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: markers),
          onTap: onTap,
        );
      },
    );
  }
}

/// One person the media provider reports in the channel this viewer is in.
///
/// A value object on purpose: the shared row never imports the servers
/// feature, so the caller maps `ServerMediaParticipant` — including the
/// localized [semanticLabel], which already reads `name, mówi` on the stage.
class YoVoiceRowParticipant {
  const YoVoiceRowParticipant({
    required this.userId,
    required this.displayName,
    this.isSpeaking = false,
    this.isMicrophoneEnabled = false,
    this.semanticLabel,
  });

  final String userId;
  final String displayName;
  final bool isSpeaking;
  final bool isMicrophoneEnabled;

  /// What a screen reader says for this face. Null falls back to the name.
  final String? semanticLabel;
}

/// The connected channel's faces: real people from the provider's roster,
/// with the speaking ring bound to `isSpeaking` and the crossed microphone to
/// `!isMicrophoneEnabled`. Neither is decorative and neither appears before
/// joining.
class _Roster extends StatelessWidget {
  const _Roster({required this.people, this.background});

  final List<YoVoiceRowParticipant> people;
  final Color? background;

  /// One face: a 22 px avatar, 2 px padding and a 2 px ring that is always
  /// there — speaking changes only its colour, so the roster never changes
  /// width on a speaking tick (the podcast stage keeps the same rule).
  static const double faceSize = 30;
  static const double faceGap = 4;
  static const double pitch = faceSize + faceGap;
  static const double ringWidth = 2;

  /// How many faces fit [maxWidth] next to the `+n` for the rest: never more
  /// than [YoVoiceChannelRow.maxAvatars], and never so many that the count
  /// is pushed out of the row.
  static int facesThatFit(
    int total,
    double maxWidth,
    double Function(int hidden) labelWidth,
  ) {
    final cap = total < YoVoiceChannelRow.maxAvatars
        ? total
        : YoVoiceChannelRow.maxAvatars;
    for (var shown = cap; shown > 0; shown--) {
      final hidden = total - shown;
      final needed =
          shown * pitch -
          (hidden > 0 ? 0 : faceGap) +
          (hidden > 0 ? labelWidth(hidden) : 0);
      if (needed <= maxWidth) return shown;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final labelStyle = AppTypography.labelSmall.copyWith(
      color: palette.textTertiary,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double labelWidth(int hidden) {
      final painter = TextPainter(
        text: TextSpan(text: '+$hidden', style: labelStyle),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width.ceilToDouble();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = facesThatFit(
            people.length,
            constraints.maxWidth,
            labelWidth,
          );
          final shown = people.take(count).toList();
          final overflow = people.length - shown.length;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final person in shown)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: faceGap),
                  child: Semantics(
                    label: person.semanticLabel ?? person.displayName,
                    child: ExcludeSemantics(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: person.isSpeaking
                                    ? AppColors.success
                                    : palette.border,
                                width: ringWidth,
                              ),
                            ),
                            child: UserAvatar(
                              radius: 11,
                              userId: person.userId,
                              displayName: person.displayName,
                              backgroundColor:
                                  background ?? palette.surfaceSunken,
                            ),
                          ),
                          if (!person.isMicrophoneEnabled)
                            PositionedDirectional(
                              end: -1,
                              bottom: -1,
                              child: Container(
                                padding: const EdgeInsets.all(1),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: palette.surface,
                                ),
                                child: Icon(
                                  Icons.mic_off_rounded,
                                  size: 11,
                                  color: palette.textTertiary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (overflow > 0)
                Flexible(
                  child: Text(
                    '+$overflow',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: labelStyle,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
