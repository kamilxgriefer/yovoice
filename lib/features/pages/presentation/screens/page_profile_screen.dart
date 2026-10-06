import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/page_links.dart';
import 'package:yovoice/features/pages/data/services/page_access_service.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/controllers/page_profile_controller.dart';
import 'package:yovoice/features/pages/presentation/page_account_actions.dart';
import 'package:yovoice/features/pages/presentation/page_navigation.dart';
import 'package:yovoice/features/pages/presentation/page_profile_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/moderation/presentation/widgets/report_reason_sheet.dart';
import 'package:yovoice/features/pages/data/services/page_post_events.dart';
import 'package:yovoice/features/pages/data/services/page_voice_player.dart';
import 'package:yovoice/features/pages/presentation/page_post_copy.dart';
import 'package:yovoice/features/pages/presentation/screens/page_composer.dart';
import 'package:yovoice/features/pages/presentation/pages_flows.dart';
import 'package:yovoice/features/pages/presentation/screens/page_edit_screen.dart';
import 'package:yovoice/features/pages/presentation/screens/page_settings_screen.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_face.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_menus.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_post_card.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_profile_parts.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_state_views.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_local_tabs.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';
import 'package:yovoice/shared/widgets/navigation/yo_server_rail_item.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

typedef PageShareLink = Future<void> Function(Uri link);

enum _Layout { phone, tablet, desktop }

enum _PageMenu {
  call,
  voiceMessage,
  invite,
  share,
  settings,
  report,
  removeFriend,
  block,
}

enum _PostMenu { pin, unpin, share, comments, delete, report }

/// The Page profile, variant B "okładka" (approved `tresci-ui/profile/B_*`;
/// R8 owner and tablet, R9 Informacje, R10 ⋯ menus, R12 notices, R15
/// stacked actions; spec premium-pages §4.3).
///
/// * **Phone (< 600)**: the cover (184, scrim) runs under the status bar
///   with glass Back and ⋯; face 80 with a 3 px ring overlapping the cover;
///   name + rosette (44×44 tap → the VIP sheet), meta, a two-line
///   description, the action row (stacked below 360 px or at ≥ 1.3× text),
///   then text-only tabs Tablica · Informacje · Zdjęcia.
/// * **Tablet (600-899)**: the same in one 640 column, a rounded cover 160.
/// * **Desktop (≥ 900, or Treści's desktop main)**: a header card with a
///   216 cover and face 96, the actions beside the name, tabs Tablica ·
///   Zdjęcia, and a 296 px right column (Informacje + photo preview).
///
/// It is pushed on Treści's own navigator (the dock keeps Treści selected)
/// or, from outside, hosted by the shell; either way it draws its own Back
/// on phone and tablet (the glass disc is its app bar) and none on desktop,
/// where the wall-A panel navigates.
///
/// When `getPageV1` answers `pageUnavailable` or `pagesNotEnabled` the
/// screen opens the ordinary personal profile instead (§4.3 fallback, so a
/// kill switch or a block never strands a friend or a victim); only a
/// deep link ([fromLink]) shows E7.
class PageProfileScreen extends StatefulWidget {
  const PageProfileScreen({
    required this.pageId,
    this.displayName,
    this.fromLink = false,
    this.service,
    this.actions,
    this.flows = PagesFlows.app,
    this.accessStream,
    this.userId,
    this.clock,
    this.shareLink,
    this.settingsBuilder,
    this.editBuilder,
    super.key,
  });

  final String pageId;

  /// What the opener already knows, shown while the Page loads.
  final String? displayName;

  /// Opened from a `?page=` link: an unavailable Page shows E7.
  final bool fromLink;

  /// Test seams; the app uses the shared instances.
  final PagesService? service;
  final PageAccountActions? actions;
  final PagesFlows flows;
  final Stream<PageAccessState> Function()? accessStream;
  final String? userId;
  final DateTime Function()? clock;
  final PageShareLink? shareLink;

  /// Builds the owner's Page settings (test seam).
  final WidgetBuilder? settingsBuilder;

  /// Builds the owner's "Edytuj stronę" (test seam).
  final WidgetBuilder? editBuilder;

  static const double phoneCover = 184;
  static const double tabletCover = 160;
  static const double desktopCover = 216;
  static const double face = 80;
  static const double desktopFace = 96;
  static const double columnWidth = 640;
  static const double desktopMaxWidth = 864;
  static const double aboutColumnWidth = 296;

  @override
  State<PageProfileScreen> createState() => _PageProfileScreenState();
}

class _PageProfileScreenState extends State<PageProfileScreen> {
  late final PagesService _service = widget.service ?? PagesService.instance;
  late final PageAccountActions _actions =
      widget.actions ?? const AppPageAccountActions();
  late final PageProfileController _controller = PageProfileController(
    service: _service,
    pageId: widget.pageId,
  );
  late final String _userId = widget.userId ?? _currentUserId();
  final ScrollController _scroll = ScrollController();
  final FocusNode _followFocus = FocusNode(debugLabel: 'page-follow');
  final FocusNode _followingFocus = FocusNode(debugLabel: 'page-following');

  int _tab = 0;
  FriendRelationshipStatus? _relationship;
  OwnPage? _ownPage;
  StreamSubscription<PageAccessState>? _accessSub;
  bool _fallbackStarted = false;
  bool _everShown = false;

  bool get _isSelf => _userId.isNotEmpty && _userId == widget.pageId;

  static String _currentUserId() {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    unawaited(_controller.load());
    if (_isSelf) {
      final stream =
          widget.accessStream?.call() ?? PageAccessService.instance.watch();
      _accessSub = stream.listen((state) {
        if (!mounted || state.ownPage == _ownPage) return;
        final previous = _ownPage;
        setState(() => _ownPage = state.ownPage);
        // The owner changed the Page (paused or resumed in settings, or
        // saved "Edytuj stronę": name, category, description, contact):
        // refresh, so the header and Informacje show what was stored.
        if (previous != null) unawaited(_controller.load());
      }, onError: (Object _, StackTrace _) {});
    } else {
      unawaited(_resolveRelationship());
    }
  }

  Future<void> _resolveRelationship() async {
    final status = await _actions.relationship(widget.pageId);
    if (mounted && status != null) setState(() => _relationship = status);
  }

