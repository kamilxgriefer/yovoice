import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_face.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_follow_button.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_type_chip.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_focus_ink.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';
import 'package:yovoice/shared/widgets/layout/home_section_header.dart';

/// How a row or tile asks for a follow change and reads its state.
class PageFollowBinding {
  const PageFollowBinding({
    required this.follows,
    required this.busy,
    required this.onToggle,
  });

  final bool Function(PageCard card) follows;
  final bool Function(PageCard card) busy;
  final void Function(PageCard card) onToggle;
}

/// Wall A's "Obserwuj więcej stron" rail (R15 rules): horizontal 150 px
/// tiles whose height comes from the tallest tile measured under the
/// reader's text scale; at ≥ 1.3× a vertical list of full-width rows.
class PageSuggestionRail extends StatelessWidget {
  const PageSuggestionRail({
    required this.title,
    required this.pages,
    required this.follow,
    required this.onOpenPage,
    this.onSeeAll,
    this.gutter = 16,
    this.verticalRows = 3,
    super.key,
  });

  final String title;
  final List<PageCard> pages;
  final PageFollowBinding follow;
  final void Function(PageCard card) onOpenPage;
  final VoidCallback? onSeeAll;
  final double gutter;

  /// How many rows the ≥ 1.3× vertical list shows ("Zobacz wszystkie"
  /// opens Find Pages for the rest).
  final int verticalRows;

  static const double tileWidth = 150;
  static const double largeTextScale = 1.3;

