import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/likers/data/models/likers_target.dart';
import 'package:yovoice/features/likers/presentation/likers_copy.dart';
import 'package:yovoice/features/likers/presentation/likers_launcher.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_discover_tiles.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_pill.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_time_labels.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/interactions/yo_press_feedback.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/voice/voice_player_row.dart'
    show VoiceBeadGlyph, VoicePourWaveform, voiceBeadStartHaptic;

/// The width line 1 keeps for the author's badges when deciding whether
/// the age fits beside the name: one 16 px icon badge (a second one, rare,
/// is taken from the name).
const double _badgeAllowance = 16;

/// The narrowest the name may become for the age to stay on line 1: past
/// this the age leaves the line instead of both being cut.
const double _nameFloor = 96;

/// The unheard dot at 100 % text, and the canvas ring drawn around it.
const double _unheardDot = 8;
const double _unheardDotOutline = 1.5;

/// The feed's one audio transport as every row reads it: which Moment is
/// the controller's current clip, and what that clip is doing.
///
/// Only mounted rows listen. Playback ticks never reorder the feed or
/// recreate an audio player for an offscreen row.
@immutable
class MomentFeedPlayback {
  const MomentFeedPlayback({
    this.id,
    this.playing = false,
    this.busy = false,
    this.elapsed = Duration.zero,
    this.duration,
    this.error,
    this.seek = 0,
  });

  final String? id;
  final bool playing;
  final bool busy;
  final Duration elapsed;
  final Duration? duration;
  final String? error;

  /// The feed's seek generation: a change snaps the poured waveform.
  final int seek;
}

/// The caption publishing writes when the author typed none
/// (`MomentService.publishRecordedMoment`).
const String momentFallbackCaption = 'Voice Moment';

/// True when [caption] carries nothing the author wrote: empty, or the
/// "Voice Moment" fallback publishing stores in its place. The row omits
/// its caption line then; the format is already named by the switch.
bool momentCaptionIsFallback(String caption) {
  final trimmed = caption.trim();
  return trimmed.isEmpty || trimmed == momentFallbackCaption;
}

String _clock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
}

/// A label that continues a sentence ("0:12 · wygasa za 5 dni") starts in
/// lower case; the stored copy keeps its capital for the places it opens.
String _midSentence(String label) =>
    label.isEmpty ? label : label[0].toLowerCase() + label.substring(1);

/// One Voice Moment in the Głos list (G4): a compact row that opens into
/// the player when it becomes the controller's current clip.
///
/// **Collapsed** (the default): no card — a 16 px gutter, a hairline under
/// the row, min 76 px. A 44 px avatar (no ring; it opens the author's
/// chain, as the old card's avatar did), the name with the identity badges,
/// the real age and — while the viewer has not heard someone else's Moment
/// — a dot that grows with the text; the caption on one line (omitted when
/// the author typed none); the meta line (real duration · ♡ real like count
/// · 💬 real comment count · the existing expiry copy, amber in the last
/// hour); and a 44 px outline play button. The row body opens the Moment
/// sheet, exactly as the card body did, so like, comments, report, delete
/// and the download all stay one tap away; a long press or a secondary
/// click opens the ⋯ menu, and like / reply / more are Semantics custom
/// actions.
///
/// **Expanded** (the current clip: playing, paused mid-way, loading, failed
/// or finished): the full caption (three lines), the availability line
/// (the expiry never disappears as the row opens), the play button turns
/// into the R14 voice bead (lit only while the clip plays), the poured
/// waveform with the transparent seek slider and the clock, and the action
/// line — like, comments, "Odpowiedz głosem", share and ⋯. Only one row is
/// ever expanded, because only one clip is ever current. While it PLAYS the
/// row wears the screen's one tint: primary fading from its leading edge.
///
/// **A finished clip stays open at its end** ("0:12 / 0:12", the bead at
/// rest) until another clip starts, the row scrolls out of view or the
/// reader leaves the screen; Play then starts it again from the beginning.
///
/// **One semantics node per row**: the body's focus merges into the named
/// row button (its tap and the three custom actions), so the node keyboard
/// focus lands on is the one that says what the row is. The avatar, the
/// play control, the seek and the action line are buttons of their own.
///
/// The collapsed and expanded rows share one element tree above the play
/// button, so a keyboard user who presses it keeps focus on it as the row
/// opens — the button stays enabled (and says "Ładowanie…") while its clip
/// loads.
class MomentCompactRow extends StatefulWidget {
  const MomentCompactRow({
    required this.moment,
    required this.seen,
    required this.isOwn,
    required this.canInteract,
    required this.canLike,
    required this.likePending,
    required this.current,
    required this.playback,
    required this.lit,
    required this.inset,
    required this.onRowBuild,
    required this.onRowDispose,
    required this.onTap,
    required this.onPlay,
    required this.onSeek,
    required this.onLike,
    required this.onComments,
    required this.onOpenChain,
    required this.onOpenDetail,
    required this.onShare,
    required this.onReport,
    required this.onDelete,
    required this.onReplyVoice,
    this.onOpenProfile,
    this.divider = true,
    this.clip,
    this.onCanvas = true,
    this.likersLauncher = const LikersLauncher(),
    super.key,
  });

  final VoiceMoment moment;

  /// The caller's own `momentViews` doc exists for this Moment.
  final bool seen;
  final bool isOwn;

  /// A signed-in viewer (nothing here works for nobody).
  final bool canInteract;
  final bool canLike;
  final bool likePending;

  /// The id of the controller's current clip — changes on play, a switch
  /// or a stop, never on a position tick. It decides which row is open.
  final ValueListenable<String?> current;

  /// The transport's full state, position included. Only the open row
  /// listens to it.
  final ValueListenable<MomentFeedPlayback> playback;

  /// The id of the one clip that is actually playing (the energy notifier):
  /// the only row that wears the tint.
  final ValueListenable<String?> lit;

  /// The horizontal gutter inside the row.
  final double inset;

  /// The row's context, for the feed's visibility checks.
  final void Function(String, BuildContext) onRowBuild;
  final void Function(String, BuildContext) onRowDispose;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onLike;
  final VoidCallback onComments;
  final VoidCallback onOpenChain;
  final VoidCallback onOpenDetail;
  final VoidCallback onShare;
  final VoidCallback onReport;
  final VoidCallback onDelete;
  final VoidCallback onReplyVoice;

  /// The author's profile preview, offered in the ⋯ menu (the name is not a
  /// target of its own in a 76 px row).
  final VoidCallback? onOpenProfile;

  /// The hairline under the row (every row but the last).
  final bool divider;

  /// Rounds the row's own paint (the tint, the ink) where it is the first
  /// or last row of a rounded block.
  final BorderRadius? clip;

