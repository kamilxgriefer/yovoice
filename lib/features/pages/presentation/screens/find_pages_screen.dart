import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/controllers/pages_controllers.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_card_rows.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_focus_ink.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_state_views.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/inputs/yo_search_field.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

/// Find Pages (spec premium-pages §4.7, R4 `P_znajdz-strony_*`, E10): a
/// search field, PROPONOWANE rows until two characters are typed, then
/// STRONY results. No filter chips in v1.
///
/// Pushed on Treści's own navigator, on the phone over the feed and on
/// desktop inside the main column, so the dock (or the rail and panel) stay
/// with Treści selected. It draws its own Back, never an app bar.
class FindPagesScreen extends StatefulWidget {
  const FindPagesScreen({
    required this.service,
    required this.follows,
    required this.onOpenPage,
    this.showBack = true,
    this.now,
    super.key,
  });

  final PagesService service;
  final PagesFollowRegistry follows;
  final void Function(BuildContext context, PageCard card) onOpenPage;

  /// False only where nothing sits under this screen to go back to.
  final bool showBack;

  /// Test seam for "post 2 godz. temu".
  final DateTime Function()? now;

  static const double maxColumnWidth = 672;

  @override
  State<FindPagesScreen> createState() => _FindPagesScreenState();
}

class _FindPagesScreenState extends State<FindPagesScreen> {
  late final FindPagesController _controller = FindPagesController(
    service: widget.service,
  );
  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();
  PagesListStatus _announcedStatus = PagesListStatus.idle;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.start());
    _scroll.addListener(_maybeLoadMore);
    _controller.addListener(_announceOutcome);
  }

  /// Results change without focus moving: a screen reader hears how many
  /// Pages a search found, that nothing was found, or that it failed.
  void _announceOutcome() {
    final status = _controller.status;
    if (status == _announcedStatus) return;
    final wasLoading = _announcedStatus == PagesListStatus.loading;
    _announcedStatus = status;
    if (!wasLoading || !mounted) return;
    final copy = PagesCopy(AppLocalizations.of(context));
    final searching = _controller.mode == FindPagesMode.search;
    switch (status) {
      case PagesListStatus.error:
        announcePages(context, copy.searchError, assertive: true);
      case PagesListStatus.ready:
        if (!searching) return;
        final count = _controller.pages.length;
        if (count > 0) {
          announcePages(context, copy.searchResults(count));
        } else if (defaultTargetPlatform != TargetPlatform.android) {
          // Android reads the empty state's live region itself.
          announcePages(context, copy.nothingFound);
        }
      case PagesListStatus.idle:
      case PagesListStatus.loading:
        break;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_announceOutcome);
    _controller.dispose();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      unawaited(_controller.loadMore());
    }
  }

  Future<void> _toggleFollow(PageCard card) async {
    final registry = widget.follows;
    final following = registry.follows(card);
    final failure = await registry.setFollowing(card.pageId, !following);
    if (!mounted || failure == null) return;
    final copy = PagesCopy(AppLocalizations.of(context));
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(copy.followError(failure))));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final top = MediaQuery.paddingOf(context).top;
    final bar = SizedBox(
      height: 60,
      child: Row(
        children: [
          const SizedBox(width: 6),
          if (widget.showBack)
            YoIconButton(
              icon: Icons.arrow_back_rounded,
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: copy.back,
              size: 44,
              backgroundColor: Colors.transparent,
              borderColor: Colors.transparent,
            )
          else
            const SizedBox(width: 10),
          const SizedBox(width: 4),
          Expanded(
            child: YoSearchField(
              key: const ValueKey('find-pages-field'),
              controller: _query,
              hint: copy.searchHint,
              onChanged: _controller.updateQuery,
              onClear: () {
                _query.clear();
                _controller.updateQuery('');
              },
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: FindPagesScreen.maxColumnWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: top),
              bar,
              Expanded(
                child: ListenableBuilder(
                  listenable: Listenable.merge([_controller, widget.follows]),
                  builder: (context, _) => _body(context, copy, palette),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, PagesCopy copy, AppPalette palette) {
    final controller = _controller;
    switch (controller.status) {
      case PagesListStatus.idle:
      case PagesListStatus.loading:
        return Center(child: YoLoadingIndicator(semanticLabel: copy.findPages));
      case PagesListStatus.error:
        return SingleChildScrollView(
          child: YoErrorState(
            message: copy.searchError,
            onRetry: () => unawaited(controller.retry()),
          ),
        );
      case PagesListStatus.ready:
        break;
    }
    final searching = controller.mode == FindPagesMode.search;
    if (controller.pages.isEmpty) {
      return SingleChildScrollView(
        key: const ValueKey('find-pages-empty'),
        child: searching
            ? PagesStateBlock(
                key: const ValueKey('find-pages-no-results'),
                liveRegion: true,
                icon: Icons.search_off_rounded,
                title: copy.nothingFound,
                body: copy.nothingFoundBody,
              )
            : PagesStateBlock(
                icon: Icons.dynamic_feed_outlined,
                title: copy.e3Title,
                body: copy.e3Body,
              ),
      );
    }
    final now = (widget.now ?? DateTime.now)();
    final binding = PageFollowBinding(
      follows: widget.follows.follows,
      busy: (card) => widget.follows.isBusy(card.pageId),
      onToggle: (card) => unawaited(_toggleFollow(card)),
    );
    final pages = controller.pages;
    final footer = controller.hasMore ? 1 : 0;
    return ListView.builder(
      key: const ValueKey('find-pages-list'),
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: 1 + pages.length + footer,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
            child: Semantics(
              header: true,
              child: Text(
                searching ? copy.pagesOverline : copy.suggestedOverline,
                style: AppTypography.overline.copyWith(
                  color: palette.textTertiary,
                  letterSpacing: .6,
                ),
              ),
            ),
          );
        }
        final at = index - 1;
        if (at >= pages.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: PagesLoadMoreButton(
                loading: controller.loadingMore,
                failed: false,
                itemCount: pages.length,
                height: 44,
                onPressed: () => unawaited(controller.loadMore()),
              ),
            ),
          );
        }
        final card = pages[at];
        final last = card.lastPostAtMs;
        return PageListRow(
          card: card,
          follow: binding,
          onOpen: () => widget.onOpenPage(context, card),
          lastPostLabel: !searching && last != null
              ? copy.lastPost(
                  DateTime.fromMillisecondsSinceEpoch(last, isUtc: true),
                  now,
                )
              : null,
        );
      },
    );
  }
}
