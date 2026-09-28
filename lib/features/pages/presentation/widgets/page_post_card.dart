import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/page_voice_player.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_face.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_focus_ink.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_type_chip.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';
import 'package:yovoice/shared/widgets/voice/voice_player_row.dart';
import 'package:yovoice/shared/widgets/waveform/yo_waveform.dart';

/// Wall A's post card (approved `tresci-ui/wall/A_karty_*`, with the R15
/// narrow and 200 % rules): header (face 40, name + VIP rosette, type chip ·
/// age, ⋯), text collapsed at 6 lines, photos or the voice transport, the
/// count line with its own likers button, and the 48 px action row Lubię to
/// / Komentuj / Udostępnij.
///
/// A null callback leaves its control disabled (never hidden and never
/// faked): the post detail, likers and voice playback belong to later Pages
/// packages (see `PagesFlows`).
class PagePostCard extends StatelessWidget {
  const PagePostCard({
    required this.post,
    required this.now,
    required this.service,
    required this.onOpenPage,
    required this.onToggleLike,
    required this.onShare,
    required this.onMore,
    this.onComment,
    this.onOpenLikers,
    this.onPlayVoice,
    this.onOpenPhotos,
    this.onOpenPhoto,
    this.voicePlayer,
    this.likeBusy = false,
    this.showTypeChip = true,
    this.photoMaxHeight,
    this.showPinnedLabel = false,
    this.commentsClosedLabel,
    this.onDeleteHeld,
    this.onHeldDetails,
    this.lead = false,
    super.key,
  });

  final PagePostView post;
  final DateTime now;

  /// Grants for the photos (`getPagePostMediaAccessV1`).
  final PagesService service;
  final VoidCallback onOpenPage;
  final VoidCallback onToggleLike;
  final VoidCallback onShare;
  final VoidCallback onMore;
  final VoidCallback? onComment;
  final VoidCallback? onOpenLikers;
  final VoidCallback? onPlayVoice;
  final VoidCallback? onOpenPhotos;

  /// Opens one photo (the post detail's full-screen viewer); wins over
  /// [onOpenPhotos].
  final ValueChanged<int>? onOpenPhoto;

  /// The player the voice transport follows; the app-wide one by default.
  final PageVoicePlayer? voicePlayer;
  final bool likeBusy;

  /// False on the Page's own wall (the profile B render shows only the age).
  final bool showTypeChip;

  /// Desktop caps a single photo's height (the wall A desktop render: 420).
  final double? photoMaxHeight;

  /// The Page's own wall marks its pinned post "Przypięty" (profile B).
  final bool showPinnedLabel;

  /// Non-null while comments are closed for everyone (a read-only Page,
  /// D14): Komentuj is disabled and says why.
  final String? commentsClosedLabel;

  /// The owner's held post (R8): its only action is "Usuń post".
  final VoidCallback? onDeleteHeld;
  final VoidCallback? onHeldDetails;

  /// The screen's lead card carries the one violet corner tint (ADR-227's
  /// light budget: at most one corner-tinted block per screen).
  final bool lead;