  /// The row sits straight on the page canvas — the backdrop photo below
  /// 1100 — rather than on the desktop block's `surface`. Its 12 px
  /// secondary text (age, meta, availability) then takes `textSecondary`:
  /// `textTertiary` measured 3.86–4.31:1 over the photo's brightest pixels.
  final bool onCanvas;

  /// Opens "See who liked" from the ⋯ menu and the screen-reader action
  /// (ADR-230). The meta line's count stays inert: it is a span inside the
  /// row's one merged label (G4). The const default runs the real flow;
  /// tests pass seams.
  final LikersLauncher likersLauncher;

  static const double minHeight = 76;
  static const double avatarDiameter = 44;
  static const double waveformHeight = 26;
  static const double seekHeight = 44;

  @override
  State<MomentCompactRow> createState() => _MomentCompactRowState();
}

class _MomentCompactRowState extends State<MomentCompactRow> {
  bool _focused = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'Voice Moment row');

  void _focusChanged(bool _) {
    // Only the row's OWN focus rings the row: a focused control inside it
    // draws its own ring.
    final focused = _focusNode.hasPrimaryFocus;
    if (focused != _focused) setState(() => _focused = focused);
  }

  void _afterMenu(VoidCallback action) {
    // A menu returns its selection before the route's inherited state has
    // rebuilt. Dispatch after that frame, retaining all destination guards.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  bool get _uploading => !widget.moment.isPublished;

  /// The ⋯ menu exists for a published Moment a signed-in viewer can act on
  /// and, always, for the author's own draft (Delete is its only exit).
  bool get _menuAvailable =>
      (widget.canInteract && !_uploading) ||
      (widget.isOwn && widget.canInteract);

  /// Opens the ⋯ menu — from a long press or a secondary click (at
  /// [globalPosition]), from the open row's ⋯ button ([anchor]), or from a
  /// screen reader's "More" (at the row's trailing edge).
  ///
  /// The menu is always opened and answered by the ROW: opening it covers
  /// the feed, which releases the player and closes an open row — a menu
  /// owned by the action line would be unmounted before it could answer.
  Future<void> _openMenu({Offset? globalPosition, BuildContext? anchor}) async {
    if (!_menuAvailable) return;
    final box = context.findRenderObject();
    final overlay = Navigator.maybeOf(
      context,
    )?.overlay?.context.findRenderObject();
    if (box is! RenderBox || overlay is! RenderBox || !box.hasSize) return;
    final RelativeRect position;
    final button = anchor?.findRenderObject();
    if (button is RenderBox && button.hasSize) {
      position = RelativeRect.fromRect(
        Rect.fromPoints(
          button.localToGlobal(Offset.zero, ancestor: overlay),
          button.localToGlobal(
            button.size.bottomRight(Offset.zero),
            ancestor: overlay,
          ),
        ),
        Offset.zero & overlay.size,
      );
    } else {
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final point =
          globalPosition ??
          box.localToGlobal(
            Offset(
              rtl ? widget.inset : box.size.width - widget.inset,
              box.size.height / 2,
            ),
          );
      position = RelativeRect.fromRect(
        overlay.globalToLocal(point) & const Size(1, 1),
        Offset.zero & overlay.size,
      );
    }
    await MomentOverflowMenu.showAt(
      context,
      position: position,
      moment: widget.moment,
      isOwn: widget.isOwn,
      uploading: _uploading,
      keyPrefix: 'moment-row',
      onOpenDetail: () => _afterMenu(widget.onOpenDetail),
      onReport: () => _afterMenu(widget.onReport),
      onDelete: () => _afterMenu(widget.onDelete),
      onOpenProfile: _profileAction,
      onShowLikers: _likersAction,
    );
  }

  /// "See who liked" in the ⋯ menu and as a screen-reader action: a
  /// published Moment with likes, for a signed-in viewer.
  VoidCallback? get _likersAction {
    if (_uploading || !widget.canInteract) return null;
    if (widget.moment.likeCount <= 0) return null;
    return () => _afterMenu(_openLikers);
  }

  void _openLikers() {
    final moment = widget.moment;
    unawaited(
      widget.likersLauncher.open(
        context,
        VoiceMomentLikersTarget(moment.id),
        totalCount: moment.likeCount,
        returnFocus: _focusNode,
      ),
    );
  }

  /// "View profile" in the ⋯ menu, for a published Moment only.
  VoidCallback? get _profileAction {
    final open = widget.onOpenProfile;
    if (open == null || _uploading || !widget.canInteract) return null;
    return () => _afterMenu(open);
  }

  @override
  void dispose() {
    widget.onRowDispose(widget.moment.id, context);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.onRowBuild(widget.moment.id, context);
    return ValueListenableBuilder<String?>(
      valueListenable: widget.current,
      builder: (context, currentId, _) =>
          _buildRow(context, expanded: currentId == widget.moment.id),
    );
  }

  Widget _buildRow(BuildContext context, {required bool expanded}) {
    final moment = widget.moment;
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final uploading = _uploading;
    final enabled = widget.canInteract && !uploading;
    final age = uploading
        ? ''
        : momentRelativeAge(moment.createdAt, copy: copy);
    final availability = uploading
        ? copy.text('Uploading…', 'Przesyłanie…')
        : widget.isOwn
        ? momentAvailabilityLabel(moment.expiresAt, copy: copy)
        : momentExpiryLabel(moment.expiresAt, copy: copy);
    final hasCaption = !momentCaptionIsFallback(moment.caption);
    // Line 1 carries the unheard dot for someone else's published Moment
    // the viewer has not heard; the row's name says "new" for it too.
    final showDot = !widget.seen && !uploading && !widget.isOwn;
    // The 12 px secondary ink: textSecondary on the page canvas (the photo
    // below 1100), textTertiary on the desktop block's surface.
    final quietInk = widget.onCanvas
        ? palette.textSecondary
        : palette.textTertiary;

    final avatar = MergeSemantics(
      // The tap region's own focus node would otherwise be a second,
      // unnamed focusable node beside the named button: merged, the face
      // is ONE node — the name, the button, the tap and the focus.
      child: AccessibleTapRegion(
        key: ValueKey('moment-row-chain-${moment.id}'),
        circular: true,
        onTap: enabled ? widget.onOpenChain : null,
        minimumSize: const Size.square(MomentCompactRow.avatarDiameter),
        semanticLabel: widget.isOwn
            // Your own chain is never "not heard yet": ADR-155's state is
            // about someone else's Moments.
            ? copy.text('Open your story chain', 'Otwórz swoją relację')
            : '${copy.template('Open the story chain by {name}', 'Otwórz relację użytkownika {name}', values: <String, Object>{'name': moment.authorName})}, '
                  '${MomentSeenAvatar.stateLabel(context, seen: widget.seen)}',
        child: ExcludeSemantics(
          child: MediaQuery(
            // The initial is a graphic sized off the disc, never copy.
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.noScaling),
            child: UserAvatar(
              radius: MomentCompactRow.avatarDiameter / 2,
              userId: moment.authorId,
              photoUrl: moment.authorPhotoUrl,
              displayName: moment.authorName,
              finish: UserAvatarFinish.brand,
            ),
          ),
        ),
      ),
    );

    // Line 1: name, badges, real age, the unheard dot. Everything the row
    // label already says is excluded here, so a reader hears it once.
    final textScaler = MediaQuery.textScalerOf(context);
    final nameStyle = AppTypography.rowTitleUnread.copyWith(
      color: palette.textPrimary,
      height: 1.25,
    );
    final ageStyle = AppTypography.bodySmall.copyWith(color: quietInk);
    // At an accessibility text size the age always leaves line 1.
    final largeText = textScaler.scale(1) >= 1.6;
    // The dot grows with the words beside it (8 px at 100 %).
    final dot = textScaler
        .scale(_unheardDot)
        .clamp(_unheardDot, 2 * _unheardDot);

    // The age stays on line 1 only while the name keeps a readable width
    // beside it (its whole width, or at least [_nameFloor]); otherwise it
    // leaves the line whole — opening the meta line — rather than being cut
    // to "40 min te…".
    bool ageFitsLine1(double width) {
      if (largeText) return false;
      if (age.isEmpty) return true;
      double measure(String text, TextStyle style) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: textScaler,
          maxLines: 1,
        )..layout();
        final result = painter.width;
        painter.dispose();
        return result;
      }

      final nameWidth = measure(moment.authorName, nameStyle);
      final beside =
          AppRhythm.hairline +
          _badgeAllowance +
          6 +
          measure(age, ageStyle) +
          (showDot ? 6 + dot + 2 * _unheardDotOutline : 0);
      // Never less than a second badge's width, so an author with two
      // badges squeezes the name, never overflows the line.
      return width - beside >=
          math.max(math.min(nameWidth, _nameFloor), _badgeAllowance + 3);
    }

    Widget identity({required bool ageInline}) => Row(
      children: <Widget>[
        Flexible(
          child: ExcludeSemantics(
            child: Text(
              moment.authorName,
              key: ValueKey('moment-row-name-${moment.id}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: nameStyle,
            ),
          ),
        ),
        const SizedBox(width: AppRhythm.hairline),
        UserIdentityBadges(
          uid: moment.authorId,
          variant: IdentityBadgeVariant.icon,
        ),
        // At its natural width: a second Flexible would split the free
        // width with the name and cut the age although both fit.
        if (age.isNotEmpty && ageInline) ...<Widget>[
          const SizedBox(width: 6),
          ExcludeSemantics(
            child: Text(
              age,
              key: ValueKey('moment-row-age-${moment.id}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ageStyle,
            ),
          ),
        ],
        if (showDot) ...<Widget>[
          const SizedBox(width: 6 + _unheardDotOutline),
          ExcludeSemantics(
            child: Container(
              key: ValueKey('moment-row-unheard-${moment.id}'),
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: highContrast
                    ? Theme.of(context).colorScheme.primary
                    : AppColors.secondary,
                // A canvas-coloured ring around it keeps the dot's 3:1
                // against whatever the backdrop photo puts behind it (it
                // measured 2.99:1 over the neon sign without one).
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: palette.background,
                    spreadRadius: _unheardDotOutline,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );

    final caption = hasCaption
        ? ExcludeSemantics(
            child: Text(
              moment.caption.trim(),
              key: ValueKey('moment-row-caption-${moment.id}'),
              maxLines: expanded ? 3 : 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium.copyWith(
                color: expanded ? palette.textPrimary : palette.textSecondary,
                height: 1.35,
              ),
            ),
          )
        : null;

    final text = LayoutBuilder(
      builder: (context, constraints) {
        final ageInline = ageFitsLine1(constraints.maxWidth);
        final ageAway = !ageInline && age.isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            identity(ageInline: ageInline),
            if (caption != null) ...<Widget>[
              const SizedBox(height: 2),
              caption,
            ],
            const SizedBox(height: 2),
            // Collapsed: the whole meta line. Open: the length and the
            // counters live in the player and the action line, so only the
            // availability stays — the expiry (amber in its last hour) and
            // the author's own states never disappear as the row opens.
            _RowMeta(
              key: ValueKey('moment-row-meta-${moment.id}'),
              moment: moment,
              leading: ageAway ? age : null,
              availability: availability,
              countdown: !uploading,
              ink: quietInk,
              availabilityOnly: expanded,
            ),
          ],
        );
      },
    );

    final Widget trailing = uploading && widget.isOwn
        // A draft has nothing to play yet; its trailing control is the ⋯
        // menu, where Delete — the author's only exit — lives.
        ? SizedBox.square(
            dimension: MomentRowTransportButton.size,
            child: MomentOverflowMenu(
              moment: moment,
              isOwn: widget.isOwn,
              uploading: uploading,
              keyPrefix: 'moment-row',
              iconSize: 22,
              icon: Icons.more_horiz_rounded,
              onOpenDetail: () => _afterMenu(widget.onOpenDetail),
              onReport: () => _afterMenu(widget.onReport),
              onDelete: () => _afterMenu(widget.onDelete),
            ),
          )
        : MomentRowTransportButton(
            buttonKey: ValueKey('moment-row-play-${moment.id}'),
            momentId: moment.id,
            expanded: expanded,
            playback: widget.playback,
            enabled: enabled && moment.hasMediaReference,
            onPressed: widget.onPlay,
            durationSeconds: moment.durationSeconds,
          );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.inset),
          child: Row(
            crossAxisAlignment: expanded
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: <Widget>[
              avatar,
              const SizedBox(width: AppRhythm.item),
              Expanded(child: text),
              const SizedBox(width: AppRhythm.item),
              trailing,
            ],
          ),
        ),
        if (expanded) ...<Widget>[
          const SizedBox(height: 3),
          _ControlStrip(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.inset),
              child: _RowTransport(
                moment: moment,
                playback: widget.playback,
                enabled: enabled && moment.hasMediaReference,
                onSeek: widget.onSeek,
                onRetry: widget.onPlay,
              ),
            ),
          ),
          const SizedBox(height: AppRhythm.hairline),
          _ControlStrip(
            child: Padding(
              // The action line's first glyph sits on the avatar's edge; its
              // last on the bead's.
              padding: EdgeInsetsDirectional.only(
                start: (widget.inset - 10).clamp(0, widget.inset),
                end: (widget.inset - 14).clamp(0, widget.inset),
              ),
              child: _RowActions(
                moment: moment,
                enabled: enabled,
                canLike: widget.canLike && !widget.likePending,
                onLike: widget.onLike,
                onComments: widget.onComments,
                onReplyVoice: widget.onReplyVoice,
                onShare: widget.onShare,
                onMore: _menuAvailable
                    ? (button) => unawaited(_openMenu(anchor: button))
                    : null,
              ),
            ),
          ),
        ],
      ],
    );

    final actions = <CustomSemanticsAction, VoidCallback>{
      if (enabled && widget.canLike && !widget.likePending)
        CustomSemanticsAction(
          label: moment.callerLiked
              ? copy.text('Unlike this Moment', 'Usuń polubienie tego Momentu')
              : copy.text('Like this Moment', 'Polub ten Moment'),
        ): widget.onLike,
      if (enabled)
        CustomSemanticsAction(
          label: copy.text('Reply with voice', 'Odpowiedz głosem'),
        ): widget.onReplyVoice,
      if (_likersAction != null)
        CustomSemanticsAction(label: LikersCopy(copy).seeWhoLiked): _openLikers,
      if (_menuAvailable)
        CustomSemanticsAction(
          label: copy.text('More options', 'Więcej opcji'),
        ): () =>
            unawaited(_openMenu()),
    };

    final dividerColor = highContrast ? palette.borderStrong : palette.hairline;
    Widget row = Stack(
      children: <Widget>[
        // The tint is always in the tree (transparent unless this clip is
        // PLAYING), so lighting the row never changes the structure above
        // its content — the play button keeps its element and its focus.
        Positioned.fill(
          child: IgnorePointer(
            child: _LitWash(momentId: moment.id, lit: widget.lit),
          ),
        ),
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey('moment-row-body-${moment.id}'),
            onTap: widget.canInteract ? widget.onTap : null,
            onLongPress: _menuAvailable ? () => unawaited(_openMenu()) : null,
            onSecondaryTapUp: _menuAvailable
                ? (details) => unawaited(
                    _openMenu(globalPosition: details.globalPosition),
                  )
                : null,
            // The node above carries this same action under the row's own
            // name; a second, unnamed tap node under it is what a screen
            // reader would read instead.
            excludeFromSemantics: true,
            focusNode: _focusNode,
            onFocusChange: _focusChanged,
            splashFactory: momentBlockSplashFactory,
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return palette.interactiveForeground.withValues(alpha: .10);
              }
              if (states.contains(WidgetState.hovered)) {
                return palette.isDark
                    ? palette.textPrimary.withValues(alpha: .04)
                    : palette.interactiveForeground.withValues(alpha: .05);
              }
              return Colors.transparent;
            }),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: MomentCompactRow.minHeight,
              ),
              child: Padding(
                padding: expanded
                    ? const EdgeInsets.only(top: 14, bottom: 6)
                    : const EdgeInsets.symmetric(vertical: 10),
                child: content,
              ),
            ),
          ),
        ),
        // Keyboard focus on the row's own target: a 2 px ring at radius 16
        // (R16), a foreground, so nothing moves.
        Positioned.fill(
          child: IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: DecoratedBox(
                key: ValueKey('moment-row-focus-${moment.id}'),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  border: Border.all(
                    color: _focused ? palette.focus : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    final clip = widget.clip;
    if (clip != null) row = ClipRRect(borderRadius: clip, child: row);

    // The relative age when there is one; the availability line is the
    // honest stand-in while a Moment is still uploading.
    final spokenAge = age.isEmpty ? (availability ?? '') : age;
    final name = hasCaption
        ? copy.template(
            'Open Voice Moment: {caption}, {author}, {age}',
            'Otwórz Voice Moment: {caption}, {author}, {age}',
            values: <String, Object>{
              'caption': moment.caption.trim(),
              'author': moment.authorName,
              'age': spokenAge,
            },
          )
        // No caption: never "Voice Moment: Voice Moment".
        : copy.template(
            'Open Voice Moment by {author}, {age}',
            'Otwórz Voice Moment: {author}, {age}',
            values: <String, Object>{
              'author': moment.authorName,
              'age': spokenAge,
            },
          );
    return Semantics(
      container: true,
      // The row's ONE node is the one that takes keyboard focus: the body's
      // focus flags (the ink's Focus) merge into it, so the focused node is
      // the named button with its tap and its three custom actions — never
      // an unnamed node beside it. The avatar, the play control, the seek
      // and the action line are buttons of their own and stay separate;
      // the meta line joins the name (the length, the counts and the
      // availability are part of what the row is).
      button: enabled,
      onTap: widget.canInteract ? widget.onTap : null,
      customSemanticsActions: actions.isEmpty ? null : actions,
      label: showDot
          ? '$name, ${copy.contextualText('yoMoments.unheardRowState', 'new', 'nowy')}'
          : name,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: widget.divider
              ? Border(bottom: BorderSide(color: dividerColor))
              : null,
        ),
        child: row,
      ),
    );
  }
}