  @override
  void dispose() {
    final shown = {
      for (final post in _controller.wallPosts) post.postId,
      for (final post in _controller.photos.posts) post.postId,
    };
    PageVoicePlayer.silenceSharedIf(shown.contains);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    unawaited(_accessSub?.cancel());
    _scroll.dispose();
    _followFocus.dispose();
    _followingFocus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final status = _controller.status;
    if (status == PageProfileStatus.ready) _everShown = true;
    // Only the first answer falls back: a Page that was on screen and then
    // became unavailable on a refresh stays here with its state.
    if (_fallbackStarted || widget.fromLink || _everShown) return;
    if (status != PageProfileStatus.unavailable &&
        status != PageProfileStatus.notEnabled) {
      return;
    }
    final navigator = Navigator.maybeOf(context);
    final route = ModalRoute.of(context);
    if (navigator == null || route == null || !navigator.canPop()) return;
    _fallbackStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final actions = _actions;
      final host = navigator.context;
      // Remove this profile's OWN route: a sheet, dialog or post detail
      // above it must never be the one popped.
      if (route.isCurrent) {
        navigator.pop();
      } else if (route.isActive) {
        navigator.removeRoute(route);
      }
      unawaited(
        actions.openPersonalProfile(
          host,
          uid: widget.pageId,
          name: widget.displayName,
        ),
      );
    });
  }

  // ------------------------------------------------------------- helpers

  PagesCopy get _copy => PagesCopy(AppLocalizations.of(context));

  void _snack(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  String get _name =>
      _controller.header?.displayName ?? widget.displayName ?? _copy.yourPage;

  PageKind? get _kind => _controller.header?.kind;

  Future<void> _share(Uri link) async {
    final share = widget.shareLink;
    if (share != null) {
      await share(link);
      return;
    }
    await SharePlus.instance.share(ShareParams(text: link.toString()));
  }

  void _back() => unawaited(Navigator.of(context).maybePop());

  void _openSettings() {
    final builder = widget.settingsBuilder;
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'pages/settings'),
          builder:
              builder ??
              (_) => PageSettingsScreen(service: _service, userId: _userId),
        ),
      ),
    );
  }

  /// "Edytuj stronę": the one form with the live preview. What it saves
  /// reaches this screen through the owner's own Page record (see
  /// [initState]), which reloads the header.
  void _openEdit() => unawaited(
    openPageEdit(
      context,
      builder:
          widget.editBuilder ??
          (_) => PageEditScreen(service: _service, userId: _userId),
    ),
  );

  Future<void> _resume() async {
    try {
      await _service.resumePage();
      if (!mounted) return;
      _snack(_copy.pageResumedSnack);
      unawaited(_controller.load());
    } on PagesException catch (error) {
      if (mounted) _snack(_copy.manageError(error.failure));
    }
  }

  Future<void> _setFollowing(bool following) async {
    // Obserwuj and Obserwujesz are different controls: keyboard focus follows
    // the swap instead of falling back to the top of the header.
    final hadFocus = _followFocus.hasFocus || _followingFocus.hasFocus;
    final failure = await _controller.setFollowing(following);
    if (!mounted) return;
    if (failure != null) _snack(_copy.followError(failure));
    if (!hadFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = (_controller.viewer?.following ?? false)
          ? _followingFocus
          : _followFocus;
      if (node.context != null) node.requestFocus();
    });
  }

  Future<void> _toggleLike(PagePostView post) async {
    final failure = await _controller.toggleLike(post.postId);
    if (failure != null && mounted) _snack(_copy.likeError(failure));
  }

  Future<void> _openServer(String serverId) async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ServerWorkspaceScreen(serverId: serverId),
      ),
    );
  }

  Future<void> _launch(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) _snack(_copy.couldNotOpenLink);
    } catch (_) {
      if (mounted) _snack(_copy.couldNotOpenLink);
    }
  }

  Future<void> _showHeldDetails() async {
    final copy = _copy;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final palette = dialogContext.appPalette;
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
          title: Text(
            copy.heldTitle,
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            copy.heldDetails,
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(copy.gotIt),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showStatement(String? reason) async {
    final copy = _copy;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final palette = dialogContext.appPalette;
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
          title: Text(
            copy.suspendedTitle,
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            '${copy.suspendedBody(reason)}\n\n${copy.statementBody}',
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(copy.gotIt),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deletePost(PagePostView post) async {
    final copy = _copy;
    final confirmed = await confirmPageAction(
      context,
      title: copy.deletePostTitle,
      body: copy.deletePostBody,
      confirm: copy.delete,
      cancel: copy.cancel,
    );
    if (!confirmed || !mounted) return;
    final failure = await _controller.managePost(
      post.postId,
      PagePostOp.delete,
    );
    if (!mounted) return;
    _snack(failure == null ? copy.postDeleted : copy.actionFailed);
  }

  Future<void> _showPostMenu(PagePostView post) async {
    final copy = _copy;
    final header = _controller.header;
    final owner = _controller.isOwner;
    final canArrange =
        owner &&
        (header?.state.running ?? false) &&
        post.state == PagePostState.published;
    final action = await showPageMenuSheet<_PostMenu>(
      context,
      sheetLabel: copy.moreOptions,
      pageId: widget.pageId,
      pageName: _name,
      kind: _kind,
      meta: _kind == null ? '' : copy.kindLabel(_kind!),
      groups: [
        [
          if (canArrange)
            post.pinned
                ? PageMenuItem(
                    value: _PostMenu.unpin,
                    icon: Icons.push_pin_outlined,
                    label: copy.unpinPost,
                  )
                : PageMenuItem(
                    value: _PostMenu.pin,
                    icon: Icons.push_pin_outlined,
                    label: copy.pinPost,
                  ),
          PageMenuItem(
            value: _PostMenu.share,
            icon: Icons.ios_share_rounded,
            label: copy.sharePost,
          ),
          if (canArrange)
            PageMenuItem(
              key: const ValueKey('page-post-comments-switch'),
              value: _PostMenu.comments,
              icon: post.commentsEnabled
                  ? Icons.comments_disabled_outlined
                  : Icons.chat_bubble_outline_rounded,
              label: post.commentsEnabled
                  ? PagePostCopy(copy.copy).turnCommentsOff
                  : PagePostCopy(copy.copy).turnCommentsOn,
            ),
        ],
        if (owner)
          [
            PageMenuItem(
              value: _PostMenu.delete,
              icon: Icons.delete_outline_rounded,
              label: copy.deletePost,
              danger: true,
            ),
          ]
        else
          [
            PageMenuItem(
              key: const ValueKey('page-post-report'),
              value: _PostMenu.report,
              icon: Icons.flag_outlined,
              label: PagePostCopy(copy.copy).reportPost,
              danger: true,
            ),
          ],
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _PostMenu.pin:
      case _PostMenu.unpin:
        final failure = await _controller.managePost(
          post.postId,
          action == _PostMenu.pin ? PagePostOp.pin : PagePostOp.unpin,
        );
        if (!mounted) return;
        _snack(
          failure != null
              ? copy.actionFailed
              : action == _PostMenu.pin
              ? copy.postPinned
              : copy.postUnpinned,
        );
      case _PostMenu.share:
        await _share(buildPageLink(post.pageId, postId: post.postId));
      case _PostMenu.delete:
        await _deletePost(post);
      case _PostMenu.comments:
        final enabled = !post.commentsEnabled;
        final postCopy = PagePostCopy(copy.copy);
        try {
          final result = await _service.setCommentsEnabled(
            post.postId,
            enabled: enabled,
          );
          PagePostEvents.instance.updated(
            post.copyWith(commentsEnabled: result.commentsEnabled),
          );
          if (mounted) {
            _snack(
              result.commentsEnabled
                  ? postCopy.commentsNowOn
                  : postCopy.commentsNowOff,
            );
          }
        } on PagesException {
          if (mounted) _snack(copy.actionFailed);
        }
      case _PostMenu.report:
        final reason = await showReportReasonSheet(
          context: context,
          title: PagePostCopy(copy.copy).reportPostTitle,
          subtitle: copy.reportSubtitle,
        );
        if (reason == null || !mounted) return;
        try {
          await _service.report(
            target: PageReportTarget.post,
            pageId: post.pageId,
            postId: post.postId,
            reason: reason.name,
          );
          if (mounted) _snack(copy.reported);
        } on PagesException {
          if (mounted) _snack(copy.reportFailed);
        }
    }
  }

  /// The owner's composer (R3). The new post lands at the top of the wall.
  Future<void> _compose(ComposeFlow flow, PagePostKind kind) async {
    final header = _controller.header;
    final post = await flow(
      context,
      owner: PageComposerOwner(
        pageId: widget.pageId,
        name: _name,
        kind: header?.kind,
        publishedToday: _controller.postedSince(_now()),
      ),
      initialKind: kind,
    );
    if (post == null || !mounted) return;
    _snack(PagePostCopy(_copy.copy).published);
    unawaited(_controller.load());
  }

  Future<void> _showPageMenu() async {
    final copy = _copy;
    final header = _controller.header;
    final owner = _controller.isOwner || _isSelf;
    final friend = !owner && _relationship == FriendRelationshipStatus.friends;
    final meta = _kind == null
        ? ''
        : friend
        ? '${copy.kindLabel(_kind!)} · ${copy.yourFriend}'
        : header == null
        ? copy.kindLabel(_kind!)
        : copy.headerMeta(header.kind, header.followerCount);
    final action = await showPageMenuSheet<_PageMenu>(
      context,
      sheetLabel: copy.moreOptions,
      pageId: widget.pageId,
      pageName: _name,
      kind: _kind,
      meta: meta,
      groups: [
        if (friend)
          [
            PageMenuItem(
              value: _PageMenu.call,
              icon: Icons.call_outlined,
              label: copy.call,
            ),
            PageMenuItem(
              value: _PageMenu.voiceMessage,
              icon: Icons.mic_none_rounded,
              label: copy.sendVoiceMessage,
            ),
            PageMenuItem(
              value: _PageMenu.invite,
              icon: Icons.group_add_outlined,
              label: copy.inviteToServer,
            ),
          ],
        [
          PageMenuItem(
            key: const ValueKey('page-menu-share'),
            value: _PageMenu.share,
            icon: Icons.ios_share_rounded,
            label: copy.sharePage,
          ),
          if (owner)
            PageMenuItem(
              value: _PageMenu.settings,
              icon: Icons.settings_outlined,
              label: copy.pageSettings,
            ),
        ],
        if (!owner)
          [
            PageMenuItem(
              key: const ValueKey('page-menu-report'),
              value: _PageMenu.report,
              icon: Icons.flag_outlined,
              label: copy.reportPage,
            ),
            if (friend)
              PageMenuItem(
                value: _PageMenu.removeFriend,
                icon: Icons.person_remove_outlined,
                label: copy.removeFriend,
                danger: true,
              ),
            PageMenuItem(
              key: const ValueKey('page-menu-block'),
              value: _PageMenu.block,
              icon: Icons.block_rounded,
              label: copy.block,
              danger: true,
            ),
          ],
      ],
    );
    if (!mounted || action == null) return;
    await _runPageMenu(action);
  }

  Future<void> _runPageMenu(_PageMenu action) async {
    final copy = _copy;
    final name = _name;
    switch (action) {
      case _PageMenu.call:
        await _actions.call(context, uid: widget.pageId, name: name);
      case _PageMenu.voiceMessage:
        await _actions.openChat(
          context,
          uid: widget.pageId,
          name: name,
          recordVoice: true,
        );
      case _PageMenu.invite:
        await _actions.inviteToServer(context, uid: widget.pageId, name: name);
      case _PageMenu.share:
        await _share(buildPageLink(widget.pageId));
      case _PageMenu.settings:
        _openSettings();
      case _PageMenu.report:
        await _report();
      case _PageMenu.removeFriend:
        final confirmed = await confirmPageAction(
          context,
          title: copy.removeFriendTitle,
          body: copy.removeFriendBody(name),
          confirm: copy.delete,
          cancel: copy.cancel,
        );
        if (!confirmed || !mounted) return;
        try {
          await _actions.removeFriend(widget.pageId);
          if (mounted) {
            setState(() => _relationship = FriendRelationshipStatus.none);
          }
        } catch (_) {
          if (mounted) _snack(copy.actionFailed);
        }
      case _PageMenu.block:
        final confirmed = await confirmPageAction(
          context,
          title: copy.blockTitle,
          body: copy.blockBody(name),
          confirm: copy.block,
          cancel: copy.cancel,
        );
        if (!confirmed || !mounted) return;
        try {
          await _actions.block(widget.pageId);
          if (mounted) Navigator.of(context).maybePop();
        } catch (_) {
          if (mounted) _snack(copy.actionFailed);
        }
    }
  }

  /// "Zgłoś stronę": a Page report (`createPageReportV1 {targetType:
  /// 'page'}`, §2.10), which carries the Page's name and kind snapshot into
  /// Page moderation (the `suspendPage` action and the tester-phase
  /// moderation script list it).
  Future<void> _report() async {
    final copy = _copy;
    final reason = await showReportReasonSheet(
      context: context,
      title: copy.reportTitle(_name),
      subtitle: copy.reportSubtitle,
    );
    if (reason == null || !mounted) return;
    try {
      await _service.report(
        target: PageReportTarget.page,
        pageId: widget.pageId,
        reason: reason.name,
      );
      if (mounted) _snack(copy.reported);
    } on PagesException catch (error) {
      if (mounted) _snack(copy.reportError(error.failure));
    }
  }

  void _openFollowingMenu(BuildContext anchor) {
    final copy = _copy;
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final rect = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset(0, box.size.height), ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    unawaited(
      showMenu<bool>(
        context: context,
        position: rect,
        items: [
          PopupMenuItem<bool>(
            key: const ValueKey('page-unfollow'),
            value: false,
            child: Row(
              children: [
                const Icon(Icons.person_remove_outlined, size: 20),
                const SizedBox(width: 12),
                Flexible(child: Text(copy.unfollow)),
              ],
            ),
          ),
        ],
      ).then((value) {
        if (value == false && mounted) unawaited(_setFollowing(false));
      }),
    );
  }

  // ---------------------------------------------------------------- build

  static _Layout _layoutFor(BuildContext context, double width) {
    if (PagesNavigatorScope.maybeOf(context)?.desktop ?? false) {
      return _Layout.desktop;
    }
    if (width >= 900) return _Layout.desktop;
    if (width >= 600) return _Layout.tablet;
    return _Layout.phone;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PagesCanvas(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final layout = _layoutFor(context, constraints.maxWidth);
              return _body(context, layout, constraints.maxWidth);
            },
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, _Layout layout, double width) {
    final copy = _copy;
    switch (_controller.status) {
      case PageProfileStatus.loading:
        return _Loading(label: copy.loadingPage, onBack: _backFor(layout));
      case PageProfileStatus.error:
        return _Framed(
          onBack: _backFor(layout),
          child: YoErrorState(
            message: copy.loadPageError,
            onRetry: () => unawaited(_controller.load()),
          ),
        );
      case PageProfileStatus.unavailable:
      case PageProfileStatus.notEnabled:
        if (_fallbackStarted) {
          return _Loading(label: copy.loadingPage, onBack: null);
        }
        // P_E7: the ban glyph 90 px under the bar and the tonal "Wróć do
        // Treści". A link always opens on Treści's own navigator (the shell
        // selects Treści and pushes the profile over the feed, even on a
        // cold start), so the action is there whenever a link shows E7.
        final canPop = Navigator.of(context).canPop();
        return _Framed(
          onBack: _backFor(layout),
          topGap: 90,
          child: PagesStateBlock(
            key: const ValueKey('page-e7'),
            icon: Icons.block_outlined,
            title: copy.e7Title,
            body: copy.e7Body,
            secondary: canPop
                ? PagesTonalButton(
                    key: const ValueKey('page-e7-back'),
                    label: copy.backToContent,
                    height: 48,
                    onPressed: _back,
                  )
                : null,
          ),
        );
      case PageProfileStatus.ready:
        return layout == _Layout.desktop
            ? _desktop(context, width)
            : _narrow(context, layout, width);
    }
  }

  VoidCallback? _backFor(_Layout layout) {
    if (layout == _Layout.desktop &&
        PagesNavigatorScope.maybeOf(context) != null) {
      return null;
    }
    return Navigator.of(context).canPop() ? _back : null;
  }

  // ---- Phone and tablet --------------------------------------------------

  Widget _narrow(BuildContext context, _Layout layout, double width) {
    final header = _controller.header!;
    final tablet = layout == _Layout.tablet;
    final padding = MediaQuery.paddingOf(context);
    final column = tablet ? PageProfileScreen.columnWidth : width;
    final side = tablet ? ((width - column) / 2).clamp(0.0, width) : 0.0;
    final gutter = tablet ? 0.0 : 16.0;
    final slivers = <Widget>[
      SliverPadding(
        padding: EdgeInsets.only(
          left: side,
          right: side,
          top: tablet ? padding.top + 36 : 0,
        ),
        sliver: SliverToBoxAdapter(
          child: _Header(
            key: const ValueKey('page-profile-header'),
            state: this,
            header: header,
            layout: layout,
            coverHeight: tablet
                ? PageProfileScreen.tabletCover
                : PageProfileScreen.phoneCover,
            discTop: tablet ? 10 : padding.top + 6,
            width: column,
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
    ];
    final pad = EdgeInsets.symmetric(horizontal: side + gutter);
    switch (_tab) {
      case 0:
        _wallSlivers(context, slivers, pad);
      case 1:
        slivers.add(
          SliverPadding(
            padding: pad,
            sliver: SliverToBoxAdapter(child: _aboutSections(context, header)),
          ),
        );
      default:
        slivers.add(
          SliverPadding(
            padding: pad,
            sliver: SliverToBoxAdapter(
              child: _photoContent(context, columns: tablet ? 4 : 3),
            ),
          ),
        );
    }
    slivers.add(
      const SliverToBoxAdapter(child: SizedBox(height: AppRhythm.page)),
    );
    return RefreshIndicator(
      onRefresh: _controller.load,
      child: CustomScrollView(
        key: const ValueKey('page-profile-scroll'),
        controller: _scroll,
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: slivers,
      ),
    );
  }

  List<ServerLocalTab> _tabsFor(PagesCopy copy, {required bool about}) => [
    ServerLocalTab(
      key: const ValueKey('page-tab-wall'),
      label: copy.tabWall,
      icon: Icons.view_agenda_outlined,
    ),
    if (about)
      ServerLocalTab(
        key: const ValueKey('page-tab-about'),
        label: copy.tabAbout,
        icon: Icons.info_outline_rounded,
      ),
    ServerLocalTab(
      key: const ValueKey('page-tab-photos'),
      label: copy.tabPhotos,
      icon: Icons.photo_library_outlined,
    ),
  ];

  void _selectTab(int index, {required bool about}) {
    setState(() => _tab = index);
    final photosIndex = about ? 2 : 1;
    if (index == photosIndex) unawaited(_controller.loadPhotos());
  }

  bool get _visitorReadOnly =>
      !_controller.isOwner &&
      _controller.header?.state == PageHeaderState.readOnly;

  Widget _postCard(BuildContext context, PagePostView post, {double? cap}) {
    final copy = _copy;
    final flows = widget.flows;
    final owner = _controller.isOwner;
    return PagePostCard(
      key: ValueKey('page-wall-post-${post.postId}'),
      post: post,
      now: _now(),
      service: _service,
      likeBusy: _controller.isLikeBusy(post.postId),
      showTypeChip: false,
      showPinnedLabel: true,
      photoMaxHeight: cap,
      commentsClosedLabel: _visitorReadOnly ? copy.visitorReadOnlyBody : null,
      onOpenPage: () {
        if (!_scroll.hasClients) return;
        // Reduce Motion: straight to the top, no 280 ms glide.
        if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
          _scroll.jumpTo(0);
          return;
        }
        unawaited(
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          ),
        );
      },
      onToggleLike: () => unawaited(_toggleLike(post)),
      onShare: () =>
          unawaited(_share(buildPageLink(post.pageId, postId: post.postId))),
      onMore: () => unawaited(_showPostMenu(post)),
      onComment: flows.openPost == null
          ? null
          : () => unawaited(
              flows.openPost!(
                context,
                pageId: post.pageId,
                postId: post.postId,
                initial: post,
                focusComposer: true,
                pageReadOnly: _visitorReadOnly,
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
                pageReadOnly: _visitorReadOnly,
              ),
            ),
      onOpenLikers: flows.openLikers == null
          ? null
          : () => unawaited(flows.openLikers!(context, post)),
      onPlayVoice: flows.playVoice == null
          ? null
          : () => unawaited(flows.playVoice!(context, post)),
      onDeleteHeld: owner ? () => unawaited(_deletePost(post)) : null,
      onHeldDetails: owner ? () => unawaited(_showHeldDetails()) : null,
    );
  }

  void _wallSlivers(
    BuildContext context,
    List<Widget> slivers,
    EdgeInsets pad, {
    double? cap,
  }) {
    final copy = _copy;
    final posts = _controller.wallPosts;
    if (posts.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 32),
            child: PagesStateBlock(
              key: const ValueKey('page-wall-empty'),
              icon: Icons.article_outlined,
              title: copy.noPostsYet,
              body: _controller.isOwner
                  ? copy.ownerNoPostsBody
                  : copy.noPostsBody,
            ),
          ),
        ),
      );
      return;
    }
    for (var i = 0; i < posts.length; i++) {
      if (i > 0) {
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 12)));
      }
      slivers.add(
        SliverPadding(
          padding: pad,
          sliver: SliverToBoxAdapter(
            child: _postCard(context, posts[i], cap: cap),
          ),
        ),
      );
    }
    final wall = _controller.wall;
    final showMore = wall.hasMore || wall.loadingMore || wall.loadMoreFailed;
    slivers.add(
      SliverPadding(
        // Stable while pages arrive above it, so its announcement survives.
        key: const ValueKey('page-wall-load-more-slot'),
        padding: pad.copyWith(top: showMore ? AppRhythm.section : 0),
        sliver: SliverToBoxAdapter(
          child: Center(
            child: PagesLoadMoreButton(
              key: const ValueKey('page-wall-load-more'),
              visible: showMore,
              loading: wall.loadingMore,
              failed: wall.loadMoreFailed,
              itemCount: posts.length,
              onPressed: () => unawaited(_controller.loadMoreWall()),
            ),
          ),
        ),
      ),
    );
  }

  /// The Zdjęcia tab's body: loading, error, empty, or the grid with
  /// "Wczytaj więcej".
  Widget _photoContent(BuildContext context, {required int columns}) {
    final copy = _copy;
    final photos = _controller.photos;
    if (!photos.loaded) {
      return Padding(
        padding: const EdgeInsets.only(top: 32),
        child: photos.failed
            ? YoErrorState(
                message: copy.loadPageError,
                onRetry: () => unawaited(_controller.loadPhotos()),
              )
            : Center(
                child: YoLoadingIndicator(semanticLabel: copy.loadingPage),
              ),
      );
    }
    if (photos.posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 32),
        child: PagesStateBlock(
          key: const ValueKey('page-photos-empty'),
          icon: Icons.photo_library_outlined,
          title: copy.noPhotosYet,
        ),
      );
    }
    final flows = widget.flows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PagePhotoGridView(
          key: const ValueKey('page-photos-grid'),
          posts: photos.posts,
          service: _service,
          pageName: _name,
          columns: columns,
          onOpen: flows.openPost == null
              ? null
              : (post) => unawaited(
                  flows.openPost!(
                    context,
                    pageId: post.pageId,
                    postId: post.postId,
                    initial: post,
                  ),
                ),
        ),
        Padding(
          padding: EdgeInsets.only(
            top: photos.hasMore || photos.loadingMore || photos.loadMoreFailed
                ? AppRhythm.section
                : 0,
          ),
          child: Center(
            child: PagesLoadMoreButton(
              visible:
                  photos.hasMore || photos.loadingMore || photos.loadMoreFailed,
              loading: photos.loadingMore,
              failed: photos.loadMoreFailed,
              itemCount: photos.posts.length,
              onPressed: () => unawaited(_controller.loadPhotos(more: true)),
            ),
          ),
        ),
      ],
    );
  }

  // ---- Informacje (R9) ---------------------------------------------------

  Widget _aboutSections(BuildContext context, PageHeader header) {
    final copy = _copy;
    final palette = context.appPalette;
    final business = header.business;
    final community = header.community;
    final description = header.description.trim();
    final since = header.onYoVoiceSinceMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            header.onYoVoiceSinceMs!,
            isUtc: true,
          );
    final sinceRow = since == null
        ? null
        : PageInfoRow(
            icon: Icons.event_available_outlined,
            label: copy.onYoVoice,
            value: copy.onYoVoiceSince(since),
          );
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      fontSize: 14.5,
      height: 1.5,
      color: palette.textPrimary,
    );
    final children = <Widget>[];
    if (header.kind == PageKind.business) {
      if (description.isNotEmpty) {
        children.add(
          PageSectionCard(
            title: copy.aboutBusiness,
            children: [
              Text(description, style: bodyStyle),
              const SizedBox(height: 6),
            ],
          ),
        );
        children.add(const SizedBox(height: 12));
      }
      children.add(
        PageSectionCard(
          key: const ValueKey('page-about-contact'),
          title: copy.contactAndHours,
          children: _contactRows(header, business, sinceRow),
        ),
      );
      final legal = business?.legalNotice;
      if (legal != null) {
        children.add(const SizedBox(height: 12));
        children.add(
          PageSectionCard(
            title: copy.legalNotice,
            children: [
              Text(
                legal,
                style: bodyStyle.copyWith(
                  fontSize: 14,
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      }
      children.add(
        PageFootnote(
          copy.notVerifiedLine,
          icon: Icons.shield_outlined,
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
        ),
      );
    } else {
      children.add(
        PageSectionCard(
          title: copy.aboutCommunity,
          children: [
            if (description.isNotEmpty) ...[
              Text(description, style: bodyStyle),
              const SizedBox(height: 10),
            ],
            PageInfoRow(
              icon: Icons.interests_outlined,
              label: copy.categoryField(header.kind),
              value: copy.categoryLabel(header.category),
            ),
            ?sinceRow,
          ],
        ),
      );
      final rules = [
        for (final line in (community?.rules ?? '').split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];
      if (rules.isNotEmpty) {
        children.add(const SizedBox(height: 12));
        children.add(
          PageSectionCard(
            key: const ValueKey('page-about-rules'),
            title: copy.rulesTitle,
            children: [
              for (var i = 0; i < rules.length; i++)
                _RuleRow(number: i + 1, text: rules[i]),
            ],
          ),
        );
      }
      final server = community?.linkedServer;
      if (server != null) {
        children.add(const SizedBox(height: 12));
        children.add(
          _LinkedServerCard(
            server: server,
            onOpen: () => unawaited(_openServer(server.serverId)),
          ),
        );
      }
      children.add(
        PageFootnote(
          copy.ownerOnlyPosts,
          icon: Icons.campaign_outlined,
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
        ),
      );
    }
    if (!_controller.isOwner) {
      children.add(
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 22, top: 2),
            child: TextButton.icon(
              key: const ValueKey('page-about-report'),
              onPressed: () => unawaited(_report()),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: palette.textSecondary,
                textStyle: AppTypography.labelLarge.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: Text(copy.reportPage),
            ),
          ),
        ),
      );
    }
    return Column(
      key: const ValueKey('page-about'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  List<Widget> _contactRows(
    PageHeader header,
    PageBusinessInfo? business,
    Widget? sinceRow,
  ) {
    final copy = _copy;
    final palette = context.appPalette;
    final website = business?.website;
    final websiteUri = website == null ? null : Uri.tryParse(website);
    return [
      PageInfoRow(
        icon: Icons.storefront_outlined,
        label: copy.categoryField(header.kind),
        value: copy.categoryLabel(header.category),
      ),
      if (business?.address != null)
        PageInfoRow(
          icon: Icons.place_outlined,
          label: copy.addressLabel,
          value: business!.address!,
        ),
      if (business?.hours != null)
        PageInfoRow(
          icon: Icons.schedule_rounded,
          label: copy.hoursLabel,
          value: business!.hours!,
        ),
      if (business?.phone != null)
        PageInfoRow(
          icon: Icons.call_outlined,
          label: copy.phoneLabel,
          value: business!.phone!,
          onTap: () =>
              unawaited(_launch(Uri(scheme: 'tel', path: business.phone))),
        ),
      if (business?.email != null)
        PageInfoRow(
          icon: Icons.mail_outline_rounded,
          label: copy.emailLabel,
          value: business!.email!,
          onTap: () =>
              unawaited(_launch(Uri(scheme: 'mailto', path: business.email))),
        ),
      if (websiteUri != null && websiteUri.scheme == 'https')
        PageInfoRow(
          icon: Icons.language_rounded,
          label: copy.websiteLabel,
          value: _displayUrl(websiteUri),
          onTap: () => unawaited(_launch(websiteUri)),
          trailing: Icon(
            Icons.open_in_new_rounded,
            size: 18,
            color: palette.textTertiary,
          ),
        ),
      ?sinceRow,
    ];
  }

  static String _displayUrl(Uri uri) {
    final path = uri.path == '/' ? '' : uri.path;
    return '${uri.host}$path';
  }

  // ---- Desktop -----------------------------------------------------------

  Widget _desktop(BuildContext context, double width) {
    final header = _controller.header!;
    final inScope = PagesNavigatorScope.maybeOf(context) != null;
    final slivers = <Widget>[];
    final column = width.clamp(0.0, PageProfileScreen.desktopMaxWidth + 48);
    final side = ((width - column) / 2).clamp(0.0, width);
    final pad = EdgeInsets.only(
      left: side + (inScope ? 0 : 24),
      right: side + 24,
    );
    if (!inScope && Navigator.of(context).canPop()) {
      slivers.add(
        SliverPadding(
          padding: pad.copyWith(top: 12),
          sliver: SliverToBoxAdapter(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _back,
                icon: const Icon(Icons.chevron_left_rounded),
                label: Text(_copy.goBack),
              ),
            ),
          ),
        ),
      );
    }
    slivers.add(
      SliverPadding(
        padding: pad.copyWith(top: 16),
        sliver: SliverToBoxAdapter(
          child: _DesktopHeader(
            key: const ValueKey('page-profile-header'),
            state: this,
            header: header,
          ),
        ),
      ),
    );
    final main = <Widget>[];
    final photosTab = _tab == 1;
    if (photosTab) {
      main.add(_photoContent(context, columns: 4));
    } else {
      final posts = _controller.wallPosts;
      if (posts.isEmpty) {
        main.add(
          PagesStateBlock(
            key: const ValueKey('page-wall-empty'),
            icon: Icons.article_outlined,
            title: _copy.noPostsYet,
            body: _controller.isOwner
                ? _copy.ownerNoPostsBody
                : _copy.noPostsBody,
          ),
        );
      }
      for (var i = 0; i < posts.length; i++) {
        if (i > 0) main.add(const SizedBox(height: 16));
        main.add(_postCard(context, posts[i], cap: 420));
      }
      final wall = _controller.wall;
      if (wall.hasMore || wall.loadingMore || wall.loadMoreFailed) {
        main.add(const SizedBox(height: AppRhythm.section));
        main.add(
          Center(
            child: wall.loadingMore
                ? YoLoadingIndicator(semanticLabel: _copy.loadingPosts)
                : PagesTonalButton(
                    key: const ValueKey('page-wall-load-more'),
                    label: wall.loadMoreFailed
                        ? _copy.tryAgain
                        : _copy.loadMore,
                    height: 48,
                    onPressed: () => unawaited(_controller.loadMoreWall()),
                  ),
          ),
        );
      }
    }
    slivers.add(
      SliverPadding(
        padding: pad.copyWith(top: 24, bottom: AppRhythm.page),
        sliver: SliverToBoxAdapter(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: main,
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: PageProfileScreen.aboutColumnWidth,
                child: _aboutColumn(context, header),
              ),
            ],
          ),
        ),
      ),
    );
    return CustomScrollView(
      key: const ValueKey('page-profile-scroll'),
      controller: _scroll,
      primary: false,
      slivers: slivers,
    );
  }

  Widget _aboutColumn(BuildContext context, PageHeader header) {
    final copy = _copy;
    final palette = context.appPalette;
    final since = header.onYoVoiceSinceMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            header.onYoVoiceSinceMs!,
            isUtc: true,
          );
    final sinceRow = since == null
        ? null
        : PageInfoRow(
            icon: Icons.event_available_outlined,
            label: copy.onYoVoice,
            value: copy.onYoVoiceSince(since),
          );
    final business = header.business;
    final community = header.community;
    final rules = [
      for (final line in (community?.rules ?? '').split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    final photos = _controller.photos;
    if (!photos.loaded && !photos.loading && !photos.failed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_controller.loadPhotos());
      });
    }
    return Column(
      key: const ValueKey('page-about-column'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageSectionCard(
          title: copy.aboutTitle,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          children: header.kind == PageKind.business
              ? _contactRows(header, business, sinceRow)
              : [
                  PageInfoRow(
                    icon: Icons.interests_outlined,
                    label: copy.categoryField(header.kind),
                    value: copy.categoryLabel(header.category),
                  ),
                  ?sinceRow,
                ],
        ),
        if (business?.legalNotice != null) ...[
          const SizedBox(height: 12),
          PageSectionCard(
            title: copy.legalNotice,
            children: [
              Text(
                business!.legalNotice!,
                style: AppTypography.bodySmall.copyWith(
                  color: palette.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ],
        if (rules.isNotEmpty) ...[
          const SizedBox(height: 12),
          PageSectionCard(
            title: copy.rulesTitle,
            children: [
              for (var i = 0; i < rules.length; i++)
                _RuleRow(number: i + 1, text: rules[i]),
            ],
          ),
        ],
        if (community?.linkedServer != null) ...[
          const SizedBox(height: 12),
          _LinkedServerCard(
            server: community!.linkedServer!,
            onOpen: () =>
                unawaited(_openServer(community.linkedServer!.serverId)),
          ),
        ],
        if (photos.posts.isNotEmpty) ...[
          const SizedBox(height: 12),
          PageSectionCard(
            key: const ValueKey('page-about-photos'),
            title: copy.photosTitle,
            padding: const EdgeInsets.all(16),
            children: [
              PagePhotoGridView(
                posts: photos.posts,
                service: _service,
                pageName: _name,
                limit: 6,
              ),
            ],
          ),
        ],
        PageFootnote(
          header.kind == PageKind.business
              ? copy.notVerifiedLine
              : copy.ownerOnlyPosts,
          icon: header.kind == PageKind.business
              ? Icons.shield_outlined
              : Icons.campaign_outlined,
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
        ),
        if (!_controller.isOwner)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('page-about-report'),
              onPressed: () => unawaited(_report()),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                foregroundColor: palette.textSecondary,
              ),
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: Text(copy.reportPage),
            ),
          ),
      ],
    );
  }

  // ---- Notices and actions -------------------------------------------------

  /// The owner's state notice (R12), above the actions.
  Widget? _ownerNotice(PageHeader header) {
    if (!_controller.isOwner) return null;
    final copy = _copy;
    switch (header.state) {
      case PageHeaderState.active:
        return null;
      case PageHeaderState.suspended:
        final reason = _ownPage?.suspensionReason;
        return PageNotice(
          key: const ValueKey('page-notice-suspended'),
          tone: PageTone.danger,
          icon: Icons.gavel_rounded,
          title: copy.suspendedTitle,
          body: copy.suspendedBody(reason),
          actions: [
            TextButton.icon(
              onPressed: () => unawaited(_showStatement(reason)),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                foregroundColor: context.appPalette.interactiveForeground,
                textStyle: AppTypography.labelLarge.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: Text(copy.seeStatement),
            ),
          ],
        );
      case PageHeaderState.hidden:
        return PageNotice(
          key: const ValueKey('page-notice-hidden'),
          tone: PageTone.neutral,
          icon: Icons.visibility_off_outlined,
          title: copy.hiddenTitle,
          body: copy.hiddenBody,
        );
      case PageHeaderState.paused:
        return PageNotice(
          key: const ValueKey('page-notice-paused'),
          tone: PageTone.info,
          icon: Icons.pause_circle_outline_rounded,
          title: copy.pausedTitle,
          body: copy.pausedBody,
        );
      case PageHeaderState.readOnly:
        final lapsedAt = _ownPage?.lapsedAt;
        int? since;
        int? left;
        if (lapsedAt != null) {
          since = _now().difference(lapsedAt).inDays.clamp(0, 30);
          left = (30 - since).clamp(0, 30);
        }
        return PageNotice(
          key: const ValueKey('page-notice-read-only'),
          tone: PageTone.warning,
          icon: Icons.hourglass_bottom_rounded,
          title: copy.readOnlyTitle,
          body: copy.readOnlyBody(daysSince: since, daysLeft: left),
        );
    }
  }

  /// The visitor's read-only notice (R12, D14), below the actions.
  Widget? _visitorNotice() {
    if (!_visitorReadOnly) return null;
    final copy = _copy;
    return PageNotice(
      key: const ValueKey('page-notice-visitor-read-only'),
      tone: PageTone.neutral,
      icon: Icons.pause_circle_outline_rounded,
      title: copy.visitorReadOnlyTitle,
      body: copy.visitorReadOnlyBody,
    );
  }

  /// The action row per viewer (profile B, R8, R12, R15). [stacked] puts
  /// the primary action on its own full-width row.
  Widget _actionRow(
    BuildContext context, {
    required PageHeader header,
    required bool stacked,
    required bool expand,
  }) {
    final copy = _copy;
    final viewer = _controller.viewer!;
    final dots = PageDotsButton(
      key: const ValueKey('page-more'),
      onPressed: () => unawaited(_showPageMenu()),
      tooltip: copy.moreOptions,
    );
    Widget? primary;
    Widget? secondary;
    String? secondaryLabel;
    var primaryLabel = '';
    if (viewer.isOwner) {
      switch (header.state) {
        case PageHeaderState.active:
          final compose = widget.flows.openComposer;
          primary = Tooltip(
            message: compose == null
                ? '${copy.newPost} · ${copy.comingSoon}'
                : copy.newPost,
            excludeFromSemantics: compose != null,
            child: YoGradientFilledButton(
              key: const ValueKey('page-new-post'),
              onPressed: compose == null
                  ? null
                  : () => unawaited(_compose(compose, PagePostKind.text)),
              minimumSize: const Size(132, 44),
              icon: const Icon(Icons.add_rounded, size: 20),
              child: Text(copy.newPost, maxLines: 1),
            ),
          );
          primaryLabel = copy.newPost;
          secondaryLabel = copy.editPage;
          secondary = PageTonalButton(
            key: const ValueKey('page-edit'),
            label: copy.editPage,
            icon: Icons.edit_outlined,
            onPressed: _openEdit,
          );
        case PageHeaderState.paused:
          primaryLabel = copy.resumePage;
          primary = YoGradientFilledButton(
            key: const ValueKey('page-resume'),
            onPressed: () => unawaited(_resume()),
            minimumSize: const Size(132, 44),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            child: Text(copy.resumePage, maxLines: 1),
          );
          secondary = PageDotsButton(
            key: const ValueKey('page-settings-button'),
            onPressed: _openSettings,
            tooltip: copy.pageSettings,
            icon: Icons.settings_outlined,
          );
        case PageHeaderState.readOnly:
        case PageHeaderState.hidden:
        case PageHeaderState.suspended:
          return Row(
            children: [
              Expanded(
                child: PageTonalButton(
                  key: const ValueKey('page-settings-button'),
                  label: copy.pageSettings,
                  icon: Icons.settings_outlined,
                  expand: true,
                  onPressed: _openSettings,
                ),
              ),
              const SizedBox(width: 8),
              dots,
            ],
          );
      }
    } else {
      if (viewer.following) {
        primaryLabel = copy.following;
        primary = Builder(
          builder: (anchor) => PageTonalButton(
            key: const ValueKey('page-following'),
            label: copy.following,
            focusNode: _followingFocus,
            // Busy stays enabled (and focused); the press is ignored.
            onPressed: _controller.followBusy
                ? () {}
                : () => _openFollowingMenu(anchor),
            trailing: Icon(
              Icons.arrow_drop_down_rounded,
              size: 22,
              color: context.appPalette.interactiveForeground,
            ),
          ),
        );
      } else if (viewer.canFollow) {
        primaryLabel = copy.follow;
        primary = YoGradientFilledButton(
          key: const ValueKey('page-follow'),
          focusNode: _followFocus,
          onPressed: () => unawaited(_setFollowing(true)),
          busy: _controller.followBusy,
          minimumSize: const Size(132, 44),
          icon: const Icon(Icons.add_rounded, size: 20),
          child: Text(copy.follow, maxLines: 1),
        );
      }
      if (viewer.canMessage) {
        secondaryLabel = copy.message;
        secondary = PageTonalButton(
          key: const ValueKey('page-message'),
          label: copy.message,
          icon: Icons.chat_bubble_outline_rounded,
          onPressed: () => unawaited(
            _actions.openChat(context, uid: widget.pageId, name: _name),
          ),
        );
      }
    }
    if (primary == null) {
      return Row(
        children: [
          if (secondary != null) ...[
            Expanded(child: secondary),
            const SizedBox(width: 8),
          ] else
            const Spacer(),
          dots,
        ],
      );
    }
    final row = primary;
    final side = secondary;
    return LayoutBuilder(
      builder: (context, constraints) {
        // R15: stack when the one row cannot hold the primary at its
        // natural width beside the secondary (narrow widths, large text,
        // long translations), not only at the fixed thresholds.
        final secondaryWidth = side == null
            ? 0.0
            : secondaryLabel == null
            ? 44.0
            : _buttonWidth(context, secondaryLabel, padding: 32) + 8;
        final primaryWidth = math.max(
          132.0,
          _buttonWidth(context, primaryLabel, padding: 40),
        );
        final fits =
            constraints.maxWidth.isFinite &&
            constraints.maxWidth - 8 - 44 - secondaryWidth >= primaryWidth;
        return _actionLayout(
          primary: row,
          secondary: side,
          dots: dots,
          stacked: stacked || (expand && !fits),
          expand: expand,
        );
      },
    );
  }

  /// A tonal / gradient button's natural width for [label]: the label under
  /// the reader's text scale, the 18-20 px icon and its 8 px gap, and the
  /// horizontal [padding] (tonal 2 × 16, gradient 2 × 20).
  static double _buttonWidth(
    BuildContext context,
    String label, {
    required double padding,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w700),
      ),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width + 20 + 8 + padding;
  }

  Widget _actionLayout({
    required Widget primary,
    required Widget? secondary,
    required Widget dots,
    required bool stacked,
    required bool expand,
  }) {
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: double.infinity, child: primary),
          const SizedBox(height: 8),
          Row(
            children: [
              if (secondary != null) ...[
                Expanded(child: secondary),
                const SizedBox(width: 8),
              ] else
                const Spacer(),
              dots,
            ],
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (expand)
          Expanded(child: primary)
        else
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 176),
            child: primary,
          ),
        if (secondary != null) ...[const SizedBox(width: 8), secondary],
        const SizedBox(width: 8),
        dots,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header B (phone, tablet)
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.header,
    required this.layout,
    required this.coverHeight,
    required this.discTop,
    required this.width,
    super.key,
  });

  final _PageProfileScreenState state;
  final PageHeader header;
  final _Layout layout;
  final double coverHeight;
  final double discTop;
  final double width;

  static const double ring = 3;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final tablet = layout == _Layout.tablet;
    const face = PageProfileScreen.face;
    final back = state._backFor(layout);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final stacked = width < 360 || scale >= 1.3;
    Widget cover = PageCover(pageId: header.pageId);
    if (tablet) cover = ClipRRect(borderRadius: AppRadius.block, child: cover);
    final ownerNotice = state._ownerNotice(header);
    final visitorNotice = state._visitorNotice();
    final description = header.description.trim();
    Widget tabs = ServerLocalTabs(
      key: const ValueKey('page-tabs'),
      scrollWhenTight: true,
      tabs: state._tabsFor(copy, about: true),
      selectedIndex: state._tab,
      onSelected: (index) => state._selectTab(index, about: true),
    );
    if (tablet) {
      tabs = Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 393),
          child: tabs,
        ),
      );
    }
    final side = tablet ? 0.0 : 16.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: coverHeight + face / 2 + ring,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: coverHeight,
                child: cover,
              ),
              if (back != null)
                PositionedDirectional(
                  start: 12,
                  top: discTop,
                  child: PageGlassButton(
                    key: const ValueKey('page-back'),
                    icon: Directionality.of(context) == TextDirection.rtl
                        ? Icons.chevron_right_rounded
                        : Icons.chevron_left_rounded,
                    tooltip: PageProfileCopy(copy).goBack,
                    onPressed: back,
                  ),
                ),
              PositionedDirectional(
                end: 12,
                top: discTop,
                child: PageGlassButton(
                  key: const ValueKey('page-cover-more'),
                  icon: Icons.more_horiz_rounded,
                  tooltip: copy.moreOptions,
                  onPressed: () => unawaited(state._showPageMenu()),
                ),
              ),
              PositionedDirectional(
                start: 13,
                top: coverHeight - face / 2 - ring,
                child: PageFace(
                  pageId: header.pageId,
                  name: header.displayName,
                  kind: header.kind,
                  size: face,
                  ring: ring,
                  ringColor: palette.background,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: side),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: NameWithVipMark(
                  key: const ValueKey('page-name'),
                  uid: header.pageId,
                  name: header.displayName,
                  maxLines: 3,
                  explainOnTap: true,
                  // The rosette's 44 px target shares these gaps, so the
                  // name sits where profile B has it (deviation sheet §13).
                  headerRoom: const EdgeInsets.only(top: 12, bottom: 4),
                  style: AppTypography.screenTitle.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Text(
                PageProfileCopy(
                  copy,
                ).headerMeta(header.kind, header.followerCount),
                key: const ValueKey('page-meta'),
                maxLines: 2,
                style: AppTypography.bodySmall.copyWith(
                  fontSize: 13,
                  color: palette.textSecondary,
                ),
              ),
              if (description.isNotEmpty) ...[
                // The target still reaches ~2 px past the name; the description
                // keeps profile B's position.
                const SizedBox(height: 8),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(
                    fontSize: 14,
                    height: 1.5,
                    color: palette.textPrimary,
                  ),
                ),
              ],
              if (ownerNotice != null) ...[
                const SizedBox(height: 14),
                ownerNotice,
              ],
              const SizedBox(height: 16),
              state._actionRow(
                context,
                header: header,
                stacked: stacked,
                expand: !tablet,
              ),
              if (visitorNotice != null) ...[
                const SizedBox(height: 12),
                visitorNotice,
              ],
              const SizedBox(height: 16),
              tabs,
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop header card
// ---------------------------------------------------------------------------

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({required this.state, required this.header, super.key});

  final _PageProfileScreenState state;
  final PageHeader header;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    const cover = PageProfileScreen.desktopCover;
    const face = PageProfileScreen.desktopFace;
    final ownerNotice = state._ownerNotice(header);
    final visitorNotice = state._visitorNotice();
    final description = header.description.trim();
    final meta =
        '${copy.kindLabel(header.kind)} · ${PageProfileCopy(copy).categoryLabel(header.category)} · ${copy.followers(header.followerCount)}';
    return YoCard(
      padding: EdgeInsets.zero,
      semanticButton: false,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: cover,
                child: Stack(
                  fit: StackFit.expand,
                  children: [PageCover(pageId: header.pageId, scrim: false)],
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(136, 14, 24, 0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final identity = Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: NameWithVipMark(
                            key: const ValueKey('page-name'),
                            uid: header.pageId,
                            name: header.displayName,
                            maxLines: 2,
                            explainOnTap: true,
                            headerRoom: const EdgeInsets.only(bottom: 4),
                            style: AppTypography.headlineLarge.copyWith(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.5,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          meta,
                          key: const ValueKey('page-meta'),
                          style: AppTypography.bodySmall.copyWith(
                            fontSize: 13,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    );
                    final actions = state._actionRow(
                      context,
                      header: header,
                      stacked: false,
                      expand: false,
                    );
                    // The approved desktop header puts the actions beside
                    // the name; a narrow main column puts them under it.
                    if (constraints.maxWidth < 640) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          identity,
                          const SizedBox(height: 12),
                          actions,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: identity),
                        const SizedBox(width: 16),
                        actions,
                      ],
                    );
                  },
                ),
              ),
              if (description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                  child: Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMedium.copyWith(
                      fontSize: 14,
                      height: 1.5,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              if (ownerNotice != null || visitorNotice != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: ownerNotice ?? visitorNotice,
                ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: palette.hairline)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
                alignment: AlignmentDirectional.centerStart,
                child: SizedBox(
                  width: 300,
                  child: ServerLocalTabs(
                    key: const ValueKey('page-tabs'),
                    tabs: state._tabsFor(copy, about: false),
                    selectedIndex: state._tab.clamp(0, 1),
                    onSelected: (index) =>
                        state._selectTab(index, about: false),
                  ),
                ),
              ),
            ],
          ),
          PositionedDirectional(
            start: 20,
            top: cover - face / 2 - 4,
            child: PageFace(
              pageId: header.pageId,
              name: header.displayName,
              kind: header.kind,
              size: face,
              ring: 4,
              ringColor: palette.blockTop,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small pieces
// ---------------------------------------------------------------------------

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.interactiveForeground.withValues(alpha: .16),
                borderRadius: AppRadius.sm,
              ),
              child: Text(
                '$number',
                style: TextStyle(
                  color: palette.interactiveForeground,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              semanticsLabel: '$number. $text',
              style: AppTypography.bodyMedium.copyWith(
                fontSize: 14.5,
                height: 1.45,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkedServerCard extends StatelessWidget {
  const _LinkedServerCard({required this.server, required this.onOpen});

  final PageLinkedServer server;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final name = server.name ?? copy.communityServer;
    final type = ServerType.parse(server.serverType);
    return YoCard(
      key: const ValueKey('page-about-server'),
      onTap: onOpen,
      semanticButton: false,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            copy.communityServer,
            style: AppTypography.sectionTitle.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ExcludeSemantics(
                child: YoServerTile(
                  initial: PageFace.initialFor(name),
                  type: type,
                  size: 48,
                  bordered: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.rowTitle.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      copy.publicServer,
                      style: AppTypography.bodySmall.copyWith(
                        color: palette.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              PageTonalButton(label: copy.open, height: 40, onPressed: onOpen),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            copy.serverNote,
            style: AppTypography.bodySmall.copyWith(
              color: palette.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading: the cover's footprint and a spinner, with Back when there is
/// somewhere to go.
class _Loading extends StatelessWidget {
  const _Loading({required this.label, required this.onBack});

  final String label;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return _Framed(
      onBack: onBack,
      child: Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Center(child: YoLoadingIndicator(semanticLabel: label)),
      ),
    );
  }
}

/// A non-ready state with the Back control in the header's place.
class _Framed extends StatelessWidget {
  const _Framed({required this.onBack, required this.child, this.topGap = 0});

  final VoidCallback? onBack;
  final Widget child;

  /// Space between the Back row and [child] (E7: 90, as on P_E7).
  final double topGap;

  @override
  Widget build(BuildContext context) {
    final copy = PagesCopy(AppLocalizations.of(context));
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 32),
        children: [
          if (onBack != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: IconButton(
                key: const ValueKey('page-back'),
                onPressed: onBack,
                tooltip: PageProfileCopy(copy).goBack,
                style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: const BackButtonIcon(),
              ),
            )
          else
            const SizedBox(height: 48),
          if (topGap > 0) SizedBox(height: topGap),
          child,
        ],
      ),
    );
  }
}