  static const int collapsedLines = 6;
  static const double largeTextScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final shortText = post.kind == PagePostKind.text && post.text.length <= 140;
    final images = post.images;
    final voice = post.voice;
    final held = post.state == PagePostState.held;
    final body = <Widget>[
      _CardHeader(
        post: post,
        age: copy.age(post.createdAt, now),
        showTypeChip: showTypeChip,
        onOpenPage: onOpenPage,
        onMore: onMore,
      ),
      if (post.text.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: CollapsingPostText(
            text: post.text,
            style:
                (shortText ? AppTypography.titleLarge : AppTypography.bodyLarge)
                    .copyWith(color: palette.textPrimary, height: 1.45),
          ),
        ),
      if (images.isNotEmpty) ...[
        const SizedBox(height: 12),
        PagePhotoGrid(
          post: post,
          images: images,
          service: service,
          maxSingleHeight: photoMaxHeight,
          onOpen: onOpenPhotos,
          onOpenPhoto: onOpenPhoto,
        ),
      ],
      if (voice != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: PageVoiceTransport(
            voice: voice,
            postId: post.postId,
            player: onPlayVoice == null
                ? null
                : voicePlayer ?? PageVoicePlayer.instance,
            onPlay: onPlayVoice,
          ),
        ),
      // A voice post with no words has no text equivalent: say so, so a
      // reader who cannot listen knows nothing is missing from the text.
      if (voice != null && post.text.trim().isEmpty)
        Padding(
          key: const ValueKey('page-post-no-transcript'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Icon(
                Icons.subtitles_off_outlined,
                size: 16,
                color: palette.textTertiary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  copy.noTranscript,
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      if (held)
        const SizedBox(height: 12)
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
          child: _CountLine(post: post, onOpenLikers: onOpenLikers),
        ),
    ];
    return YoCard(
      padding: EdgeInsets.zero,
      semanticButton: false,
      tint: lead && !held ? Theme.of(context).colorScheme.primary : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (held)
            _HeldBanner(onDetails: onHeldDetails)
          else if (showPinnedLabel && post.pinned)
            const _PinnedLabel(),
          if (held)
            Opacity(
              opacity: .55,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: body,
              ),
            )
          else
            ...body,
          Container(height: 1, color: palette.hairline),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: held
                ? _HeldActions(onDelete: onDeleteHeld)
                : _ActionRow(
                    post: post,
                    likeBusy: likeBusy,
                    onToggleLike: onToggleLike,
                    onComment: onComment,
                    onShare: onShare,
                    closedLabel: commentsClosedLabel,
                  ),
          ),
        ],
      ),
    );
  }
}

/// "Przypięty" over the Page's pinned post (profile B, R8).
class _PinnedLabel extends StatelessWidget {
  const _PinnedLabel();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    return Padding(
      key: const ValueKey('page-post-pinned'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Icon(Icons.push_pin_outlined, size: 14, color: palette.textTertiary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              copy.copy.contextualText('pages.pinned', 'Pinned', 'Przypięty'),
              style: AppTypography.overline.copyWith(
                color: palette.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The owner's held-post marker (R8): the warning tone, "Ukryty przez
/// moderację", and "Szczegóły".
class _HeldBanner extends StatelessWidget {
  const _HeldBanner({required this.onDetails});

  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final ink = palette.warningForeground;
    return Container(
      key: const ValueKey('page-post-held'),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: palette.warningSurface,
        border: Border(
          bottom: BorderSide(
            color: Color.alphaBlend(ink.withValues(alpha: .38), palette.border),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_off_outlined, size: 18, color: ink),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy.text('Hidden by moderation', 'Ukryty przez moderację'),
                  style: AppTypography.bodyMedium.copyWith(
                    color: palette.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  copy.text(
                    'Only you can see it until it has been reviewed',
                    'Widzisz go tylko Ty, do czasu weryfikacji',
                  ),
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          if (onDetails != null)
            TextButton(
              onPressed: onDetails,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: palette.interactiveForeground,
                textStyle: AppTypography.labelLarge.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(copy.text('Details', 'Szczegóły')),
            ),
        ],
      ),
    );
  }
}

class _HeldActions extends StatelessWidget {
  const _HeldActions({required this.onDelete});

  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return SizedBox(
      height: 48,
      child: Center(
        child: TextButton.icon(
          key: const ValueKey('page-post-delete-held'),
          onPressed: onDelete,
          style: TextButton.styleFrom(
            minimumSize: const Size(44, 44),
            foregroundColor: palette.textSecondary,
            textStyle: AppTypography.labelMedium.copyWith(fontSize: 13),
            shape: const StadiumBorder(),
          ),
          icon: const Icon(Icons.delete_outline_rounded, size: 20),
          label: Text(copy.text('Delete post', 'Usuń post')),
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.post,
    required this.age,
    required this.showTypeChip,
    required this.onOpenPage,
    required this.onMore,
  });

  final PagePostView post;
  final String age;
  final bool showTypeChip;
  final VoidCallback onOpenPage;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    // >= 1.3x: chip + age leave the face column and take the card's full
    // width, so the chip never breaks mid-word (R15).
    final big =
        MediaQuery.textScalerOf(context).scale(1) >=
        PagePostCard.largeTextScale;
    final ageText = Text(
      showTypeChip ? '· $age' : age,
      style: AppTypography.bodySmall.copyWith(
        color: palette.textSecondary,
        height: 1.2,
      ),
    );
    final meta = ExcludeSemantics(
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (showTypeChip) PageTypeChip(kind: post.pageKind),
          ageText,
        ],
      ),
    );
    // One node: the button role, the merged "{Page}, {kind}, {age}" (+ VIP)
    // label and the InkWell's tap and focus (spec §4.5 semantics table).
    final identity = MergeSemantics(
      child: Semantics(
        button: true,
        child: PagesFocusInk(
          key: const ValueKey('page-post-header'),
          onTap: onOpenPage,
          borderRadius: AppRadius.md,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageFace(
                  pageId: post.pageId,
                  name: post.pageName,
                  kind: post.pageKind,
                  size: 40,
                ),
                const SizedBox(width: AppRhythm.item),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NameWithVipMark(
                        uid: post.pageId,
                        name: post.pageName,
                        maxLines: big ? 3 : 2,
                        semanticsLabel: copy.cardHeader(
                          post.pageName,
                          post.pageKind,
                          age,
                        ),
                        style: AppTypography.rowTitle.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!big) ...[const SizedBox(height: 3), meta],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: identity),
              YoIconButton(
                icon: Icons.more_horiz_rounded,
                onPressed: onMore,
                tooltip: copy.moreOptions,
                size: 44,
                iconSize: 22,
                backgroundColor: Colors.transparent,
                borderColor: Colors.transparent,
                foregroundColor: palette.textSecondary,
              ),
            ],
          ),
          if (big)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
              child: meta,
            ),
        ],
      ),
    );
  }
}