/// The open row's player and action lines are control strips, not row
/// body: a tap between their controls — or on one that is inert for the
/// moment (a like whose write is in flight, the seek while the grant
/// resolves) — does nothing, instead of falling through to the row and
/// opening the Moment sheet over the clip that is playing; a long press or
/// a secondary click there does not open the row's ⋯ menu.
class _ControlStrip extends StatelessWidget {
  const _ControlStrip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    onTap: () {},
    // A long press or a secondary click in the player or the action line
    // is not a request for the row's ⋯ menu either: the row's own ones
    // would otherwise win from here and cover the playing clip.
    onLongPress: () {},
    onSecondaryTapUp: (_) {},
    child: child,
  );
}

/// The screen's one tint, on the row whose clip is PLAYING: primary at the
/// palette's tint alpha (.16 Dark / .09 Pearl) fading out across three
/// quarters of the row from its leading edge. Light comes in over 180 ms
/// and leaves over 320 ms, instantly under Reduce Motion; high contrast
/// draws none.
class _LitWash extends StatelessWidget {
  const _LitWash({required this.momentId, required this.lit});

  final String momentId;
  final ValueListenable<String?> lit;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    if (MediaQuery.highContrastOf(context)) {
      return const SizedBox.expand();
    }
    return ValueListenableBuilder<String?>(
      valueListenable: lit,
      builder: (context, litId, _) {
        final on = litId == momentId;
        final duration = AppMotion.decorative(context)
            ? (on ? YoGradientDisc.litIn : YoGradientDisc.litOut)
            : Duration.zero;
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: on ? 1 : 0),
          duration: duration,
          curve: AppMotion.standardCurve,
          builder: (context, t, _) => DecoratedBox(
            key: ValueKey('moment-row-lit-$momentId'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: <Color>[
                  AppColors.primary.withValues(alpha: palette.tintAlpha * t),
                  AppColors.primary.withValues(alpha: 0),
                ],
                stops: const <double>[0, .75],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The collapsed row's third line: real duration · ♡ real like count ·
/// 💬 real comment count · the existing expiry copy (amber in the last
/// hour). Zero counts are not printed — an invented "0" is fake activity.
///
/// Drawn as glyphs with bare numbers, spoken as phrases (ADR-186): the node
/// reads "0:12, Likes: 3, Comments: 2, Expires in 23h". A written phrase
/// ("2 komentarze") pushed the four facts onto two lines at 390; the glyph
/// keeps the row at its 76 px.
///
/// **The one-hour mark is the line's own**, as it is the expiry pill's: one
/// one-shot timer (re-armed in steps of at most a day) repaints it amber.
class _RowMeta extends StatefulWidget {
  const _RowMeta({
    required this.moment,
    required this.availability,
    required this.countdown,
    required this.ink,
    this.leading,
    this.availabilityOnly = false,
    super.key,
  });

  final VoiceMoment moment;

  /// Opens the line when line 1 has no room for it (the age at an
  /// accessibility text size). Not spoken here: the row label says it.
  final String? leading;
  final String? availability;
  final bool countdown;

  /// The line's ink (and its glyphs'): `textSecondary` on the canvas,
  /// `textTertiary` on the desktop block.
  final Color ink;

  /// The open row's line: the availability alone (the length and the
  /// counters are the player's and the action line's there).
  final bool availabilityOnly;

  @override
  State<_RowMeta> createState() => _RowMetaState();
}

class _RowMetaState extends State<_RowMeta> {
  Timer? _urgentTimer;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(covariant _RowMeta oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moment.expiresAt != widget.moment.expiresAt ||
        oldWidget.countdown != widget.countdown) {
      _arm();
    }
  }

  void _arm() {
    _urgentTimer?.cancel();
    _urgentTimer = null;
    final expiresAt = widget.moment.expiresAt;
    if (!widget.countdown || expiresAt == null) return;
    final now = DateTime.now();
    if (MomentExpiryPill.isUrgent(expiresAt: expiresAt, now: now)) return;
    var wait = expiresAt.subtract(MomentExpiryPill.urgentBelow).difference(now);
    if (wait.isNegative) return;
    if (wait > MomentExpiryPill.longestWait) {
      wait = MomentExpiryPill.longestWait;
    }
    _urgentTimer = Timer(wait, () {
      if (!mounted) return;
      setState(() {});
      _arm();
    });
  }

  @override
  void dispose() {
    _urgentTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final moment = widget.moment;
    final availability = widget.availability;
    final urgent =
        widget.countdown &&
        MomentExpiryPill.isUrgent(
          expiresAt: moment.expiresAt,
          now: DateTime.now(),
        );
    final base = AppTypography.bodySmall.copyWith(
      color: widget.ink,
      height: 1.35,
    );
    final full = !widget.availabilityOnly;
    // Each counter is ONE inline unit — the glyph and its number — so a
    // wrapping line can break before or after "♡ 24", never inside it (the
    // paragraph breaks around an inline widget whatever joins it to the
    // text beside it, a no-break space included).
    WidgetSpan counter({
      required Key key,
      required IconData icon,
      required Color color,
      required int count,
    }) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: _MetaCounter(
        key: key,
        icon: icon,
        color: color,
        count: count,
        style: base,
      ),
    );
    final spans = <InlineSpan>[];
    final spoken = <String>[];
    void separator() {
      if (spans.isNotEmpty) spans.add(const TextSpan(text: ' · '));
    }

    final leading = widget.leading;
    if (leading != null) spans.add(TextSpan(text: leading));
    if (full && moment.durationSeconds > 0) {
      separator();
      spans.add(TextSpan(text: _clock(moment.durationSeconds)));
      spoken.add(_clock(moment.durationSeconds));
    }
    if (full && moment.likeCount > 0) {
      separator();
      spans.add(
        counter(
          key: ValueKey('moment-row-meta-likes-${moment.id}'),
          icon: moment.callerLiked
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          color: moment.callerLiked ? AppColors.secondary : widget.ink,
          count: moment.likeCount,
        ),
      );
      spoken.add(
        copy.template(
          'Likes: {count}',
          'Polubienia: {count}',
          values: <String, Object>{'count': moment.likeCount},
        ),
      );
    }
    if (full && moment.commentCount > 0) {
      separator();
      spans.add(
        counter(
          key: ValueKey('moment-row-meta-comments-${moment.id}'),
          icon: Icons.mode_comment_outlined,
          color: widget.ink,
          count: moment.commentCount,
        ),
      );
      spoken.add(
        copy.template(
          'Comments: {count}',
          'Komentarze: {count}',
          values: <String, Object>{'count': moment.commentCount},
        ),
      );
    }
    if (availability != null && availability.isNotEmpty) {
      separator();
      spans.add(
        TextSpan(
          text: spans.isEmpty ? availability : _midSentence(availability),
          style: urgent
              ? TextStyle(
                  color: palette.warningForeground,
                  fontWeight: FontWeight.w600,
                )
              : null,
        ),
      );
      spoken.add(availability);
    }
    if (spans.isEmpty) return const SizedBox.shrink();
    return Text.rich(
      TextSpan(style: base, children: spans),
      semanticsLabel: spoken.join(', '),
    );
  }
}

/// One counter of the meta line: the glyph and its bare number, laid out
/// as a single inline unit (see [_RowMetaState.build]).
///
/// Laid out at 1× — the line's text scaler scales the whole unit with the
/// words beside it — so neither half is scaled twice. The number keeps the
/// line's own style and box, so it sits on the line's baseline.
class _MetaCounter extends StatelessWidget {
  const _MetaCounter({
    required this.icon,
    required this.color,
    required this.count,
    required this.style,
    super.key,
  });

  final IconData icon;
  final Color color;
  final int count;
  final TextStyle style;

  /// A size under the 12 px type so the glyph's ink matches its x-height.
  static const double glyph = 11;

  /// About the width of a space at 12 px.
  static const double gap = 3;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: glyph, color: color),
        const SizedBox(width: gap),
        Text(
          '$count',
          maxLines: 1,
          softWrap: false,
          textScaler: TextScaler.noScaling,
          style: style,
        ),
      ],
    );
  }
}

