import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/page_access_service.dart';
import 'package:yovoice/features/pages/presentation/controllers/pages_controllers.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_face.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_focus_ink.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';

/// Which panel row reads as selected.
enum ContentPanelSelection { allPosts, findPages, none }

/// The desktop Treści panel (wall A desktop render, R5, §4.2): the "Treści"
/// heading with search, "Wszystkie posty", the viewer's own Page or the
/// "Utwórz swoją stronę" row, OBSERWOWANE (48 px rows from `findPagesV1
/// following`, loaded on scroll, D10 dot) and a sticky "Znajdź strony".
///
/// Rows grow with the reader's text; the list scrolls so nothing clips at
/// 620 px tall or at 200 %.
class ContentDesktopPanel extends StatefulWidget {
  const ContentDesktopPanel({
    required this.userId,
    required this.followed,
    required this.access,
    required this.selection,
    required this.onAllPosts,
    required this.onFindPages,
    required this.onOpenPage,
    this.onCreatePage,
    this.ownPageName,
    this.showNavigation = true,
    this.selectedPageId,
    super.key,
  });

  /// The Page open in the main column, highlighted in the list.
  final String? selectedPageId;

  /// The owner's display name, for the own-Page row's face fallback.
  final String? ownPageName;

  static const double width = 240;

  final String userId;
  final FollowedPagesController followed;
  final PageAccessState access;
  final ContentPanelSelection selection;
  final VoidCallback onAllPosts;
  final VoidCallback onFindPages;
  final void Function(String pageId, String displayName) onOpenPage;

  /// Null while the create flow is not available (the row is not drawn).
  final VoidCallback? onCreatePage;

  /// False under the kill switch (E9): only the heading stays.
  final bool showNavigation;

  @override
  State<ContentDesktopPanel> createState() => _ContentDesktopPanelState();
}

