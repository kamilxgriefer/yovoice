import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/join_action_identity.dart';
import 'package:yovoice/features/moments/data/models/moment_chain.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// One friend's unheard Voice Moment chain, as the friends rail sees it.
///
/// Built ONLY from a page the caller already loaded: a chain lands here when
/// its author is a real friend, the Moment carries playable media, it has not
/// expired, and the caller has not listened to it yet. "No ring" therefore
/// means "nothing of yours in the page I loaded" — never "nothing exists" —
/// which is why the rail never prints a count of new Moments.
@immutable
class HomeFriendVoice {
  const HomeFriendVoice({required this.chain, required this.newest});

  /// Oldest → newest, the order the story viewer plays.
  final List<VoiceMoment> chain;

  /// The Moment whose duration the tile prints.
  final VoiceMoment newest;

  int get durationSeconds => newest.durationSeconds;

  String get durationLabel => newest.durationLabel;
}

/// Which friends have something new to hear, from a page the caller already
/// holds.
///
/// Four gates, all of them facts the client can check: the author is a real
/// FRIEND (never merely followed — the feed page is the following feed, and
/// reusing it for friends without this gate is the exact mislabel the package
/// warned about), the Moment carries playable media, it has not expired, and
/// the chain still contains something the caller has not listened to.
Map<String, HomeFriendVoice> homeFriendVoiceByAuthor({
  required List<VoiceMoment> page,
  required Set<String> friendIds,
  required Set<String> viewedMomentIds,
  required DateTime now,
}) {
  if (page.isEmpty || friendIds.isEmpty) return const {};
  final eligible = page
      .where(
        (moment) =>
            friendIds.contains(moment.authorId) &&
            moment.hasMediaReference &&
            moment.isActiveAt(now),
      )
      .toList(growable: false);
  if (eligible.isEmpty) return const {};
  final result = <String, HomeFriendVoice>{};
  for (final chain in buildMomentChains(eligible)) {
    if (!chain.hasUnviewed(viewedMomentIds)) continue;
    result[chain.authorId] = HomeFriendVoice(
      chain: chain.moments,
      newest: chain.moments.last,
    );
  }
  return result;
}

/// A friend on Home's "Twoi znajomi" rail.
///
/// Two independent facts, drawn as two independent marks, because they answer
/// different questions and must never be collapsed into one:
///
///  * the RING and the BADGE mean "there is new content you can hear" —
///    Home's own meaning for the cyan join identity;
///  * the DOT and the status word mean "this is their presence", straight
///    from `socialPresence`.
///
/// The 2 px ring slot is laid out whether or not a ring is painted, so a tile
/// never changes size when a Moment arrives or expires under the reader.
///
/// Deliberately NOT [PeopleStatusAvatar]: that component's ring means STATUS
/// everywhere else in the app (Friends, Chats, the profile preview) and it has
/// to keep meaning that there.
class HomeFriendTile extends StatelessWidget {
  const HomeFriendTile({
    required this.displayName,
    required this.status,
    required this.onOpenProfile,
    this.userId,
    this.photoUrl,
    this.mediaRevision,
    this.voice,
    this.onOpenVoice,
    this.statusLabel,
    this.semanticLabel,
    this.showChangeCaret = false,
    this.avatarRadius = 28,
    this.labelWidth,
    super.key,
  });

  final String displayName;
  final String? userId;
  final String? photoUrl;
  final Object? mediaRevision;

  /// Presence, from `socialPresence` only.
  final PeopleStatus status;

  /// Overrides the presence word (the own tile prints its chosen
  /// availability, which projected presence masks).
  final String? statusLabel;

  /// Replaces the default "name + presence" pair with one phrase. The own
  /// tile announces the same "Dostępność: …. Zmień" as `AvailabilityChip`,
  /// so one action keeps one label everywhere.
  final String? semanticLabel;

  /// Rides the status line with the "caret = change availability" grammar
  /// the chip and the Friends tile already use. Only the own tile sets it.
  final bool showChangeCaret;

  /// The unheard chain, when one exists.
  final HomeFriendVoice? voice;

  /// Opens that chain in the existing story viewer. Null keeps the tile on
  /// the profile route even if content exists.
  final ValueChanged<List<VoiceMoment>>? onOpenVoice;

  /// The profile preview: the tile's long-press, its accessible custom
  /// action, and its tap when there is nothing to play.
  final VoidCallback onOpenProfile;

  final double avatarRadius;
  final double? labelWidth;

  /// avatar + 2 px gap + 2 px ring on each side.
  double get discSize => avatarRadius * 2 + 8;

  double get _badgeSize => (discSize * 26 / 64).clamp(20.0, 34.0);

  double get _dotSize => (discSize * 12 / 64).clamp(10.0, 16.0);

  static const double _statusFontSize = 10.5;

