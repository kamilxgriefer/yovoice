import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/inputs/yo_search_field.dart';
import 'package:yovoice/shared/widgets/layout/home_section_header.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_member_role.dart';
import '../../data/services/server_directory_liveness.dart';
import '../../data/services/server_media_connector.dart';
import '../../data/services/server_question_attention.dart';
import '../../data/services/server_service.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import '../servers_board_copy.dart';
import '../widgets/server_delete_flow.dart';
import '../widgets/servers_board.dart';
import 'create_server_screen.dart';
import 'server_workspace_screen.dart';

/// The Servers tab: one scrolling board (owner's choice 2026-10-03, option A
/// of sheet `2_hub`; ADR-239).
///
/// From the top: the title row (`Serwery`, a name filter and the "+" that
/// opens `Stwórz serwer` / `Dołącz z linku`), the account's own servers as a
/// compact list with a LIVE lamp where a conversation is live, then the
/// public servers a person can look at and join. The public list and the
/// lamp are part of Servers; they are not the retired Discover surface.
///
/// The board's first section, "Na żywo", belongs to the LIVE wave: it needs
/// a `liveStreams` projection that does not exist yet, so nothing is drawn
/// for it — no heading, no placeholder. [liveSectionBuilder] is where that
/// wave mounts it.
class ServersScreen extends StatefulWidget {
  const ServersScreen({
    this.repository,
    this.isRootTab = false,
    this.onOpenServer,
    this.onCreateServer,
    this.chatService,
    this.connector,
    this.isVisible,
    this.liveSectionBuilder,
    super.key,
  });
  final ServerRepository? repository;
  final bool isRootTab;
  final ValueChanged<Server>? onOpenServer;
  final VoidCallback? onCreateServer;

  /// The board's "Na żywo" section, mounted between the title row and
  /// "Twoje serwery". Null — every production caller today — draws nothing
  /// there. The builder brings its own heading, so an absent section leaves
  /// no title behind.
  final WidgetBuilder? liveSectionBuilder;

  /// From this content width the title row carries the name filter inline
  /// (the desktop slot); below it the filter opens from the search button.
  static const double inlineSearchWidth = 760;
  static const double inlineSearchFieldWidth = 300;

  /// Whether the shell's content slot that hosts this screen is the one on
  /// screen.
  ///
  /// The desktop shell keeps its built slots alive inside an `IndexedStack`,
  /// so a hidden Servers slot stays mounted with every listener — and, once
  /// someone has joined, with an open microphone behind no visible dock. The
  /// Moments slot solves the same problem with the same shape
  /// (`MomentsScreen(isVisible:)`); this is the Servers end of that contract,
  /// and the workspace leaves its conversation when the slot goes away.
  /// Null (a pushed route, a test, a phone) means always visible.
  final ValueListenable<bool>? isVisible;

  /// Test seams handed to the workspace this screen hosts or pushes.
  final ClubChatService? chatService;
  final ServerMediaConnector? connector;

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  late final ServerRepository _repository;
  late Stream<List<Server>> _servers;

  /// The server hosted INLINE over the directory. From
  /// [ServerWorkspaceScreen.tabletBreakpoint] up, opening a server replaces
  /// the directory inside this same slot, so the shell's rail and dock never
  /// move; a server opened on a phone-width surface is a pushed route with a
  /// real app bar instead. Once hosted it stays hosted at every width — see
  /// the comment in [build].
  String? _inlineServerId;

  /// The channel a pasted link asked for, handed to the inline workspace.
  String? _inlineChannelId;
  double _width = 0;

  /// "Serwery publiczne": the one listing Rules allow. Null when the
  /// repository cannot list (a narrow test double), which leaves the board
  /// without that section.
  Stream<List<Server>>? _public;

  /// Which of the account's servers are live, for the rows' lamps.
  late final ServerDirectoryLiveness _liveness;

  /// "Pokaż wszystkie" was pressed.
  bool _showAll = false;