/// The row's transport control: ONE [IconButton] whose face is a 44 px
/// outline disc (borderStrong hairline, textPrimary glyph) while the row is
/// collapsed, and the R14 voice bead once the row is the current clip —
/// lit (brand glow) only while it plays, a white spinner while the grant
/// resolves. Keeping one button across both faces is what keeps keyboard
/// focus on it as the row opens.
///
/// It listens to the transport only while its row is open, so a position
/// tick never rebuilds a collapsed row.
class MomentRowTransportButton extends StatefulWidget {
  const MomentRowTransportButton({
    required this.momentId,
    required this.expanded,
    required this.playback,
    required this.enabled,
    required this.onPressed,
    this.durationSeconds = 0,
    this.buttonKey,
    super.key,
  });

  final String momentId;
  final bool expanded;
  final ValueListenable<MomentFeedPlayback> playback;
  final bool enabled;
  final VoidCallback onPressed;

  /// The Moment's real length, spoken with "Play" ("Odtwórz, 12 sekund").
  final int durationSeconds;

  /// Goes on the [IconButton], where the feed's finders look for it.
  final Key? buttonKey;

  static const double size = 44;

  /// The collapsed face, so a test can read its edge.
  @visibleForTesting
  static const Key outlineKey = ValueKey<String>('moment-row-play-outline');