/// Post text collapsed at [PagePostCard.collapsedLines] lines with a
/// "Pokaż więcej" button (≥ 44 px) that expands it in place.
class CollapsingPostText extends StatefulWidget {
  const CollapsingPostText({
    required this.text,
    required this.style,
    super.key,
  });

  final String text;
  final TextStyle style;

  @override
  State<CollapsingPostText> createState() => _CollapsingPostTextState();
}

class _CollapsingPostTextState extends State<CollapsingPostText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    return LayoutBuilder(
      builder: (context, constraints) {
        final style = DefaultTextStyle.of(context).style.merge(widget.style);
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
          maxLines: PagePostCard.collapsedLines,
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();
        final collapsed = overflows && !_expanded;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              maxLines: collapsed ? PagePostCard.collapsedLines : null,
              overflow: collapsed ? TextOverflow.ellipsis : null,
              style: widget.style,
            ),
            if (collapsed)
              Transform.translate(
                offset: Offset(
                  Directionality.of(context) == TextDirection.rtl ? 8 : -8,
                  0,
                ),
                child: TextButton(
                  onPressed: () => setState(() => _expanded = true),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: palette.textPrimary,
                    textStyle: AppTypography.labelMedium.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(copy.showMore),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// "48 polubień · 12 komentarzy". The likes figure is its own TextButton
/// (≥ 44 px, semantics "48 polubień, pokaż kto polubił") while a likers
/// list can open; otherwise it is plain text.
class _CountLine extends StatelessWidget {
  const _CountLine({required this.post, required this.onOpenLikers});

  final PagePostView post;
  final VoidCallback? onOpenLikers;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final likes = copy.likes(post.likeCount);
    final textStyle = AppTypography.bodySmall.copyWith(
      color: palette.textSecondary,
      fontWeight: FontWeight.w500,
    );
    final canOpen = onOpenLikers != null && post.likeCount > 0;
    final commentsText = copy.comments(post.commentCount);
    if (!canOpen) {
      // One plain line, as on the wall A render. The separator is glued to
      // both neighbours so it never starts a line; it is not spoken.
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              '$likes\u00A0·\u00A0$commentsText',
              semanticsLabel: '$likes, $commentsText',
              style: textStyle,
            ),
          ),
        ),
      );
    }
    // The likers figure is its own 44 px button in the same muted w500 as
    // the rest of the line. The separator rides the button's side, so when
    // the line wraps (320 px, 200 %) it ends a line instead of starting one.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Semantics(
                label: copy.likersEntry(post.likeCount),
                button: true,
                onTap: onOpenLikers,
                excludeSemantics: true,
                child: TextButton(
                  key: const ValueKey('page-post-likers'),
                  onPressed: onOpenLikers,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
                    tapTargetSize: MaterialTapTargetSize.padded,
                    foregroundColor: palette.textSecondary,
                    textStyle: textStyle,
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
                  ),
                  child: Text(likes),
                ),
              ),
            ),
            ExcludeSemantics(child: Text('·\u00A0', style: textStyle)),
          ],
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(commentsText, style: textStyle),
            ),
          ),
        ),
      ],
    );
  }
}

