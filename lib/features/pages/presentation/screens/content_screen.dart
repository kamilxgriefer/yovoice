import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/embedded_back_scope.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/page_links.dart';
import 'package:yovoice/features/pages/data/services/page_access_service.dart';
import 'package:yovoice/features/pages/data/services/pages_local_store.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/controllers/pages_controllers.dart';
import 'package:yovoice/features/pages/presentation/page_navigation.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/moderation/presentation/widgets/report_reason_sheet.dart';
import 'package:yovoice/features/pages/data/services/page_voice_player.dart';
import 'package:yovoice/features/pages/presentation/page_post_copy.dart';
import 'package:yovoice/features/pages/presentation/page_profile_copy.dart';
import 'package:yovoice/features/pages/presentation/screens/page_composer.dart';
import 'package:yovoice/features/pages/presentation/pages_flows.dart';
import 'package:yovoice/features/pages/presentation/screens/find_pages_screen.dart';
import 'package:yovoice/features/pages/presentation/widgets/content_desktop_panel.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_card_rows.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_face.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_post_card.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_type_chip.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_state_views.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';
import 'package:yovoice/shared/widgets/layout/home_section_header.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

typedef PagesShareLink = Future<void> Function(Uri link);

/// The Treści destination (Premium Pages, spec premium-pages §4.2): shell
/// content slot 14, the six-tab dock's fourth slot and the desktop rail row
/// between Czaty and Momenty. Only reachable while `PagesAvailability`
/// reports Pages enabled for the account.
///
/// Wall A "karty" at three widths, sharing one state:
/// * **Phone (< 600)**: header "Treści" + search 44, the card feed with the
///   "Obserwuj więcej stron" rail after the second post, "Wczytaj więcej".
/// * **Tablet (600-1099)**: the same wall in one centred 640 column.
/// * **Desktop (the shell's desktop layout)**: the 240 px panel (heading,
///   Wszystkie posty, own Page / create row, OBSERWOWANE, Znajdź strony)
///   beside a 640 feed column.
///
/// Find Pages (and, later, the Page profile and post detail) are pushed on
/// Treści's OWN navigator: over the feed on the phone, inside the main
/// column on desktop. So the dock keeps Treści selected, Back returns to the
/// feed, and re-tapping Treści pops back to it (§4.3). While a pushed screen
/// is showing and Treści is the visible tab, the destination holds one level
/// of system Back through [EmbeddedBackScope].
///
/// States (R4): loading, E1 no follows (+ suggestions), E2 = E1 + create,
/// E3 empty directory, E4 no new posts, E9 `pagesNotEnabled` (kill switch)
/// and the error state. VIPs without a Page get the create entries (R5):
/// the phone card, the desktop panel row, and E2/E3.
class ContentScreen extends StatefulWidget {
  const ContentScreen({
    this.isRootTab = false,
    this.pendingPageLink,
    this.isVisible,
    this.reselect,
    this.service,
    this.accessStream,
    this.localStore,
    this.flows = PagesFlows.app,
    this.userId,
    this.userDisplayName,
    this.shareLink,
    this.clock,
    super.key,
  });

  /// True inside the shell's content slot (dock or rail): no app bar, the
  /// shell owns navigation. False when pushed as a route: a real app bar
  /// with Back (CLAUDE.md, the `isRootTab` pattern).
  final bool isRootTab;

  /// A validated `?page=` deep link the shell handed to this destination.
  final ValueListenable<PageLinkTarget?>? pendingPageLink;

  /// Whether Treści is the tab on screen (the shell retains hidden slots).
  /// Only a visible destination holds system Back. Null = always visible.
  final ValueListenable<bool>? isVisible;

  /// Fires when the Treści tab is tapped while already selected: pops to
  /// the feed, else scrolls to the top and reloads.
  final Listenable? reselect;

  /// Test seams; the app uses the shared instances.
  final PagesService? service;
  final Stream<PageAccessState> Function()? accessStream;
  final PagesLocalStore? localStore;
  final PagesFlows flows;
  final String? userId;
  final String? userDisplayName;
  final PagesShareLink? shareLink;
  final DateTime Function()? clock;

  /// The main column's measure on tablet and desktop.
  static const double columnWidth = 640;

  @override
  State<ContentScreen> createState() => _ContentScreenState();
}