  /// The name filter: its text, and whether the phone's title row currently
  /// shows the field instead of the title.
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'ServersBoardSearch');

  /// The search button's own node: closing the field hands focus back to the
  /// control that opened it. A focused field that leaves the tree drops
  /// focus to the route, and the next Tab would restart from the top
  /// (WCAG 2.4.3 — the same reason `YoSearchField` keeps focus on a clear).
  final _searchButtonFocus = FocusNode(debugLabel: 'ServersBoardSearchButton');
  bool _searchOpen = false;
  String _query = '';

  /// Rows this directory just deleted or left. They are hidden at once, so
  /// the list never shows a server the person has just removed while the
  /// root's closing read (or the mirror sweep) is still on its way.
  final _removedIds = <String>{};

  /// Rows with a delete or leave in flight: their action button shows
  /// progress and a second tap cannot start a second call.
  final _busyIds = <String>{};

  /// Listener questions this host has not seen, per podcast server. One set of
  /// listeners for the directory's tiles and every workspace opened from here
  /// (inline or pushed), paused while the shell hides this slot.
  late final ServerQuestionAttention _attention;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? ServerService();
    _servers = _repository.watchMyServers();
    _public = _watchPublic();
    _attention = ServerQuestionAttention(
      repository: _repository,
      isVisible: widget.isVisible,
    )..addListener(_onAttention);
    _liveness = ServerDirectoryLiveness(
      repository: _repository,
      isVisible: widget.isVisible,
    )..addListener(_onAttention);
  }

  Stream<List<Server>>? _watchPublic() {
    final repository = _repository;
    if (repository is! ServerPublicDirectoryRepository) return null;
    try {
      return (repository as ServerPublicDirectoryRepository)
          .watchPublicServers();
    } on Object {
      return null;
    }
  }

  void _onAttention() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _attention
      ..removeListener(_onAttention)
      ..dispose();
    _liveness
      ..removeListener(_onAttention)
      ..dispose();
    _search.dispose();
    _searchFocus.dispose();
    _searchButtonFocus.dispose();
    super.dispose();
  }

  /// The "+": the actions that exist today.
  Future<void> _openAdd() async {
    final action = await showServersAddSheet(context);
    if (!mounted || action == null) return;
    switch (action) {
      case ServersAddAction.create:
        _create();
      case ServersAddAction.joinLink:
        await _joinWithLink();
    }
  }

  /// "Dołącz z linku": the pasted link opens the server it names. A public
  /// server answers with its admission (`Dołącz do serwera`); one this
  /// account may not enter answers that it is unavailable — the same two
  /// outcomes as opening the link from outside the app.
  Future<void> _joinWithLink() async {
    final target = await showServerJoinLinkSheet(context);
    if (!mounted || target == null) return;
    _openById(target.serverId, channelId: target.channelId);
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    _searchFocus.requestFocus();
  }

  void _closeSearch() {
    setState(() {
      _searchOpen = false;
      _search.clear();
      _query = '';
    });
    // The button is back in the tree after this frame (it is absent when the
    // window has widened to the inline field in the meantime).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchButtonFocus.context != null) {
        _searchButtonFocus.requestFocus();
      }
    });
  }

  void _create() {
    final callback = widget.onCreateServer;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreateServerScreen(repository: _repository),
      ),
    );
  }

  void _open(Server server) {
    final callback = widget.onOpenServer;
    if (callback != null) {
      callback(server);
      return;
    }
    _openById(server.id);
  }

  void _openById(String serverId, {String? channelId}) {
    if (_width >= ServerWorkspaceScreen.tabletBreakpoint) {
      setState(() {
        _inlineServerId = serverId;
        _inlineChannelId = channelId;
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServerWorkspaceScreen(
          serverId: serverId,
          initialChannelId: channelId,
          repository: _repository,
          chatService: widget.chatService,
          connector: widget.connector,
          questionAttention: _attention,
        ),
      ),
    );
  }

  /// Delete for the owner, leave for everyone else — the role is the
  /// viewer's own directory mirror; the callable stays the authority.
  bool _ownsServer(Server server) {
    final role = server.directoryRole;
    if (role != null) return role == ServerMemberRole.owner;
    final me = _repository.currentUserId;
    return me.isNotEmpty && server.ownerId == me;
  }

  Future<void> _showActions(Server server) async {
    if (_repository is! ServerManagementRepository) return;
    if (_busyIds.contains(server.id)) return;
    final copy = AppLocalizations.of(context);
    final owner = _ownsServer(server);
    final action = await showModalBottomSheet<_DirectoryAction>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          key: const ValueKey('server-directory-actions-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                server.name.isEmpty ? copy.serversTitle : server.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: sheetContext.appPalette.textPrimary,
                ),
              ),
            ),
            if (owner)
              ListTile(
                key: const ValueKey('server-directory-delete'),
                minTileHeight: 56,
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: sheetContext.appPalette.dangerForeground,
                ),
                title: Text(
                  copy.serverDelete,
                  style: TextStyle(
                    color: sheetContext.appPalette.dangerForeground,
                  ),
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_DirectoryAction.delete),
              )
            else
              ListTile(
                key: const ValueKey('server-directory-leave'),
                minTileHeight: 56,
                leading: Icon(
                  Icons.logout_rounded,
                  color: sheetContext.appPalette.dangerForeground,
                ),
                title: Text(
                  copy.serverLeave,
                  style: TextStyle(
                    color: sheetContext.appPalette.dangerForeground,
                  ),
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_DirectoryAction.leave),
              ),
            const SizedBox(height: AppRhythm.tight),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _DirectoryAction.delete:
        await _delete(server);
      case _DirectoryAction.leave:
        await _leave(server);
    }
  }

  Future<void> _delete(Server server) async {
    final management = _repository as ServerManagementRepository;
    // The live channels decide whether the confirmation offers "End
    // conversations and delete". One bounded read; an unreadable list simply
    // offers the plain delete, which the backend still refuses while live.
    var live = const <ServerChannel>[];
    if (!server.isLegacy) {
      try {
        live = liveServerChannels(
          await _repository
              .watchChannels(server.id)
              .first
              .timeout(const Duration(seconds: 5)),
        );
      } catch (_) {
        live = const [];
      }
    }
    if (!mounted) return;
    if (!await confirmServerDeletion(
      context,
      server: server,
      liveChannels: live,
    )) {
      return;
    }
    await _runRowAction(
      server,
      () => deleteServerFor(
        repository: _repository,
        management: management,
        server: server,
        liveChannels: live,
      ),
      failureCopy: (error, copy) =>
          serverDeletionFailureCopy(error, copy, server),
    );
  }

  Future<void> _leave(Server server) async {
    final management = _repository as ServerManagementRepository;
    final copy = AppLocalizations.of(context);
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            key: const ValueKey('server-leave-dialog'),
            content: Text(copy.serverLeaveQuestion),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(copy.serverCancel),
              ),
              FilledButton(
                key: const ValueKey('server-leave-confirm'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(copy.serverLeave),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    await _runRowAction(
      server,
      () => management.leaveServer(
        serverId: server.id,
        requestId: _repository.newRequestId(),
      ),
      failureCopy: (error, copy) => serverActionFailureCopy(error, copy),
    );
  }

  Future<void> _runRowAction(
    Server server,
    Future<void> Function() action, {
    required String Function(Object error, AppLocalizations copy) failureCopy,
  }) async {
    if (_busyIds.contains(server.id)) return;
    setState(() => _busyIds.add(server.id));
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _busyIds.remove(server.id);
        _removedIds.add(server.id);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyIds.remove(server.id));
      final copy = AppLocalizations.of(context);
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const ValueKey('server-directory-action-error'),
            content: Text(failureCopy(error, copy)),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.appPalette.background,
      appBar: widget.isRootTab ? null : AppBar(title: Text(copy.serversTitle)),
      body: SafeArea(
        top: widget.isRootTab,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _width = constraints.maxWidth;
            final inline = _inlineServerId;
            // Once a server is open in this slot it STAYS open, at every
            // width. The condition used to include `_width >= 768`, which
            // made a narrowing window — a resize, browser zoom to 200 % on a
            // 1440 px window, a tablet rotated to portrait — unmount the
            // workspace, run its `dispose()` and end a live conversation
            // mid-sentence, silently, while the surface fell back to the
            // directory. A layout change must never end a media session, so
            // below the breakpoint the same workspace simply renders its
            // phone tier in place (with a way back, which the panel it does
            // not draw there would otherwise have carried).
            final hosting = inline != null;
            // The directory stays mounted under the hosted workspace: its
            // subscription and scroll position survive the visit, exactly as
            // the shell retains its own content slots.
            return Stack(
              children: [
                Offstage(
                  offstage: hosting,
                  child: TickerMode(
                    enabled: !hosting,
                    child: _directory(context, copy, onScreen: !hosting),
                  ),
                ),
                if (hosting)
                  ServerWorkspaceScreen(
                    key: ValueKey('servers-inline-$inline'),
                    serverId: inline,
                    initialChannelId: _inlineChannelId,
                    repository: _repository,
                    isRootTab: true,
                    chatService: widget.chatService,
                    connector: widget.connector,
                    isVisible: widget.isVisible,
                    questionAttention: _attention,
                    onBack: () => setState(() {
                      _inlineServerId = null;
                      _inlineChannelId = null;
                    }),
                    // The workspace's server rail switches servers IN this
                    // slot. Without this callback it falls back to
                    // `pushReplacement` on the root navigator, which would
                    // replace the route that holds the whole app shell.
                    onOpenServer: (server) => setState(() {
                      _inlineServerId = server.id;
                      _inlineChannelId = null;
                    }),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _directory(
    BuildContext context,
    AppLocalizations copy, {
    required bool onScreen,
  }) => ResponsiveContentFrame(
    width: ResponsiveContentWidth.dashboard,
    alignment: ResponsiveContentAlignment.topLeft,
    // The public listing is subscribed OUTSIDE the account's own list, for
    // the board's whole life. Nested the other way round its `StreamBuilder`
    // left the tree whenever the own list showed its error or loading state
    // and listened to the same single-subscription stream again afterwards:
    // "Stream has already been listened to", an error box where the board
    // should be, after nothing more than a failed read and "Spróbuj
    // ponownie". Here it is only ever resubscribed with a NEW stream (the
    // public section's own retry).
    child: StreamBuilder<List<Server>>(
      stream: _public,
      builder: (context, publicSnapshot) => StreamBuilder<List<Server>>(
        stream: _servers,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return SingleChildScrollView(
              child: YoErrorState(
                error: snapshot.error,
                onRetry: () =>
                    setState(() => _servers = _repository.watchMyServers()),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: Semantics(
                label: copy.serversBoardLoading,
                child: const CircularProgressIndicator(),
              ),
            );
          }
          final servers = [
            for (final server in snapshot.data ?? const <Server>[])
              if (!_removedIds.contains(server.id)) server,
          ];
          _attention.trackDirectory(servers);
          // A board hidden under a hosted workspace keeps no lamp listeners.
          _liveness.track(servers, active: onScreen);
          return LayoutBuilder(
            builder: (context, constraints) =>
                _board(context, copy, constraints, servers, publicSnapshot),
          );
        },
      ),
    ),
  );

  /// The public servers this account can still join: the listing minus the
  /// servers it already belongs to (they are in "Twoje serwery").
  static List<Server> _joinable(List<Server> listed, List<Server> mine) {
    final own = {for (final server in mine) server.id};
    return [
      for (final server in listed)
        if (!own.contains(server.id) &&
            ServerService.isJoinablePublicServer(server))
          server,
    ];
  }

  static bool _matches(Server server, String query) =>
      query.isEmpty || server.name.toLowerCase().contains(query);

  Widget _board(
    BuildContext context,
    AppLocalizations copy,
    BoxConstraints constraints,
    List<Server> servers,
    AsyncSnapshot<List<Server>> publicSnapshot,
  ) {
    final palette = context.appPalette;
    final padding = ResponsiveContentFrame.adaptivePagePadding(
      constraints.maxWidth,
    );
    final contentWidth = constraints.maxWidth - padding.horizontal;
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    // Text grows the measure a row or a card needs, up to 200 %.
    final measure = textScale.clamp(1.0, 2.0);
    final inlineSearch = contentWidth >= ServersScreen.inlineSearchWidth;
    final headerScale = inlineSearch
        ? HomeSectionHeaderScale.expanded
        : HomeSectionHeaderScale.compact;
    // The desktop shell's rail draws its own lifted "Stwórz serwer" beside
    // this slot, so there the board's create actions keep the gradient and
    // give up the lift: one lift per screen, exactly as Start does on a
    // desktop. The predicate is MainShell's own (`usesDesktopLayout`):
    // 1 100 px wide AND tall enough for the fixed rail.
    final viewport = MediaQuery.sizeOf(context);
    final railOwnsLift =
        widget.isRootTab &&
        viewport.width >= ServerWorkspaceScreen.desktopBreakpoint &&
        viewport.height >= DesktopSidebar.minimumSupportedHeight;
    final newcomer = servers.isEmpty;

    final query = _query.trim().toLowerCase();
    final filtering = query.isNotEmpty;
    // Live servers first, otherwise the directory's own order: a lamp is
    // never hidden behind "Pokaż wszystkie".
    final mine = [
      for (final server in servers)
        if (_matches(server, query) && _liveness.isLive(server.id)) server,
      for (final server in servers)
        if (_matches(server, query) && !_liveness.isLive(server.id)) server,
    ];
    // The error is read before the data (ADR-083): a failed listing is
    // never drawn from whatever an earlier snapshot left behind.
    final publicFailed = publicSnapshot.hasError;
    // The listing reads more roots than the board shows
    // (`ServerService.publicDirectoryReadLimit`), so legacy clubs and the
    // account's own servers do not take the cards' places; the filter looks
    // through all of them, the board shows the first eight.
    final public = [
      for (final server in _joinable(
        publicFailed
            ? const <Server>[]
            : publicSnapshot.data ?? const <Server>[],
        servers,
      ))
        if (_matches(server, query)) server,
    ].take(ServerService.publicDirectoryLimit).toList(growable: false);

    const gap = ServersBoardMetrics.gap;
    final rowColumns =
        ((contentWidth + gap) /
                (ServersBoardMetrics.rowColumnMinWidth * measure + gap))
            .floor()
            .clamp(1, ServersBoardMetrics.rowMaxColumns);
    final rowLimit = ServersBoardMetrics.collapsedRows * rowColumns;
    final collapsible = !filtering && mine.length > rowLimit;
    final visible = collapsible && !_showAll
        ? mine.take(rowLimit).toList()
        : mine;

    final cardCap = contentWidth < 560
        ? 2
        : contentWidth < 1000
        ? 3
        : 4;
    final cardColumns = ((contentWidth + gap) / (150 * measure + gap))
        .floor()
        .clamp(1, cardCap);

    final manageable = _repository is ServerManagementRepository;
    Widget row(Server server) => ServerBoardRow(
      key: ValueKey('servers-board-row-${server.id}'),
      server: server,
      live: _liveness.isLive(server.id),
      questionsWaiting: _attention.isWaiting(server.id),
      busy: _busyIds.contains(server.id),
      onTap: () => _open(server),
      onActions: manageable ? () => _showActions(server) : null,
    );

    final liveSection = widget.liveSectionBuilder?.call(context);
    final nothingMatches =
        filtering && mine.isEmpty && public.isEmpty && !newcomer;

    return ListView(
      padding: padding.add(
        const EdgeInsets.only(top: AppRhythm.item, bottom: AppRhythm.page),
      ),
      children: [
        _titleRow(
          context,
          copy,
          inlineSearch: inlineSearch,
          // One lift per screen: the first-run invitation's own CTA takes it
          // from the disc, and on a desktop the rail has it.
          discLifted: !railOwnsLift && !newcomer,
        ),
        ?liveSection,
        if (newcomer) ...[
          HomeSectionHeader(title: copy.serversBoardYours, scale: headerScale),
          Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ServersNewcomerBlock(
                onCreate: _create,
                onJoinLink: _joinWithLink,
                lifted: !railOwnsLift,
              ),
            ),
          ),
        ] else if (mine.isNotEmpty) ...[
          HomeSectionHeader(title: copy.serversBoardYours, scale: headerScale),
          _columns(
            [for (final server in visible) row(server)],
            rowColumns,
            (rows) => ServersBoardGroup(children: rows),
          ),
          if (collapsible)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const ValueKey('servers-show-all'),
                onPressed: () => setState(() => _showAll = !_showAll),
                style: TextButton.styleFrom(
                  foregroundColor: palette.interactiveForeground,
                  minimumSize: const Size(48, 44),
                ),
                child: Text(
                  _showAll
                      ? copy.serversBoardShowFewer
                      : copy.serversBoardShowAll,
                ),
              ),
            ),
        ],
        if (nothingMatches)
          Padding(
            key: const ValueKey('servers-no-matches'),
            padding: const EdgeInsets.only(top: AppRhythm.section),
            child: Text(
              copy.serversBoardNoMatches,
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ),
        if (public.isNotEmpty) ...[
          HomeSectionHeader(title: copy.serversBoardPublic, scale: headerScale),
          _grid([
            for (final server in public)
              ServerPublicCard(
                key: ValueKey('servers-board-public-${server.id}'),
                server: server,
                onOpen: () => _open(server),
              ),
          ], cardColumns),
        ] else if (publicFailed && !filtering) ...[
          // A denied or failed listing is said, not swallowed: the silent
          // version of this is how Start's old rail stayed broken unseen.
          HomeSectionHeader(title: copy.serversBoardPublic, scale: headerScale),
          _publicError(context, copy),
        ],
      ],
    );
  }

  Widget _titleRow(
    BuildContext context,
    AppLocalizations copy, {
    required bool inlineSearch,
    required bool discLifted,
  }) {
    final palette = context.appPalette;
    final title = Text(
      copy.serversTitle,
      style: AppTypography.headlineMedium.copyWith(
        fontWeight: FontWeight.w700,
        color: palette.textPrimary,
      ),
    );
    final field = YoSearchField(
      key: const ValueKey('servers-search-field'),
      controller: _search,
      focusNode: _searchFocus,
      hint: copy.serversBoardSearch,
      onChanged: (value) => setState(() => _query = value),
    );
    final add = ServersAddButton(
      onPressed: _openAdd,
      size: inlineSearch ? 44 : 40,
      lifted: discLifted,
    );
    final highContrast = MediaQuery.highContrastOf(context);
    ButtonStyle discStyle() =>
        AppFinish.tonalNeutral(palette, highContrast: highContrast).merge(
          IconButton.styleFrom(
            minimumSize: const Size(40, 40),
            fixedSize: const Size(40, 40),
            padding: EdgeInsets.zero,
          ),
        );
    final Widget child;
    if (inlineSearch) {
      // The desktop slot: the filter sits in the row, where a pointer and a
      // keyboard reach it without opening anything.
      child = Row(
        children: [
          Expanded(child: title),
          const SizedBox(width: AppRhythm.title),
          SizedBox(width: ServersScreen.inlineSearchFieldWidth, child: field),
          const SizedBox(width: AppRhythm.item),
          add,
        ],
      );
    } else if (_searchOpen || _query.isNotEmpty) {
      // A filter typed in the desktop slot stays visible when the window
      // narrows: a list is never filtered by a field nobody can see.
      child = Row(
        children: [
          Expanded(child: field),
          // 12 px between the field and the 40 px disc; the button's 48 px
          // target brings 4 of them and the gutter shift gives 4 back.
          const SizedBox(width: AppRhythm.tight - 4),
          _onGutter(
            context,
            inset: 4,
            child: IconButton.outlined(
              key: const ValueKey('servers-search-close'),
              onPressed: _closeSearch,
              tooltip: copy.serversBoardCloseSearch,
              style: discStyle(),
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          ),
        ],
      );
    } else {
      child = Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppRhythm.title,
        runSpacing: AppRhythm.item,
        children: [
          title,
          _onGutter(
            context,
            inset: 2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.outlined(
                  key: const ValueKey('servers-search'),
                  focusNode: _searchButtonFocus,
                  onPressed: _openSearch,
                  tooltip: copy.serversBoardSearch,
                  style: discStyle(),
                  icon: const Icon(Icons.search_rounded, size: 20),
                ),
                // 10 px between the two 40 px visuals: the button's 48 px
                // and the disc's 44 px targets already bring 6 of them.
                const SizedBox(width: 4),
                add,
              ],
            ),
          ),
        ],
      );
    }
    // One title row, 56 px tall at 100 % text, its content centred in it.
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(width: double.infinity, child: child),
    );
  }

  /// Puts a control's visible SHAPE on the page gutter. The search and close
  /// buttons and the "+" disc are 40 px shapes inside larger touch targets,
  /// so laid out plainly their edge stops [inset] px short of the edge the
  /// blocks under them share. The shift is paint and hit-test only; nothing
  /// in the row moves.
  static Widget _onGutter(
    BuildContext context, {
    required double inset,
    required Widget child,
  }) => Transform.translate(
    offset: Offset(
      Directionality.of(context) == TextDirection.rtl ? -inset : inset,
      0,
    ),
    child: child,
  );

  /// [cells] dealt into [columns] balanced columns, column-major, each
  /// wrapped by [group] — "Twoje serwery" as one block per column. A column
  /// with nothing in it keeps its width, so one server on a desktop is one
  /// row of a sensible measure, not a row stretched across the page.
  static Widget _columns(
    List<Widget> cells,
    int columns,
    Widget Function(List<Widget> rows) group,
  ) {
    if (columns <= 1) return group(cells);
    final base = cells.length ~/ columns;
    final extra = cells.length % columns;
    final slots = <Widget>[];
    var index = 0;
    for (var column = 0; column < columns; column++) {
      final take = base + (column < extra ? 1 : 0);
      final rows = cells.sublist(index, index + take);
      index += take;
      if (column > 0) slots.add(const SizedBox(width: ServersBoardMetrics.gap));
      slots.add(
        Expanded(child: rows.isEmpty ? const SizedBox.shrink() : group(rows)),
      );
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: slots);
  }

  /// [cells] in rows of [columns], each row stretched to its tallest card.
  static Widget _grid(List<Widget> cells, int columns) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < cells.length; i += columns) ...[
        if (i > 0) const SizedBox(height: ServersBoardMetrics.gap),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < columns; j++) ...[
                if (j > 0) const SizedBox(width: ServersBoardMetrics.gap),
                Expanded(
                  child: i + j < cells.length
                      ? cells[i + j]
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      ],
    ],
  );

  Widget _publicError(BuildContext context, AppLocalizations copy) {
    final palette = context.appPalette;
    return Container(
      key: const ValueKey('servers-public-error'),
      // The line carries the button's own 12 px text inset, so when the
      // button wraps under it the two start on one edge.
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: AppFinish.block(
        palette,
        highContrast: MediaQuery.highContrastOf(context),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppRhythm.item,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              copy.serversBoardPublicFailed,
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('servers-public-retry'),
            onPressed: () => setState(() => _public = _watchPublic()),
            style: TextButton.styleFrom(
              foregroundColor: palette.interactiveForeground,
              minimumSize: const Size(48, 44),
            ),
            child: Text(copy.serversBoardRetry),
          ),
        ],
      ),
    );
  }
}

enum _DirectoryAction { delete, leave }