/// Lubię to / Komentuj / Udostępnij. When any label does not fit its third,
/// all three drop to icon + tooltip; the targets stay 48 tall (R15).
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.post,
    required this.likeBusy,
    required this.onToggleLike,
    required this.onComment,
    required this.onShare,
    this.closedLabel,
  });

  final PagePostView post;
  final bool likeBusy;
  final VoidCallback onToggleLike;
  final VoidCallback? onComment;
  final VoidCallback onShare;

  /// Why comments are closed (a read-only Page), or null.
  final String? closedLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final scaler = MediaQuery.textScalerOf(context);
    final style = AppTypography.labelMedium.copyWith(fontSize: 13);
    final labels = <String>[copy.like, copy.comment, copy.share];
    return LayoutBuilder(
      builder: (context, constraints) {
        final each = constraints.maxWidth / 3;
        final base = DefaultTextStyle.of(context).style.merge(style);
        bool fits(String label) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: base),
            textScaler: scaler,
            textDirection: Directionality.of(context),
            maxLines: 1,
          )..layout();
          final need = 20 + 6 + painter.width + 16;
          painter.dispose();
          return need <= each;
        }

        final labeled = labels.every(fits);
        Widget action({
          required Key key,
          required IconData icon,
          required String label,
          required String semanticLabel,
          required VoidCallback? onPressed,
          bool active = false,
          bool? toggled,
          String? disabledReason,
          bool busy = false,
        }) {
          final enabled = onPressed != null;
          final color = !enabled
              ? palette.textTertiary
              : active
              ? AppColors.secondary
              : palette.textSecondary;
          final body = SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: color),
                if (labeled) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: style.copyWith(color: color),
                    ),
                  ),
                ],
              ],
            ),
          );
          final tooltip = enabled
              ? label
              : '$label · ${disabledReason ?? copy.comingSoon}';
          // A busy control stays enabled and focusable (taps are ignored
          // until the server answers), so keyboard focus never jumps away.
          final onTap = busy ? _ignoreTap : onPressed;
          return Expanded(
            child: Tooltip(
              message: tooltip,
              excludeFromSemantics: true,
              child: Semantics(
                button: true,
                enabled: enabled,
                toggled: toggled,
                label: enabled ? semanticLabel : tooltip,
                excludeSemantics: true,
                onTap: onTap,
                child: PagesFocusInk(
                  key: key,
                  onTap: onTap,
                  borderRadius: AppRadius.md,
                  child: body,
                ),
              ),
            ),
          );
        }

        return Row(
          children: [
            action(
              key: const ValueKey('page-post-like'),
              icon: post.callerLiked
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              label: labels[0],
              semanticLabel: copy.likeToggle(post.likeCount),
              onPressed: onToggleLike,
              busy: likeBusy,
              active: post.callerLiked,
              toggled: post.callerLiked,
            ),
            action(
              key: const ValueKey('page-post-comment'),
              icon: Icons.chat_bubble_outline_rounded,
              label: labels[1],
              semanticLabel: labels[1],
              onPressed: post.commentsEnabled && closedLabel == null
                  ? onComment
                  : null,
              disabledReason: closedLabel,
            ),
            action(
              key: const ValueKey('page-post-share'),
              icon: Icons.ios_share_rounded,
              label: labels[2],
              semanticLabel: labels[2],
              onPressed: onShare,
            ),
          ],
        );
      },
    );
  }
}