class _ContentDesktopPanelState extends State<ContentDesktopPanel> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 160) {
      unawaited(widget.followed.loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final titleStyle = AppTypography.rowTitle.copyWith(
      color: palette.textPrimary,
    );
    final heading = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                AppLocalizations.of(context).navigationContent,
                key: const ValueKey('content-panel-title'),
                style: AppTypography.screenTitle.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
          if (widget.showNavigation)
            YoIconButton(
              key: const ValueKey('content-panel-search'),
              icon: Icons.search_rounded,
              onPressed: widget.onFindPages,
              tooltip: copy.findPages,
              size: 44,
            ),
        ],
      ),
    );
    if (!widget.showNavigation) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Align(alignment: Alignment.topCenter, child: heading),
      );
    }
    final ownPage = widget.access.ownPage;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.followed,
              builder: (context, _) {
                final followed = widget.followed;
                final pages = followed.pages;
                return ListView(
                  controller: _scroll,
                  padding: EdgeInsets.zero,
                  children: [
                    _PanelRow(
                      key: const ValueKey('content-panel-all-posts'),
                      selected:
                          widget.selection == ContentPanelSelection.allPosts,
                      lead: const _Glyph(Icons.article_outlined),
                      title: Text(copy.allPosts, style: titleStyle),
                      onTap: widget.onAllPosts,
                    ),
                    if (ownPage != null)
                      _PanelRow(
                        key: const ValueKey('content-panel-own-page'),
                        selected: widget.selectedPageId == widget.userId,
                        lead: PageFace(
                          pageId: widget.userId,
                          name: widget.ownPageName ?? copy.yourPage,
                          kind: ownPage.kind,
                          size: 32,
                        ),
                        title: Text(copy.yourPage, style: titleStyle),
                        onTap: () =>
                            widget.onOpenPage(widget.userId, copy.yourPage),
                      )
                    else if (widget.access.canCreatePage &&
                        widget.onCreatePage != null)
                      _PanelRow(
                        key: const ValueKey('content-panel-create'),
                        lead: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: palette.glass,
                            borderRadius: AppRadius.md,
                            border: Border.all(color: palette.hairlineControl),
                          ),
                          child: Icon(
                            Icons.add_rounded,
                            size: 20,
                            color: palette.interactiveForeground,
                          ),
                        ),
                        title: Text(
                          copy.createYourPage,
                          style: titleStyle.copyWith(
                            color: palette.interactiveForeground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onTap: widget.onCreatePage!,
                      ),
                    if (pages.isNotEmpty ||
                        followed.status == PagesListStatus.loading) ...[
                      const SizedBox(height: AppSpacing.md),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 12,
                          bottom: 8,
                        ),
                        child: Semantics(
                          header: true,
                          child: Text(
                            copy.followedOverline,
                            style: AppTypography.overline.copyWith(
                              color: palette.textTertiary,
                              letterSpacing: .6,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (followed.status == PagesListStatus.loading &&
                        pages.isEmpty)
                      for (var i = 0; i < 3; i++) const _PanelBoneRow(),
                    for (final card in pages)
                      _FollowedRow(
                        card: card,
                        unseen: followed.hasUnseen(card),
                        selected: widget.selectedPageId == card.pageId,
                        titleStyle: titleStyle,
                        onTap: () {
                          followed.markSeen(card.pageId);
                          widget.onOpenPage(card.pageId, card.displayName);
                        },
                      ),
                    if (followed.loadingMore) const _PanelBoneRow(),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _PanelRow(
            key: const ValueKey('content-panel-find'),
            selected: widget.selection == ContentPanelSelection.findPages,
            lead: const _Glyph(Icons.travel_explore_rounded),
            title: Text(copy.findPages, style: titleStyle),
            onTap: widget.onFindPages,
          ),
        ],
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    return Container(
      width: 32,
      height: 32,
      decoration: AppFinish.glyphBox(scheme, highContrast: highContrast),
      child: Icon(icon, size: 18, color: palette.interactiveForeground),
    );
  }
}

/// A 48 px panel row (the rail's selection language: selected fill and a
/// 4 px start bar).
class _PanelRow extends StatelessWidget {
  const _PanelRow({
    required this.lead,
    required this.title,
    required this.onTap,
    this.selected = false,
    this.trailing,
    super.key,
  });

  final Widget lead;
  final Widget title;
  final VoidCallback onTap;
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppRhythm.hairline),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          type: MaterialType.transparency,
          child: PagesFocusInk(
            onTap: onTap,
            borderRadius: AppRadius.md,
            child: Ink(
              decoration: BoxDecoration(
                color: selected ? AppFinish.blockSelectedFill(palette) : null,
                borderRadius: AppRadius.md,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Stack(
                  children: [
                    if (selected)
                      PositionedDirectional(
                        start: 0,
                        top: 8,
                        bottom: 8,
                        child: Container(
                          width: 4,
                          decoration: BoxDecoration(
                            color: palette.interactiveForeground,
                            borderRadius:
                                const BorderRadiusDirectional.horizontal(
                                  end: Radius.circular(4),
                                ).resolve(Directionality.of(context)),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          lead,
                          const SizedBox(width: 12),
                          Expanded(child: title),
                          ?trailing,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FollowedRow extends StatelessWidget {
  const _FollowedRow({
    required this.card,
    required this.unseen,
    required this.titleStyle,
    required this.onTap,
    this.selected = false,
  });

  final PageCard card;
  final bool unseen;
  final bool selected;
  final TextStyle titleStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    return _PanelRow(
      key: ValueKey('content-panel-page-${card.pageId}'),
      selected: selected,
      lead: PageFace(
        pageId: card.pageId,
        name: card.displayName,
        kind: card.kind,
        size: 32,
      ),
      title: NameWithVipMark(
        uid: card.pageId,
        name: card.displayName,
        style: titleStyle,
        semanticsLabel: unseen ? copy.newPostsFrom(card.displayName) : null,
      ),
      trailing: unseen
          ? Padding(
              padding: const EdgeInsetsDirectional.only(start: 6),
              child: Container(
                key: ValueKey('content-panel-dot-${card.pageId}'),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: palette.interactiveForeground,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}

class _PanelBoneRow extends StatelessWidget {
  const _PanelBoneRow();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return ExcludeSemantics(
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: palette.surfaceMuted,
                  borderRadius: AppRadius.md,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: .7,
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: palette.surfaceMuted,
                      borderRadius: AppRadius.sm,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