  @override
  State<MomentRowTransportButton> createState() =>
      _MomentRowTransportButtonState();
}

class _MomentRowTransportButtonState extends State<MomentRowTransportButton> {
  final WidgetStatesController _states = WidgetStatesController();

  /// Owned, so the button keeps keyboard focus through every state: it is
  /// never disabled while its clip loads (a disabled button drops focus and
  /// the next Tab starts again at the top of the page).
  final FocusNode _focusNode = FocusNode(debugLabel: 'Voice Moment play');
  bool _hovered = false;
  bool _focused = false;
  bool _playing = false;
  bool _busy = false;
  ValueListenable<MomentFeedPlayback>? _listening;

  @override
  void initState() {
    super.initState();
    _states.addListener(_statesChanged);
    _listen();
  }

  @override
  void didUpdateWidget(covariant MomentRowTransportButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded != widget.expanded ||
        !identical(oldWidget.playback, widget.playback) ||
        oldWidget.momentId != widget.momentId) {
      _listen();
    }
  }

  void _listen() {
    _listening?.removeListener(_playbackChanged);
    _listening = null;
    if (widget.expanded) {
      _listening = widget.playback..addListener(_playbackChanged);
    }
    _read();
  }

  void _read() {
    final state = widget.playback.value;
    final mine = widget.expanded && state.id == widget.momentId;
    _playing = mine && state.playing;
    _busy = mine && state.busy;
  }

  void _playbackChanged() {
    final wasPlaying = _playing;
    final wasBusy = _busy;
    _read();
    if (wasPlaying != _playing || wasBusy != _busy) setState(() {});
  }

  void _statesChanged() {
    if (!mounted) return;
    final hovered = _states.value.contains(WidgetState.hovered);
    final focused = _states.value.contains(WidgetState.focused);
    if (hovered == _hovered && focused == _focused) return;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _statesChanged());
      return;
    }
    setState(() {
      _hovered = hovered;
      _focused = focused;
    });
  }

  @override
  void dispose() {
    _listening?.removeListener(_playbackChanged);
    _states
      ..removeListener(_statesChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final enabled = widget.enabled;
    final playing = _playing;
    final busy = _busy;
    final pressable = enabled && !busy;
    const size = MomentRowTransportButton.size;
    // What the button says: the loading state while the grant resolves,
    // "Pause" while it plays, otherwise "Play" with the real length.
    final loading = copy.text('Loading…', 'Ładowanie…');
    final shortLabel = busy
        ? loading
        : playing
        ? copy.text('Pause', 'Pauza')
        : copy.text('Play', 'Odtwórz');
    final spokenLabel = busy || playing || widget.durationSeconds <= 0
        ? shortLabel
        : copy.template(
            'Play, {duration}',
            'Odtwórz, {duration}',
            values: <String, Object>{
              'duration': copy.secondsCount(widget.durationSeconds),
            },
          );
    final Widget face;
    if (widget.expanded) {
      face = YoGradientDisc(
        size: size,
        emphasis: playing && enabled ? YoDiscEmphasis.lit : YoDiscEmphasis.rest,
        gloss: true,
        status: busy
            ? YoDiscStatus.busy
            : enabled
            ? YoDiscStatus.idle
            : YoDiscStatus.disabled,
        hovered: _hovered && enabled,
        focused: _focused,
        nudgePlay: !playing,
        glyph: VoiceBeadGlyph(playing: playing),
      );
    } else {
      face = ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: <Widget>[
              AnimatedContainer(
                key: MomentRowTransportButton.outlineKey,
                duration: AppMotion.resolve(context, AppMotion.quick),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _hovered && enabled
                      ? AppFinish.glass(palette, hovered: true)
                      : Colors.transparent,
                  border: Border.all(
                    color: enabled ? palette.borderStrong : palette.border,
                  ),
                ),
              ),
              Center(
                child: Transform.translate(
                  offset: const Offset(size * .03, 0),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 22,
                    color: enabled ? palette.textPrimary : palette.textTertiary,
                  ),
                ),
              ),
              if (_focused)
                Positioned(
                  left: -5,
                  top: -5,
                  right: -5,
                  bottom: -5,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.focus, width: 2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    // One node: the button, its spoken name and state, its tap and focus.
    // The tooltip is the short visible word; the node carries the long one.
    return Tooltip(
      message: shortLabel,
      excludeFromSemantics: true,
      child: MergeSemantics(
        child: Semantics(
          label: spokenLabel,
          child: YoPressFeedback(
            scale: YoPressFeedback.disc,
            enabled: pressable,
            child: _button(enabled: enabled, playing: playing, face: face),
          ),
        ),
      ),
    );
  }

  Widget _button({
    required bool enabled,
    required bool playing,
    required Widget face,
  }) {
    return IconButton(
      key: widget.buttonKey,
      focusNode: _focusNode,
      // Enabled through the loading state (a press is ignored then), so
      // focus stays on the button while the grant resolves.
      onPressed: enabled
          ? () {
              if (_busy) return;
              if (!playing) voiceBeadStartHaptic();
              widget.onPressed();
            }
          : null,
      statesController: _states,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: const WidgetStatePropertyAll(
          Size.square(MomentRowTransportButton.size),
        ),
        maximumSize: const WidgetStatePropertyAll(
          Size.square(MomentRowTransportButton.size),
        ),
        // The disc is 44 (the board); the target keeps the product's 48 px
        // promise for the primary transport control around it.
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: const WidgetStatePropertyAll(CircleBorder()),
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        // The face carries hover, press and focus itself.
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
      ),
      icon: face,
    );
  }
}