/// A post's photos, edge to edge in the card: 1, 2, 3, or 4-10 with "+N"
/// on the fourth tile (spec §4.2). Bytes arrive through 90 s grants; the
/// declared width and height are used for layout only.
class PagePhotoGrid extends StatefulWidget {
  const PagePhotoGrid({
    required this.post,
    required this.images,
    required this.service,
    this.maxSingleHeight,
    this.onOpen,
    this.onOpenPhoto,
    super.key,
  });

  final PagePostView post;
  final List<PageMediaView> images;
  final PagesService service;
  final double? maxSingleHeight;
  final VoidCallback? onOpen;
  final ValueChanged<int>? onOpenPhoto;

  static const double gap = 2;

  @override
  State<PagePhotoGrid> createState() => _PagePhotoGridState();
}

class _PagePhotoGridState extends State<PagePhotoGrid> {
  Map<String, PageMediaGrant> _grants = const <String, PageMediaGrant>{};
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(PagePhotoGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.postId != widget.post.postId) {
      _grants = const <String, PageMediaGrant>{};
      _failed = false;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    try {
      final grants = await widget.service.mediaAccess(widget.post.postId, [
        for (final image in widget.images) image.mediaId,
      ]);
      if (!mounted) return;
      setState(() {
        _grants = grants;
        _failed = false;
      });
    } on PagesException {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Widget _tile(int index, {int? moreCount}) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final image = widget.images[index];
    final grant = _grants[image.mediaId];
    Widget content;
    if (grant != null) {
      content = Image.network(
        grant.url.toString(),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : ColoredBox(color: palette.surfaceMuted),
        errorBuilder: (context, _, _) => _PhotoPlaceholder(failed: true),
      );
    } else {
      content = _PhotoPlaceholder(failed: _failed);
    }
    final label = copy.photoLabel(
      index + 1,
      widget.images.length,
      widget.post.pageName,
    );
    final tileLabel = moreCount == null
        ? label
        : '$label. ${copy.morePhotos(moreCount)}';
    final Widget visual = ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
          if (moreCount != null)
            ColoredBox(
              color: Colors.black.withValues(alpha: .48),
              child: Center(
                child: Text(
                  '+$moreCount',
                  style: AppTypography.titleLarge.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    final onOpenPhoto = widget.onOpenPhoto;
    final onOpen = widget.onOpen;
    final VoidCallback? onTap = onOpenPhoto != null
        ? () => onOpenPhoto(index)
        : onOpen;
    if (onTap == null) {
      return Semantics(image: true, label: tileLabel, child: visual);
    }
    // A real, focusable button with the 2 px ring: Tab reaches every photo
    // and Enter opens it, as a tap does.
    return Semantics(
      button: true,
      image: true,
      label: tileLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: PagesFocusInk(
        key: onOpenPhoto != null ? ValueKey('page-photo-$index') : null,
        onTap: onTap,
        ringInset: 2,
        child: visual,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    const gap = PagePhotoGrid.gap;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        switch (images.length) {
          case 1:
            final aspect = (images.single.aspectRatio ?? 4 / 3).clamp(
              4 / 5,
              16 / 9,
            );
            var height = width / aspect;
            final cap = widget.maxSingleHeight;
            if (cap != null) height = math.min(height, cap);
            return SizedBox(width: width, height: height, child: _tile(0));
          case 2:
            final side = (width - gap) / 2;
            return SizedBox(
              height: side,
              child: Row(
                children: [
                  Expanded(child: _tile(0)),
                  const SizedBox(width: gap),
                  Expanded(child: _tile(1)),
                ],
              ),
            );
          case 3:
            return SizedBox(
              height: width * 2 / 3,
              child: Row(
                children: [
                  Expanded(flex: 2, child: _tile(0)),
                  const SizedBox(width: gap),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: _tile(1)),
                        const SizedBox(height: gap),
                        Expanded(child: _tile(2)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          default:
            final more = images.length - 4;
            return SizedBox(
              height: width,
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _tile(0)),
                        const SizedBox(width: gap),
                        Expanded(child: _tile(1)),
                      ],
                    ),
                  ),
                  const SizedBox(height: gap),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _tile(2)),
                        const SizedBox(width: gap),
                        Expanded(
                          child: _tile(3, moreCount: more > 0 ? more : null),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
        }
      },
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({required this.failed});

  final bool failed;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return ColoredBox(
      color: palette.surfaceMuted,
      child: failed
          ? Center(
              child: Icon(
                Icons.broken_image_outlined,
                size: 28,
                color: palette.textTertiary,
              ),
            )
          : null,
    );
  }
}

/// The voice transport as on Głos (R13/R14): the gloss bead, the fixed
/// silhouette and the clip's real length under it (≤ 1:00, D8).
///
/// While [player] is given, the bead and the silhouette follow it: loading,
/// playing (the played run and the position clock), paused and failed.
/// Playback downloads the whole clip first (§4.5). Without [onPlay] the bead
/// is the disabled disc and says why.
class PageVoiceTransport extends StatelessWidget {
  const PageVoiceTransport({
    required this.voice,
    this.postId,
    this.player,
    this.onPlay,
    super.key,
  });

  final PageMediaView voice;
  final String? postId;
  final PageVoicePlayer? player;
  final VoidCallback? onPlay;

  static String clock(int milliseconds) {
    final seconds = (milliseconds / 1000).round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = this.player;
    final id = postId;
    if (player == null || id == null || onPlay == null) {
      return _body(context, PageVoicePhase.idle, Duration.zero);
    }
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) =>
          _body(context, player.phaseOf(id), player.positionOf(id)),
    );
  }

  Widget _body(BuildContext context, PageVoicePhase phase, Duration position) {
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    final copy = PagesCopy(AppLocalizations.of(context));
    final totalMs = voice.durationMs ?? 0;
    final duration = clock(totalMs);
    final enabled = onPlay != null;
    final playing = phase == PageVoicePhase.playing;
    final active = playing || phase == PageVoicePhase.paused;
    final progress = active && totalMs > 0
        ? (position.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : null;
    final base = copy.voiceLabel(duration);
    final String label;
    if (!enabled) {
      label = '$base. ${copy.voicePlaybackSoon}';
    } else if (phase == PageVoicePhase.failed) {
      label = '$base. ${copy.voicePlaybackFailed}';
    } else {
      label = '$base, ${playing ? copy.pauseAction : copy.playAction}';
    }
    // The position is the value; under Reduce Motion it is not re-announced
    // on every tick.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final value = active && !reduceMotion
        ? clock(position.inMilliseconds)
        : null;
    final tooltip = !enabled
        ? copy.voicePlaybackSoon
        : phase == PageVoicePhase.failed
        ? copy.voicePlaybackFailed
        : _capitalized(playing ? copy.pauseAction : copy.playAction);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      value: value,
      onTap: onPlay,
      excludeSemantics: true,
      child: Row(
        children: [
          Tooltip(
            message: tooltip,
            excludeFromSemantics: true,
            child: InkResponse(
              key: const ValueKey('page-voice-play'),
              onTap: onPlay,
              radius: 28,
              child: YoGradientDisc(
                size: 48,
                gloss: true,
                status: !enabled
                    ? YoDiscStatus.disabled
                    : phase == PageVoicePhase.failed
                    ? YoDiscStatus.failed
                    : phase == PageVoicePhase.loading
                    ? YoDiscStatus.busy
                    : YoDiscStatus.idle,
                glyph: VoiceBeadGlyph(playing: playing),
              ),
            ),
          ),
          const SizedBox(width: AppRhythm.item),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                YoWaveform(
                  color: palette.waveUnplayed,
                  progress: progress,
                  playedGradient: AppGradients.voicePlayed(scheme, palette),
                  continuousProgress: true,
                  gradientSpan: YoWaveformGradientSpan.full,
                  height: 36,
                  barWidth: 3,
                  barGap: 2,
                  barRadius: 1.5,
                ),
                const SizedBox(height: 4),
                Text(
                  active
                      ? '${clock(position.inMilliseconds)} / $duration'
                      : duration,
                  style: AppTypography.bodySmall.copyWith(
                    color: phase == PageVoicePhase.failed
                        ? palette.dangerForeground
                        : palette.textSecondary,
                    height: 1.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _ignoreTap() {}

String _capitalized(String value) => value.isEmpty
    ? value
    : '${value.characters.first.toUpperCase()}${value.characters.skip(1)}';