class _ContentScreenState extends State<ContentScreen> {
  late final PagesService _service = widget.service ?? PagesService.instance;
  late final PagesFollowRegistry _follows = PagesFollowRegistry(_service);
  late final PagesFeedController _feed = PagesFeedController(
    service: _service,
    follows: _follows,
    clock: widget.clock,
  );
  late final PagesLocalStore _store =
      widget.localStore ?? const SharedPreferencesPagesLocalStore();
  late final String _userId = widget.userId ?? _currentUserId();
  late final String? _userName = widget.userDisplayName ?? _currentUserName();
  FollowedPagesController? _followed;

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final _ContentNavigatorObserver _observer = _ContentNavigatorObserver(
    _onNavigationChanged,
  );
  final ScrollController _feedScroll = ScrollController();

  PageAccessState _access = PageAccessState.unknown;
  StreamSubscription<PageAccessState>? _accessSub;
  bool _createCardDismissed = true;
  bool _canPop = false;
  String? _topRoute;

  static String _currentUserId() {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  static String? _currentUserName() {
    try {
      final name = FirebaseAuth.instance.currentUser?.displayName?.trim();
      return name == null || name.isEmpty ? null : name;
    } catch (_) {
      return null;
    }
  }

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    unawaited(_feed.load());
    final stream =
        widget.accessStream?.call() ?? PageAccessService.instance.watch();
    _accessSub = stream.listen((state) {
      if (mounted && state != _access) setState(() => _access = state);
    }, onError: (Object _, StackTrace _) {});
    unawaited(_readCreateCard());
    widget.reselect?.addListener(_onReselect);
    widget.pendingPageLink?.addListener(_onPendingLink);
    widget.isVisible?.addListener(_onVisibility);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPendingLink());
  }

  /// A voice post never keeps sounding behind another tab. Leaving Treści
  /// after it showed E9 (the kill switch) hands `pagesNotEnabled` to
  /// `PagesAvailability`, so the tab and rail row go away without waiting
  /// for the hourly re-check or a restart; E9 was on screen to explain it.
  void _onVisibility() {
    if (widget.isVisible?.value == false) {
      unawaited(PageVoicePlayer.instance.pause());
      if (_feed.status == PagesFeedStatus.notEnabled) {
        _service.reportNotEnabled();
      }
    }
  }

  @override
  void didUpdateWidget(ContentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reselect != widget.reselect) {
      oldWidget.reselect?.removeListener(_onReselect);
      widget.reselect?.addListener(_onReselect);
    }
    if (oldWidget.isVisible != widget.isVisible) {
      oldWidget.isVisible?.removeListener(_onVisibility);
      widget.isVisible?.addListener(_onVisibility);
    }
    if (oldWidget.pendingPageLink != widget.pendingPageLink) {
      oldWidget.pendingPageLink?.removeListener(_onPendingLink);
      widget.pendingPageLink?.addListener(_onPendingLink);
    }
  }

  @override
  void dispose() {
    widget.reselect?.removeListener(_onReselect);
    widget.pendingPageLink?.removeListener(_onPendingLink);
    widget.isVisible?.removeListener(_onVisibility);
    unawaited(_accessSub?.cancel());
    _feed.dispose();
    _followed?.dispose();
    _follows.dispose();
    _feedScroll.dispose();
    super.dispose();
  }

  Future<void> _readCreateCard() async {
    if (_userId.isEmpty) return;
    var dismissed = false;
    try {
      dismissed = await _store.createCardDismissed(_userId);
    } catch (_) {
      dismissed = false;
    }
    if (mounted) setState(() => _createCardDismissed = dismissed);
  }

  FollowedPagesController _followedController() {
    return _followed ??= () {
      final controller = FollowedPagesController(
        service: _service,
        follows: _follows,
        store: _store,
        userId: _userId,
      );
      unawaited(controller.load());
      return controller;
    }();
  }

  void _onNavigationChanged(bool canPop, String? top) {
    if (!mounted) return;
    if (canPop == _canPop && top == _topRoute) return;
    setState(() {
      _canPop = canPop;
      _topRoute = top;
    });
  }

  NavigatorState? get _navigator => _navigatorKey.currentState;

  /// The Page whose profile is on top of Treści's navigator, if any.
  String? get _openPageId {
    final top = _topRoute;
    const prefix = 'pages/page/';
    return top != null && top.startsWith(prefix)
        ? top.substring(prefix.length)
        : null;
  }

  /// Pops Treści's routes down to the feed, but never through "Edytuj
  /// stronę": that form may hold unsaved edits, and a programmatic pop skips
  /// its "Odrzucić zmiany?" question. Returns whether the feed was reached;
  /// when it was not, the edit form is the top route.
  bool _popToFeed() {
    final navigator = _navigator;
    if (navigator == null) return false;
    var reachedFeed = false;
    navigator.popUntil((route) {
      reachedFeed = route.isFirst;
      return reachedFeed || route.settings.name == pageEditRouteName;
    });
    return reachedFeed;
  }

  /// Re-selecting Treści (or "Wszystkie posty") while "Edytuj stronę" is
  /// open leaves the form the way Back does: it asks first when there are
  /// unsaved edits, and only a form that really closed lets the rest go.
  Future<void> _leaveEditThenFeed(NavigatorState navigator) async {
    await navigator.maybePop();
    if (mounted) _popToFeed();
  }

  void _onReselect() {
    final navigator = _navigator;
    if (navigator != null && navigator.canPop()) {
      if (!_popToFeed()) unawaited(_leaveEditThenFeed(navigator));
      return;
    }
    if (_feedScroll.hasClients && _feedScroll.offset > 0) {
      final reduceMotion =
          MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (reduceMotion) {
        _feedScroll.jumpTo(0);
      } else {
        unawaited(
          _feedScroll.animateTo(
            0,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    }
    unawaited(_feed.load());
  }

  void _onPendingLink() {
    final listenable = widget.pendingPageLink;
    final target = listenable?.value;
    if (target == null || !mounted) return;
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onPendingLink());
      return;
    }
    if (listenable is ValueNotifier<PageLinkTarget?>) listenable.value = null;
    _popToFeed();
    final postId = target.postId;
    final openPost = widget.flows.openPost;
    if (postId != null && openPost != null) {
      unawaited(
        openPost(navigatorContext, pageId: target.pageId, postId: postId),
      );
    } else {
      final open = target.fromLink
          ? widget.flows.openPageFromLink ?? widget.flows.openPage
          : widget.flows.openPage;
      unawaited(open(navigatorContext, pageId: target.pageId));
    }
  }

  // ------------------------------------------------------------- actions

  void _openFind() {
    if (_topRoute == _findRouteName) return;
    final navigator = _navigator;
    if (navigator == null) return;
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: _findRouteName),
          builder: (routeContext) => PagesCanvas(
            child: FindPagesScreen(
              service: _service,
              follows: _follows,
              now: widget.clock,
              onOpenPage: (context, card) =>
                  _openPage(context, card.pageId, card.displayName),
            ),
          ),
        ),
      ),
    );
  }

  void _openPage(BuildContext context, String pageId, String? name) {
    _followed?.markSeen(pageId);
    unawaited(
      widget.flows.openPage(context, pageId: pageId, displayName: name),
    );
  }

  void _openPageFromPanel(String pageId, String name) {
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) return;
    _openPage(navigatorContext, pageId, name);
  }

  void _openCreate(BuildContext context) {
    final flow = widget.flows.openCreatePage;
    if (flow != null) unawaited(flow(context));
  }

  Future<void> _dismissCreateCard() async {
    setState(() => _createCardDismissed = true);
    try {
      await _store.dismissCreateCard(_userId);
    } catch (_) {
      // Dismissed for this session; the next launch may show it once more.
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleLike(BuildContext context, PagePostView post) async {
    final copy = PagesCopy(AppLocalizations.of(context));
    final failure = await _feed.toggleLike(post.postId);
    if (failure != null && context.mounted) {
      _snack(context, copy.likeError(failure));
    }
  }

  Future<void> _toggleFollow(BuildContext context, PageCard card) async {
    final copy = PagesCopy(AppLocalizations.of(context));
    final failure = await _follows.setFollowing(
      card.pageId,
      !_follows.follows(card),
    );
    if (failure != null && context.mounted) {
      _snack(context, copy.followError(failure));
    }
  }

  Future<void> _share(PagePostView post) async {
    final link = buildPageLink(post.pageId, postId: post.postId);
    final share = widget.shareLink;
    if (share != null) {
      await share(link);
      return;
    }
    await SharePlus.instance.share(ShareParams(text: link.toString()));
  }

  /// The owner's composer (R3). The owner does not follow their own Page,
  /// so the new post is not in this feed: a snack offers to open it.
  Future<void> _compose(
    BuildContext context,
    ComposeFlow flow,
    PagePostKind kind,
  ) async {
    final ownPage = _access.ownPage;
    final post = await flow(
      context,
      owner: PageComposerOwner(
        pageId: _userId,
        name:
            ownPage?.displayName ??
            _userName ??
            PagesCopy(AppLocalizations.of(context)).yourPage,
        kind: ownPage?.kind,
      ),
      initialKind: kind,
    );
    if (post == null || !context.mounted) return;
    final copy = PagePostCopy(AppLocalizations.of(context));
    final openPost = widget.flows.openPost;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(copy.published),
        action: openPost == null
            ? null
            : SnackBarAction(
                label: copy.view,
                onPressed: () {
                  final navigatorContext = _navigatorKey.currentContext;
                  if (navigatorContext == null) return;
                  unawaited(
                    openPost(
                      navigatorContext,
                      pageId: post.pageId,
                      postId: post.postId,
                      initial: post,
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _reportPost(BuildContext context, PagePostView post) async {
    final copy = PagesCopy(AppLocalizations.of(context));
    final reason = await showReportReasonSheet(
      context: context,
      title: PagePostCopy(AppLocalizations.of(context)).reportPostTitle,
      subtitle: copy.reportSubtitle,
    );
    if (reason == null || !context.mounted) return;
    try {
      await _service.report(
        target: PageReportTarget.post,
        pageId: post.pageId,
        postId: post.postId,
        reason: reason.name,
      );
      if (context.mounted) _snack(context, copy.reported);
    } on PagesException {
      if (context.mounted) _snack(context, copy.reportFailed);
    }
  }

  Future<void> _showPostMenu(BuildContext context, PagePostView post) async {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final action = await showModalBottomSheet<_PostMenuAction>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: palette.surfaceRaised,
      showDragHandle: false,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) =>
          _PostMenuSheet(post: post, copy: copy, viewerId: _userId),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case _PostMenuAction.share:
        await _share(post);
      case _PostMenuAction.openPage:
        _openPage(context, post.pageId, post.pageName);
      case _PostMenuAction.report:
        await _reportPost(context, post);
    }
  }

  // ---------------------------------------------------------------- build

  static const String _findRouteName = 'pages/find';

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final viewport = MediaQuery.sizeOf(context);
    // The shell's own predicate (MainShell.usesDesktopLayout): the rail
    // needs both the width and a minimum logical height.
    final desktopShell =
        viewport.width >= MainShell.desktopBreakpoint &&
        viewport.height >= DesktopSidebar.minimumSupportedHeight;
    final body = ListenableBuilder(
      listenable: _feed,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final desktop =
              widget.isRootTab && desktopShell && constraints.maxWidth >= 760;
          final navigator = _ContentScope(
            state: this,
            desktop: desktop,
            access: _access,
            createCardDismissed: _createCardDismissed,
            showHeader: widget.isRootTab && !desktop,
            child: PagesNavigatorScope(
              desktop: desktop,
              // Its own semantic container: the routes' modal barriers block
              // the semantics of everything painted before them in the same
              // container, which without this boundary took the desktop
              // panel, the shell rail and the phone banners out of the
              // accessibility tree while Treści was the visible tab.
              child: Semantics(
                container: true,
                child: Navigator(
                  key: _navigatorKey,
                  observers: <NavigatorObserver>[_observer],
                  onGenerateInitialRoutes: (navigator, initialRoute) => [
                    MaterialPageRoute<void>(
                      settings: const RouteSettings(name: 'pages/wall'),
                      builder: (_) => const _WallView(),
                    ),
                  ],
                ),
              ),
            ),
          );
          if (!desktop) return navigator;
          final notEnabled = _feed.status == PagesFeedStatus.notEnabled;
          // "Edytuj stronę" takes the whole content slot (pageEdit A, the
          // approved 1440 frame: the form with its standing preview beside
          // the shell's rail). The panel is kept alive and only steps
          // aside, so it is back, unchanged, when the form closes.
          final focused = _topRoute == pageEditRouteName;
          // Keyboard order between the two columns: the panel is group 1,
          // the feed column (and whatever is pushed over it) group 2, so Tab
          // leaves the end of the feed for the panel instead of looping.
          return FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: focused ? 0 : 24),
                Visibility(
                  key: const ValueKey('content-desktop-panel-slot'),
                  visible: !focused,
                  maintainState: true,
                  child: SizedBox(
                    width: ContentDesktopPanel.width,
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(1),
                      child: FocusTraversalGroup(
                        child: ContentDesktopPanel(
                          userId: _userId,
                          ownPageName: _userName,
                          followed: _followedController(),
                          access: _access,
                          showNavigation: !notEnabled,
                          selectedPageId: _openPageId,
                          selection: _topRoute == _findRouteName
                              ? ContentPanelSelection.findPages
                              : _canPop
                              ? ContentPanelSelection.none
                              : ContentPanelSelection.allPosts,
                          onAllPosts: () {
                            if (_canPop) {
                              _popToFeed();
                            } else {
                              _onReselect();
                            }
                          },
                          onFindPages: _openFind,
                          onOpenPage: _openPageFromPanel,
                          onCreatePage: widget.flows.openCreatePage == null
                              ? null
                              : () {
                                  final navigatorContext =
                                      _navigatorKey.currentContext;
                                  if (navigatorContext != null) {
                                    _openCreate(navigatorContext);
                                  }
                                },
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: focused ? 0 : 24),
                Expanded(
                  child: FocusTraversalOrder(
                    order: const NumericFocusOrder(2),
                    child: FocusTraversalGroup(child: navigator),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    final visible = widget.isVisible;
    Widget scoped(bool isVisible) => EmbeddedBackScope(
      claimed: isVisible && _canPop,
      onBack: () => unawaited(_navigator?.maybePop()),
      child: body,
    );
    final content = visible == null
        ? scoped(true)
        : ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, isVisible, _) => scoped(isVisible),
          );
    if (widget.isRootTab) {
      return PagesCanvas(
        child: Material(type: MaterialType.transparency, child: content),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(copy.navigationContent),
        actions: [
          ListenableBuilder(
            listenable: _feed,
            builder: (context, _) => _feed.status == PagesFeedStatus.notEnabled
                ? const SizedBox.shrink()
                : IconButton(
                    onPressed: _openFind,
                    tooltip: PagesCopy(copy).findPages,
                    icon: const Icon(Icons.search_rounded),
                  ),
          ),
        ],
      ),
      body: PagesCanvas(child: content),
    );
  }
}

class _ContentNavigatorObserver extends NavigatorObserver {
  _ContentNavigatorObserver(this.onChanged);

  final void Function(bool canPop, String? top) onChanged;

  void _report(Route<dynamic>? top) {
    // Navigator callbacks can arrive mid-build (the initial route).
    scheduleMicrotask(() {
      final nav = navigator;
      if (nav == null) return;
      onChanged(nav.canPop(), top?.settings.name);
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _report(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _report(previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _report(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _report(newRoute);
}

/// Hands the destination's state to the routes of its own navigator.
class _ContentScope extends InheritedWidget {
  const _ContentScope({
    required this.state,
    required this.desktop,
    required this.access,
    required this.createCardDismissed,
    required this.showHeader,
    required super.child,
  });

  final _ContentScreenState state;
  final bool desktop;
  final PageAccessState access;
  final bool createCardDismissed;
  final bool showHeader;

  static _ContentScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ContentScope>()!;

  @override
  bool updateShouldNotify(_ContentScope oldWidget) =>
      desktop != oldWidget.desktop ||
      access != oldWidget.access ||
      createCardDismissed != oldWidget.createCardDismissed ||
      showHeader != oldWidget.showHeader;
}

/// The feed route: wall A.
class _WallView extends StatelessWidget {
  const _WallView();

  @override
  Widget build(BuildContext context) {
    final scope = _ContentScope.of(context);
    final state = scope.state;
    return ListenableBuilder(
      listenable: Listenable.merge([state._feed, state._follows]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) =>
            _wall(context, scope, constraints.maxWidth),
      ),
    );
  }

  Widget _wall(BuildContext context, _ContentScope scope, double width) {
    final state = scope.state;
    final feed = state._feed;
    final flows = state.widget.flows;
    final copy = PagesCopy(AppLocalizations.of(context));
    final desktop = scope.desktop;
    final wide = desktop || width >= 600;
    final column = desktop
        ? ContentScreen.columnWidth
        : wide
        ? ContentScreen.columnWidth + 32
        : width;
    final side = ((width - column) / 2).clamp(0.0, double.infinity);
    final gutter = desktop ? 0.0 : 16.0;
    final pad = EdgeInsets.symmetric(horizontal: side + gutter);
    final access = scope.access;
    final notEnabled = feed.status == PagesFeedStatus.notEnabled;

    final slivers = <Widget>[];
    if (scope.showHeader) {
      slivers.add(
        SliverSafeArea(
          bottom: false,
          sliver: SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: side + 16),
            sliver: SliverToBoxAdapter(
              child: _WallHeader(
                showSearch: !notEnabled,
                onSearch: state._openFind,
              ),
            ),
          ),
        ),
      );
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));
    } else {
      slivers.add(
        SliverToBoxAdapter(child: SizedBox(height: desktop ? 16 : 8)),
      );
    }

    Widget boxed(Widget child) => SliverPadding(
      padding: pad,
      sliver: SliverToBoxAdapter(child: child),
    );
    // State blocks carry their own 32 px side padding (as YoEmptyState).
    Widget stateBoxed(Widget child) => SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: side),
      sliver: SliverToBoxAdapter(child: child),
    );
    SliverToBoxAdapter gap(double height) =>
        SliverToBoxAdapter(child: SizedBox(height: height));

    switch (feed.status) {
      case PagesFeedStatus.loading:
        slivers.add(
          boxed(
            Semantics(
              label: copy.loadingPosts,
              child: const Column(
                children: [
                  PagesSkeletonCard(media: true),
                  SizedBox(height: AppRhythm.title),
                  PagesSkeletonCard(),
                  SizedBox(height: AppRhythm.title),
                  PagesSkeletonCard(),
                ],
              ),
            ),
          ),
        );
      case PagesFeedStatus.error:
        slivers.add(
          stateBoxed(
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: YoErrorState(
                message: copy.loadError,
                onRetry: () => unawaited(feed.load()),
              ),
            ),
          ),
        );
      case PagesFeedStatus.notEnabled:
        slivers.add(
          stateBoxed(
            Padding(
              key: const ValueKey('pages-e9'),
              padding: const EdgeInsets.only(top: 70),
              child: PagesStateBlock(
                icon: Icons.article_outlined,
                title: copy.e9Title,
                body: copy.e9Body,
                pill: copy.e9Pill,
              ),
            ),
          ),
        );
      case PagesFeedStatus.ready:
        _readySlivers(
          context,
          scope: scope,
          slivers: slivers,
          boxed: boxed,
          stateBoxed: stateBoxed,
          gap: gap,
          pad: pad,
          side: side,
          gutter: gutter,
          access: access,
          flows: flows,
          copy: copy,
        );
    }
    slivers.add(gap(AppRhythm.page));

    final scrollView = CustomScrollView(
      key: const ValueKey('content-feed'),
      controller: state._feedScroll,
      primary: false,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: slivers,
    );
    if (feed.status != PagesFeedStatus.ready) return scrollView;
    return RefreshIndicator(onRefresh: feed.load, child: scrollView);
  }

  void _readySlivers(
    BuildContext context, {
    required _ContentScope scope,
    required List<Widget> slivers,
    required Widget Function(Widget) boxed,
    required Widget Function(Widget) stateBoxed,
    required SliverToBoxAdapter Function(double) gap,
    required EdgeInsets pad,
    required double side,
    required double gutter,
    required PageAccessState access,
    required PagesFlows flows,
    required PagesCopy copy,
  }) {
    final state = scope.state;
    final feed = state._feed;
    final ownPage = access.ownPage;
    final createFlow = flows.openCreatePage;
    final canCreate = access.canCreatePage && createFlow != null;
    final emptyKind = feed.emptyKind;

    // Owner: the composer entry (R5) on every width.
    final composeFlow = flows.openComposer;
    if (ownPage != null && ownPage.canPublish && composeFlow != null) {
      slivers.add(
        boxed(
          OwnerComposerEntry(
            pageId: state._userId,
            pageName: state._userName ?? copy.yourPage,
            kind: ownPage.kind,
            wide: scope.desktop,
            onCompose: (kind) =>
                unawaited(state._compose(context, composeFlow, kind)),
          ),
        ),
      );
      slivers.add(gap(AppRhythm.title));
    }
    // VIP without a Page on the phone shell: the dismissible card (R5). The
    // desktop panel carries its own row instead; the empty states carry the
    // action themselves.
    if (canCreate &&
        !scope.desktop &&
        !scope.createCardDismissed &&
        emptyKind == null) {
      slivers.add(
        boxed(
          CreatePageCard(
            onStart: () => state._openCreate(context),
            onDismiss: () => unawaited(state._dismissCreateCard()),
          ),
        ),
      );
      slivers.add(gap(AppRhythm.title));
    }

    final follow = PageFollowBinding(
      follows: state._follows.follows,
      busy: (card) => state._follows.isBusy(card.pageId),
      onToggle: (card) => unawaited(state._toggleFollow(context, card)),
    );

    if (emptyKind != null) {
      _emptySlivers(
        context,
        kind: emptyKind,
        scope: scope,
        slivers: slivers,
        boxed: boxed,
        stateBoxed: stateBoxed,
        gap: gap,
        canCreate: canCreate,
        follow: follow,
        copy: copy,
      );
      return;
    }

    final posts = feed.posts;
    final suggestions = feed.suggestions;
    final railAfter = posts.length >= 2 ? 1 : posts.length - 1;
    final now = state._now();
    for (var i = 0; i < posts.length; i++) {
      final post = posts[i];
      if (i > 0) slivers.add(gap(AppRhythm.title));
      slivers.add(
        boxed(
          PagePostCard(
            key: ValueKey('page-post-${post.postId}'),
            post: post,
            now: now,
            service: state._service,
            likeBusy: feed.isLikeBusy(post.postId),
            lead: i == 0,
            photoMaxHeight: pad.horizontal > 32 || scope.desktop ? 420 : null,
            onOpenPage: () =>
                state._openPage(context, post.pageId, post.pageName),
            onToggleLike: () => unawaited(state._toggleLike(context, post)),
            onShare: () => unawaited(state._share(post)),
            onMore: () => unawaited(state._showPostMenu(context, post)),
            onComment: flows.openPost == null
                ? null
                : () => unawaited(
                    flows.openPost!(
                      context,
                      pageId: post.pageId,
                      postId: post.postId,
                      initial: post,
                      focusComposer: true,
                    ),
                  ),
            onOpenPhotos: flows.openPost == null
                ? null
                : () => unawaited(
                    flows.openPost!(
                      context,
                      pageId: post.pageId,
                      postId: post.postId,
                      initial: post,
                    ),
                  ),
            onOpenLikers: flows.openLikers == null
                ? null
                : () => unawaited(flows.openLikers!(context, post)),
            onPlayVoice: flows.playVoice == null
                ? null
                : () => unawaited(flows.playVoice!(context, post)),
          ),
        ),
      );
      if (i == railAfter && suggestions.isNotEmpty) {
        slivers.add(gap(AppRhythm.section));
        slivers.add(
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: side),
            sliver: SliverToBoxAdapter(
              child: PageSuggestionRail(
                key: const ValueKey('pages-suggestion-rail'),
                title: copy.followMorePages,
                pages: suggestions,
                follow: follow,
                gutter: gutter,
                onSeeAll: state._openFind,
                onOpenPage: (card) =>
                    state._openPage(context, card.pageId, card.displayName),
              ),
            ),
          ),
        );
        if (i < posts.length - 1) slivers.add(gap(AppRhythm.section));
      }
    }
    final showMore = feed.hasMore || feed.loadingMore || feed.loadMoreFailed;
    if (showMore) slivers.add(gap(AppRhythm.section));
    slivers.add(
      KeyedSubtree(
        // Stable across the gap above appearing and going, so the button
        // (and its announcement of the last page) keeps its state.
        key: const ValueKey('pages-load-more-slot'),
        child: boxed(
          Center(
            child: PagesLoadMoreButton(
              visible: showMore,
              loading: feed.loadingMore,
              failed: feed.loadMoreFailed,
              itemCount: posts.length,
              onPressed: () => unawaited(feed.loadMore()),
            ),
          ),
        ),
      ),
    );
  }

  void _emptySlivers(
    BuildContext context, {
    required PagesFeedEmptyKind kind,
    required _ContentScope scope,
    required List<Widget> slivers,
    required Widget Function(Widget) boxed,
    required Widget Function(Widget) stateBoxed,
    required SliverToBoxAdapter Function(double) gap,
    required bool canCreate,
    required PageFollowBinding follow,
    required PagesCopy copy,
  }) {
    final state = scope.state;
    final feed = state._feed;
    switch (kind) {
      case PagesFeedEmptyKind.noFollows:
        slivers.add(
          stateBoxed(
            PagesStateBlock(
              key: ValueKey(canCreate ? 'pages-e2' : 'pages-e1'),
              icon: Icons.dynamic_feed_outlined,
              title: copy.e1Title,
              body: copy.e1Body,
              primaryLabel: copy.findPages,
              onPrimary: state._openFind,
              secondary: canCreate
                  ? PagesTonalButton(
                      label: copy.createYourPage,
                      icon: Icons.add_business_outlined,
                      height: 48,
                      onPressed: () => state._openCreate(context),
                    )
                  : null,
            ),
          ),
        );
        final suggestions = feed.suggestions.take(5).toList(growable: false);
        if (suggestions.isNotEmpty) {
          final now = state._now();
          slivers.add(
            boxed(
              HomeSectionHeader(
                title: copy.suggestedPages,
                onSeeAll: state._openFind,
                seeAllLabel: copy.seeAll,
              ),
            ),
          );
          slivers.add(gap(4));
          for (final card in suggestions) {
            final last = card.lastPostAtMs;
            slivers.add(
              SliverToBoxAdapter(
                child: _CenteredRow(
                  desktop: scope.desktop,
                  child: PageListRow(
                    card: card,
                    follow: follow,
                    onOpen: () =>
                        state._openPage(context, card.pageId, card.displayName),
                    lastPostLabel: last == null
                        ? null
                        : copy.lastPost(
                            DateTime.fromMillisecondsSinceEpoch(
                              last,
                              isUtc: true,
                            ),
                            now,
                          ),
                  ),
                ),
              ),
            );
          }
        }
      case PagesFeedEmptyKind.noPages:
        slivers.add(
          stateBoxed(
            Padding(
              key: const ValueKey('pages-e3'),
              padding: const EdgeInsets.only(top: 60),
              child: PagesStateBlock(
                icon: Icons.dynamic_feed_outlined,
                title: copy.e3Title,
                body: copy.e3Body,
                primaryLabel: canCreate ? copy.createYourPage : null,
                onPrimary: canCreate ? () => state._openCreate(context) : null,
              ),
            ),
          ),
        );
      case PagesFeedEmptyKind.noNewPosts:
        slivers.add(
          stateBoxed(
            Padding(
              key: const ValueKey('pages-e4'),
              padding: const EdgeInsets.only(top: 60),
              child: PagesStateBlock(
                icon: Icons.schedule_outlined,
                title: copy.e4Title,
                body: copy.e4Body,
                secondary: PagesTonalButton(
                  label: copy.findMorePages,
                  icon: Icons.travel_explore_rounded,
                  height: 48,
                  onPressed: state._openFind,
                ),
              ),
            ),
          ),
        );
    }
  }
}

/// Keeps an edge-to-edge list row inside the wall's column.
class _CenteredRow extends StatelessWidget {
  const _CenteredRow({required this.desktop, required this.child});

  final bool desktop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: desktop
              ? ContentScreen.columnWidth
              : ContentScreen.columnWidth + 32,
        ),
        child: child,
      ),
    );
  }
}