/// The open row's player line: the decorative waveform poured to the REAL
/// position, the transparent seek slider over it (what a finger, a keyboard
/// and a screen reader get) and the clock, then — only when playback failed
/// — today's copy and its retry.
class _RowTransport extends StatelessWidget {
  const _RowTransport({
    required this.moment,
    required this.playback,
    required this.enabled,
    required this.onSeek,
    required this.onRetry,
  });

  final VoiceMoment moment;
  final ValueListenable<MomentFeedPlayback> playback;
  final bool enabled;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onRetry;

  /// The narrowest the wave may get beside the clock.
  static const double _minimumWave = 140;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return ValueListenableBuilder<MomentFeedPlayback>(
      valueListenable: playback,
      builder: (context, value, _) {
        final active = value.id == moment.id;
        final state = active ? value : const MomentFeedPlayback();
        final total =
            state.duration ?? Duration(seconds: moment.durationSeconds);
        final maxMs = total.inMilliseconds;
        final position = state.elapsed.inMilliseconds.clamp(
          0,
          maxMs > 0 ? maxMs : 0,
        );
        final progress = maxMs > 0 ? position / maxMs : 0.0;
        final seekable =
            enabled &&
            active &&
            !state.busy &&
            state.error == null &&
            maxMs > 0;
        final wave = _SeekStrip(
          momentId: moment.id,
          progress: active ? progress : null,
          snapKey: state.seek,
          position: position.toDouble(),
          maxMs: maxMs,
          onSeek: seekable ? onSeek : null,
          label: copy.contextualText(
            'yoMoments.playbackPosition',
            'Playback position',
            'Pozycja odtwarzania',
          ),
          // Both numbers: "0:18" alone says nothing about what is left.
          describe: (value) => copy.template(
            '{position} of {total}',
            '{position} z {total}',
            values: <String, Object>{
              'position': _clock(value ~/ 1000),
              'total': _clock(maxMs ~/ 1000),
            },
          ),
        );
        final clock = Text(
          '${_clock(position ~/ 1000)} / ${_clock(total.inSeconds)}',
          key: ValueKey('moment-row-time-${moment.id}'),
          maxLines: 1,
          style: AppTypography.labelMedium.copyWith(
            fontSize: 13,
            color: palette.textPrimary,
            fontWeight: FontWeight.w600,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        );
        final error = state.error;
        // The clock sits beside the wave (the board); when the reader's
        // text size would leave the wave too little room it drops under
        // it, end-aligned, and the wave keeps the full width.
        final line = LayoutBuilder(
          builder: (context, constraints) {
            final painter = TextPainter(
              text: TextSpan(text: clock.data, style: clock.style),
              textScaler: MediaQuery.textScalerOf(context),
              textDirection: Directionality.of(context),
              maxLines: 1,
            )..layout();
            final clockWidth = painter.width;
            painter.dispose();
            if (constraints.maxWidth - clockWidth - 10 >= _minimumWave) {
              return Row(
                children: <Widget>[
                  Expanded(child: wave),
                  const SizedBox(width: 10),
                  // The slider speaks the position; the clock is its echo
                  // (and would re-announce the row every second).
                  ExcludeSemantics(child: clock),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                wave,
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: ExcludeSemantics(child: clock),
                ),
              ],
            );
          },
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            line,
            if (error != null) ...<Widget>[
              Text(
                error,
                style: AppTypography.bodySmall.copyWith(
                  color: palette.dangerForeground,
                ),
              ),
              TextButton.icon(
                key: ValueKey('moment-row-play-retry-${moment.id}'),
                onPressed: enabled && !state.busy ? onRetry : null,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(copy.text('Try again', 'Spróbuj ponownie')),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The open row's wave strip: the decorative waveform poured to the real
/// position under a transparent [Slider] — what a finger, a keyboard and a
/// screen reader use to seek.
///
/// Keyboard focus draws a 2 px `focus` ring around the whole strip (the
/// slider has no thumb to light). The slider moves in steps of one second
/// (one division per second of the clip), so an arrow key always moves the
/// spoken position; 5 % of a 12 s clip used to announce no change at all.
class _SeekStrip extends StatefulWidget {
  const _SeekStrip({
    required this.momentId,
    required this.progress,
    required this.snapKey,
    required this.position,
    required this.maxMs,
    required this.onSeek,
    required this.label,
    required this.describe,
  });

  final String momentId;
  final double? progress;
  final int snapKey;
  final double position;
  final int maxMs;
  final ValueChanged<Duration>? onSeek;
  final String label;
  final String Function(double value) describe;

  /// The ring, so a test can read its colour.
  @visibleForTesting
  static const Key focusRingKey = ValueKey<String>('moment-row-seek-focus');

  @override
  State<_SeekStrip> createState() => _SeekStripState();
}

class _SeekStripState extends State<_SeekStrip> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Voice Moment seek');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_focusChanged);
  }

  void _focusChanged() {
    final focused = _focusNode.hasFocus;
    if (focused != _focused && mounted) setState(() => _focused = focused);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_focusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final maxMs = widget.maxMs;
    final onSeek = widget.onSeek;
    return SizedBox(
      height: MomentCompactRow.seekHeight,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned.fill(
            child: Center(
              child: ExcludeSemantics(
                child: VoicePourWaveform(
                  key: ValueKey('moment-row-wave-${widget.momentId}'),
                  progress: widget.progress,
                  snapKey: widget.snapKey,
                  color: palette.waveUnplayed,
                  playedGradient: AppGradients.voicePlayed(colors, palette),
                  height: MomentCompactRow.waveformHeight,
                  barWidth: 3,
                  barGap: 2,
                  barRadius: 1.5,
                ),
              ),
            ),
          ),
          Positioned.fill(
            // One node carrying the name AND the value.
            child: MergeSemantics(
              child: Semantics(
                container: true,
                label: widget.label,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: MomentCompactRow.waveformHeight,
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                    disabledActiveTrackColor: Colors.transparent,
                    disabledInactiveTrackColor: Colors.transparent,
                    secondaryActiveTrackColor: Colors.transparent,
                    activeTickMarkColor: Colors.transparent,
                    inactiveTickMarkColor: Colors.transparent,
                    disabledActiveTickMarkColor: Colors.transparent,
                    disabledInactiveTickMarkColor: Colors.transparent,
                    tickMarkShape: SliderTickMarkShape.noTickMark,
                    thumbColor: Colors.transparent,
                    disabledThumbColor: Colors.transparent,
                    overlayColor: Colors.transparent,
                    thumbShape: SliderComponentShape.noThumb,
                    overlayShape: SliderComponentShape.noOverlay,
                    trackShape: const RectangularSliderTrackShape(),
                    showValueIndicator: ShowValueIndicator.never,
                  ),
                  child: Slider(
                    key: ValueKey('moment-row-progress-${widget.momentId}'),
                    focusNode: _focusNode,
                    value: widget.position,
                    max: maxMs > 0 ? maxMs.toDouble() : 1,
                    // One step per second of the clip.
                    divisions: maxMs > 0
                        ? math.max(1, (maxMs / 1000).round())
                        : null,
                    padding: EdgeInsets.zero,
                    onChanged: onSeek == null
                        ? null
                        : (value) =>
                              onSeek(Duration(milliseconds: value.round())),
                    semanticFormatterCallback: widget.describe,
                  ),
                ),
              ),
            ),
          ),
          // The focus ring: always in the tree (transparent until focused),
          // a foreground, so focusing the seek never moves a pixel.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: _SeekStrip.focusRingKey,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                  border: Border.all(
                    color: _focused ? palette.focus : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The open row's action line: like (count) · comments (count) ·
/// "Odpowiedz głosem" · share · ⋯ — real counters only, drawn as bare
/// numbers and spoken as phrases. When the reply does not fit the line at
/// the reader's text size it takes a line of its own, so no word breaks.
class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.moment,
    required this.enabled,
    required this.canLike,
    required this.onLike,
    required this.onComments,
    required this.onReplyVoice,
    required this.onShare,
    required this.onMore,
  });

  final VoiceMoment moment;
  final bool enabled;
  final bool canLike;
  final VoidCallback onLike;
  final VoidCallback onComments;
  final VoidCallback onReplyVoice;
  final VoidCallback onShare;

  /// Opens the row's ⋯ menu anchored on the button (the row owns the menu).
  final ValueChanged<BuildContext>? onMore;

  static const double _padding = 10;
  static const double _glyph = 20;
  static const double _iconGap = 8;

  /// Every action keeps the product's 48 px target.
  static const double _target = 48;

  static const TextStyle _countStyle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontFamilyFallback: AppTypography.fontFamilyFallback,
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );

  double _labelWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final id = moment.id;
    ButtonStyle quiet(Color ink, {FontWeight weight = FontWeight.w600}) =>
        TextButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(_target, _target),
          padding: const EdgeInsets.symmetric(horizontal: _padding),
          textStyle: _countStyle.copyWith(fontWeight: weight),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
    // The like is an ACTION with its count, and a toggle: "Lubię to,
    // Polubienia: 8", on once the viewer liked it.
    final likeAction = copy.text('Like', 'Lubię to');
    final likeLabel = moment.likeCount > 0
        ? '$likeAction, ${copy.template('Likes: {count}', 'Polubienia: {count}', values: <String, Object>{'count': moment.likeCount})}'
        : likeAction;
    final commentsLabel = moment.commentCount > 0
        ? copy.template(
            'Comments: {count}',
            'Komentarze: {count}',
            values: <String, Object>{'count': moment.commentCount},
          )
        : copy.text('Comments', 'Komentarze');
    // MergeSemantics so the liked STATE lands on the node with the role, the
    // name and the tap action.
    final like = MergeSemantics(
      child: Semantics(
        toggled: moment.callerLiked,
        child: TextButton.icon(
          key: ValueKey('moment-row-like-$id'),
          onPressed: enabled && canLike ? onLike : null,
          style: quiet(palette.textSecondary),
          icon: Icon(
            moment.callerLiked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            size: _glyph,
            color: moment.callerLiked ? AppColors.secondary : null,
          ),
          label: Text(
            '${moment.likeCount}',
            maxLines: 1,
            semanticsLabel: likeLabel,
          ),
        ),
      ),
    );
    final comments = TextButton.icon(
      key: ValueKey('moment-row-comments-$id'),
      onPressed: enabled ? onComments : null,
      style: quiet(palette.textSecondary),
      icon: const Icon(Icons.mode_comment_outlined, size: _glyph),
      label: Text(
        '${moment.commentCount}',
        maxLines: 1,
        semanticsLabel: commentsLabel,
      ),
    );
    final replyText = copy.text('Reply with voice', 'Odpowiedz głosem');
    // Merged, so the tooltip (who the reply goes to) belongs to the button
    // rather than to the row around it.
    final reply = MergeSemantics(
      child: Tooltip(
        message: copy.template(
          'Reply with voice to {name}',
          'Odpowiedz głosem: {name}',
          values: <String, Object>{'name': moment.authorName},
        ),
        child: TextButton.icon(
          key: ValueKey('moment-row-reply-voice-$id'),
          onPressed: enabled ? onReplyVoice : null,
          style: quiet(palette.interactiveForeground, weight: FontWeight.w700),
          icon: const Icon(Icons.mic_none_rounded, size: _glyph),
          label: Text(
            replyText,
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
    final share = IconButton(
      key: ValueKey('moment-row-share-$id'),
      onPressed: enabled ? onShare : null,
      tooltip: copy.text('Share', 'Udostępnij'),
      style: IconButton.styleFrom(
        foregroundColor: palette.textSecondary,
        fixedSize: const Size.square(_target),
        minimumSize: const Size.square(_target),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.ios_share_rounded, size: 20),
    );
    final more = Builder(
      builder: (button) => IconButton(
        key: ValueKey('moment-row-menu-$id'),
        onPressed: onMore == null ? null : () => onMore!(button),
        tooltip: copy.text('More options', 'Więcej opcji'),
        style: IconButton.styleFrom(
          foregroundColor: palette.textSecondary,
          fixedSize: const Size.square(_target),
          minimumSize: const Size.square(_target),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.more_horiz_rounded, size: 20),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        double buttonWidth(String label, TextStyle style) =>
            2 * _padding +
            _glyph +
            _iconGap +
            _labelWidth(context, label, style) +
            1;
        final needed =
            buttonWidth('${moment.likeCount}', _countStyle) +
            buttonWidth('${moment.commentCount}', _countStyle) +
            buttonWidth(
              replyText,
              _countStyle.copyWith(fontWeight: FontWeight.w700),
            ) +
            2 * _target;
        if (needed <= constraints.maxWidth) {
          return SizedBox(
            height: _target,
            child: Row(
              children: <Widget>[
                like,
                comments,
                reply,
                const Spacer(),
                share,
                more,
              ],
            ),
          );
        }
        // Narrow or large text: the counters and the two icons on the first
        // line, the reply on its own, whole.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Flexible(child: like),
                Flexible(child: comments),
                const Spacer(),
                share,
                more,
              ],
            ),
            reply,
          ],
        );
      },
    );
  }
}