  /// The narrowest column in which no single word of [label] has to break,
  /// measured in the style and text scale the status line actually renders
  /// with, plus the caret when it rides the line.
  ///
  /// Flutter breaks a word wider than its line rather than ellipsising it, so
  /// a fixed column turned "Nie przeszkadzać" into "Nie przesz / kadzać".
  static double statusColumnMinimumWidth(
    BuildContext context,
    String label, {
    required bool showCaret,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    final style = DefaultTextStyle.of(context).style.merge(
      const TextStyle(fontSize: _statusFontSize, fontWeight: FontWeight.w600),
    );
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
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final join = JoinAction.resolve(Theme.of(context).brightness);
    final content = voice;
    final presenceWord = statusLabel ?? status.localizedLabel(copy);
    final columnWidth =
        labelWidth ??
        MediaQuery.textScalerOf(context).scale(avatarRadius * 2.4);

    final tapsVoice = content != null && onOpenVoice != null;
    final semanticValue = content == null
        ? presenceWord
        : copy.template(
            'New Voice Moment, {duration}. {status}',
            'Nowy Voice Moment, {duration}. {status}',
            values: <String, Object>{
              'duration': copy.secondsCount(content.durationSeconds),
              'status': presenceWord,
            },
          );

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: semanticLabel ?? displayName,
      value: semanticLabel == null ? semanticValue : null,
      onTap: tapsVoice ? () => onOpenVoice!(content.chain) : onOpenProfile,
      // A screen-reader user cannot long-press, so the profile route is also
      // a named custom action whenever the tap belongs to the chain.
      customSemanticsActions: tapsVoice
          ? <CustomSemanticsAction, VoidCallback>{
              CustomSemanticsAction(
                label: copy.text('Open profile', 'Otwórz profil'),
              ): onOpenProfile,
            }
          : null,
      // The rail's shared ink and focus ring, plus the long-press that opens
      // the profile when the tap belongs to the chain. `PeopleTileInk` is a
      // Friends-owned component and takes no long-press of its own.
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onLongPress: onOpenProfile,
        child: PeopleTileInk(
          onTap: tapsVoice ? () => onOpenVoice!(content.chain) : onOpenProfile,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _disc(context, palette: palette, join: join, content: content),
              const SizedBox(height: AppRhythm.tight),
              SizedBox(
                width: columnWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                    _StatusLine(
                      label: content == null
                          ? presenceWord
                          : 'Voice ${content.durationLabel}',
                      foreground: palette.textSecondary,
                      showCaret: showChangeCaret,
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

  Widget _disc(
    BuildContext context, {
    required AppPalette palette,
    required JoinActionVisuals join,
    required HomeFriendVoice? content,
  }) {
    final hasContent = content != null;
    final badge = _badgeSize;
    final dot = _dotSize;
    return SizedBox(
      width: discSize,
      height: discSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The ring slot is ALWAYS 2 px: a hairline border when there is
          // nothing new, the join colour when there is. The disc therefore
          // never resizes when content arrives or expires.
          Container(
            width: discSize,
            height: discSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: hasContent ? join.ring : palette.border,
                width: 2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: UserAvatar(
                radius: avatarRadius,
                userId: userId,
                photoUrl: photoUrl,
                mediaRevision: mediaRevision,
                displayName: displayName,
              ),
            ),
          ),
          if (hasContent)
            PositionedDirectional(
              start: discSize - badge,
              top: discSize - badge,
              child: _ContentBadge(
                size: badge,
                fill: join.badge,
                ink: join.onBadge,
                border: palette.background,
              ),
            ),
          // Presence is a separate fact and stays visible either way: it
          // moves to the top when the badge owns the bottom corner.
          PositionedDirectional(
            start: discSize - dot,
            top: hasContent ? 0 : discSize - dot,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: status.foreground(palette),
                border: Border.all(color: palette.background, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The tile's second line: the presence word, or the Moment's length, with
/// the availability caret when this is the reader's own tile.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    required this.foreground,
    required this.showCaret,
  });

  final String label;
  final Color foreground;
  final bool showCaret;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 2,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: foreground,
        fontSize: HomeFriendTile._statusFontSize,
        fontWeight: FontWeight.w600,
      ),
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

/// The waveform badge that means "a Voice Moment you have not heard".
///
/// There is deliberately no Reel badge: `listReelsV2` exposes no friends or
/// author scope, so the app cannot know whether a friend has a Reel for you.
/// Omitting the mark is the honest state; drawing one would be a claim.
class _ContentBadge extends StatelessWidget {
  const _ContentBadge({
    required this.size,
    required this.fill,
    required this.ink,
    required this.border,
  });

  final double size;
  final Color fill;
  final Color ink;
  final Color border;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: fill,
      border: Border.all(color: border, width: 2),
    ),
    child: Center(
      child: Icon(Icons.graphic_eq_rounded, size: size * .54, color: ink),
    ),
  );
}