/// "Treści" + the 44 px search button (wall A phone header).
class _WallHeader extends StatelessWidget {
  const _WallHeader({required this.showSearch, required this.onSearch});

  final bool showSearch;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                copy.navigationContent,
                key: const ValueKey('content-screen-title'),
                style: AppTypography.screenTitle.copyWith(
                  color: palette.textPrimary,
                  fontSize: 26,
                ),
              ),
            ),
          ),
          if (showSearch)
            YoIconButton(
              key: const ValueKey('content-search'),
              icon: Icons.search_rounded,
              onPressed: onSearch,
              tooltip: PagesCopy(copy).findPages,
              size: 44,
              iconSize: 22,
            ),
        ],
      ),
    );
  }
}

enum _PostMenuAction { share, openPage, report }

/// The card's ⋯ sheet: the Page's identity, Udostępnij post, Przejdź do
/// strony and Zgłoś post (R10's sheet language).
class _PostMenuSheet extends StatelessWidget {
  const _PostMenuSheet({
    required this.post,
    required this.copy,
    required this.viewerId,
  });

  final PagePostView post;
  final PagesCopy copy;
  final String viewerId;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    Widget item(IconData icon, String label, _PostMenuAction action) =>
        ListTile(
          minTileHeight: 56,
          leading: Icon(icon, color: palette.textPrimary),
          title: Text(
            label,
            style: AppTypography.titleMedium.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          onTap: () => Navigator.of(context).pop(action),
        );
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YoModalSheetChrome(
                sheetLabel: copy.moreOptions,
                surfaceColor: palette.surfaceRaised,
                onClose: () => Navigator.of(context).pop(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    PageFace(
                      pageId: post.pageId,
                      name: post.pageName,
                      kind: post.pageKind,
                      size: 48,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          NameWithVipMark(
                            uid: post.pageId,
                            name: post.pageName,
                            maxLines: 2,
                            style: AppTypography.rowTitle.copyWith(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          PageTypeChip(kind: post.pageKind, compact: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: palette.hairline, height: 1),
              item(
                Icons.ios_share_rounded,
                copy.sharePost,
                _PostMenuAction.share,
              ),
              item(
                Icons.storefront_outlined,
                copy.goToPage,
                _PostMenuAction.openPage,
              ),
              if (post.pageId != viewerId) ...[
                Divider(color: palette.hairline, height: 1),
                ListTile(
                  key: const ValueKey('page-post-report'),
                  minTileHeight: 56,
                  leading: Icon(
                    Icons.flag_outlined,
                    color: palette.dangerForeground,
                  ),
                  title: Text(
                    PagePostCopy(copy.copy).reportPost,
                    style: AppTypography.titleMedium.copyWith(
                      color: palette.dangerForeground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () =>
                      Navigator.of(context).pop(_PostMenuAction.report),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