  static TextStyle nameStyle(AppPalette palette) =>
      AppTypography.titleSmall.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 13.5,
        height: 1.3,
      );

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final scaler = MediaQuery.textScalerOf(context);
    final vertical = scaler.scale(1) >= largeTextScale;
    final style = nameStyle(palette);
    final header = Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: HomeSectionHeader(
        title: title,
        onSeeAll: onSeeAll,
        seeAllLabel: onSeeAll == null ? null : copy.seeAll,
      ),
    );
    if (vertical) {
      final items = pages.take(verticalRows).toList(growable: false);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 10),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: YoCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              semanticButton: false,
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 72),
                        child: Container(height: 1, color: palette.hairline),
                      ),
                    PageListRow(
                      card: items[i],
                      follow: follow,
                      onOpen: () => onOpenPage(items[i]),
                      showMeta: false,
                      divider: false,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }
    // Tallest tile: name (2 lines at most, with the mark's allowance), the
    // chip and the follow pill, all under the current text scale.
    final base = DefaultTextStyle.of(context).style.merge(style);
    var nameHeight = 0.0;
    for (final page in pages) {
      final painter = TextPainter(
        text: TextSpan(text: page.displayName, style: base),
        textScaler: scaler,
        textDirection: Directionality.of(context),
        textAlign: TextAlign.center,
        maxLines: 2,
      )..layout(maxWidth: tileWidth - 24 - 16);
      nameHeight = math.max(nameHeight, painter.height);
      painter.dispose();
    }
    final chipHeight = math.max(18.0, scaler.scale(10.5) * 1.25 + 4);
    final followHeight = math.max(32.0, scaler.scale(12.5) * 1.2 + 12);
    // The follow pill's 48 px padded target adds 8 px above and below the
    // 32 px pill.
    final followTarget = math.max(48.0, followHeight);
    final tileHeight =
        (16 + 56 + 10 + nameHeight + 6 + chipHeight + 8 + followTarget + 8)
            .ceilToDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 10),
        SizedBox(
          height: tileHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: gutter),
            itemCount: pages.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final page = pages[index];
              // Two controls, each one node: the Page (button: name, VIP,
              // type) over the whole upper tile, and Obserwuj. Nothing on
              // the tile claims a selected state it does not have.
              return SizedBox(
                width: tileWidth,
                child: YoCard(
                  key: ValueKey('page-rail-tile-${page.pageId}'),
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                  semanticButton: false,
                  child: Column(
                    children: [
                      Expanded(
                        child: MergeSemantics(
                          child: Semantics(
                            button: true,
                            child: PagesFocusInk(
                              key: ValueKey('page-rail-open-${page.pageId}'),
                              onTap: () => onOpenPage(page),
                              borderRadius: AppRadius.md,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                                child: Column(
                                  children: [
                                    PageFace(
                                      pageId: page.pageId,
                                      name: page.displayName,
                                      kind: page.kind,
                                      size: 56,
                                    ),
                                    const SizedBox(height: 10),
                                    NameWithVipMark(
                                      uid: page.pageId,
                                      name: page.displayName,
                                      maxLines: 2,
                                      textAlign: TextAlign.center,
                                      style: style,
                                    ),
                                    const SizedBox(height: 6),
                                    PageTypeChip(
                                      kind: page.kind,
                                      compact: true,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: PageFollowButton(
                          following: follow.follows(page),
                          busy: follow.busy(page),
                          pageName: page.displayName,
                          onPressed: () => follow.onToggle(page),
                          expand: true,
                          height: followHeight,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One Page in a list (Find Pages, the E1 suggestions, the ≥ 1.3× rail):
/// face 48, name + rosette, type chip, "48 obserwujących · post 2 godz.
/// temu", and Obserwuj. Obserwuj moves under the name when the text column
/// would drop below about seven scaled characters (R15).
class PageListRow extends StatelessWidget {
  const PageListRow({
    required this.card,
    required this.follow,
    required this.onOpen,
    this.lastPostLabel,
    this.showMeta = true,
    this.divider = true,
    this.faceImage,
    this.mediaService,
    this.mediaRevision,
    super.key,
  });

  final PageCard card;
  final PageFollowBinding follow;
  final VoidCallback onOpen;

  /// A photo that is not saved yet (the live preview of "Edytuj stronę"),
  /// shown instead of the stored one.
  final ImageProvider<Object>? faceImage;

  /// Test seam for the face's media grant; the app uses the shared service.
  final ProfileMediaService? mediaService;
  final Object? mediaRevision;

  /// "post 2 godz. temu" (the suggestions list only, as rendered).
  final String? lastPostLabel;
  final bool showMeta;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final nameStyle = AppTypography.rowTitle.copyWith(
      color: palette.textPrimary,
      fontWeight: FontWeight.w700,
    );
    final meta = showMeta
        ? [copy.followers(card.followerCount), ?lastPostLabel].join(' · ')
        : null;
    final following = follow.follows(card);
    final button = PageFollowButton(
      following: following,
      busy: follow.busy(card),
      pageName: card.displayName,
      onPressed: () => follow.onToggle(card),
    );
    return Container(
      key: ValueKey('page-row-${card.pageId}'),
      decoration: divider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.hairline)),
            )
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scaler = MediaQuery.textScalerOf(context);
          final label = following ? copy.following : copy.follow;
          final labelPainter = TextPainter(
            text: TextSpan(
              text: label,
              style: DefaultTextStyle.of(context).style.merge(
                AppTypography.labelMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
            textScaler: scaler,
            textDirection: Directionality.of(context),
            maxLines: 1,
          )..layout();
          final followWidth = labelPainter.width + 16 + 8 + 24 + 4;
          labelPainter.dispose();
          final nameRoom =
              constraints.maxWidth - 32 - 48 - 12 - 8 - followWidth;
          final stack = nameRoom < scaler.scale(13.5) * 7;
          final identity = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NameWithVipMark(
                uid: card.pageId,
                name: card.displayName,
                maxLines: stack ? 3 : 1,
                style: nameStyle,
              ),
              const SizedBox(height: 4),
              PageTypeChip(kind: card.kind, compact: true),
              if (meta != null) ...[
                const SizedBox(height: 4),
                Text(
                  meta,
                  maxLines: stack ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ],
          );
          // One node: the button role, the name (+ VIP), type and meta as
          // its label, and the tap and focus. Obserwuj stays its own node.
          final open = MergeSemantics(
            child: Semantics(
              button: true,
              child: PagesFocusInk(
                key: ValueKey('page-row-open-${card.pageId}'),
                onTap: onOpen,
                borderRadius: AppRadius.md,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: stack ? 0 : 72),
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      16,
                      10,
                      8,
                      stack ? 4 : 10,
                    ),
                    child: Row(
                      crossAxisAlignment: stack
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
                      children: [
                        PageFace(
                          pageId: card.pageId,
                          name: card.displayName,
                          kind: card.kind,
                          size: 48,
                          localImage: faceImage,
                          mediaService: mediaService,
                          mediaRevision: mediaRevision,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: identity),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          if (stack) {
            // Obserwuj under the text column, outside the row's target.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                open,
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(76, 0, 16, 10),
                  child: button,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: open),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 16),
                child: button,
              ),
            ],
          );
        },
      ),
    );
  }
}
