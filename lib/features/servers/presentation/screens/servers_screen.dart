import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';
import 'package:yovoice/shared/widgets/interactions/yo_press_feedback.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/navigation/yo_server_rail_item.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_member_role.dart';
import '../../data/services/server_media_connector.dart';
import '../../data/services/server_question_attention.dart';
import '../../data/services/server_service.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';
import '../widgets/server_channel_scene.dart';
import '../widgets/server_delete_flow.dart';
import '../widgets/server_waiting_dot.dart';
import 'create_server_screen.dart';
import 'server_workspace_screen.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({
    this.repository,
    this.isRootTab = false,
    this.onOpenServer,
    this.onCreateServer,
    this.chatService,
    this.connector,
    this.isVisible,
    super.key,
  });
  final ServerRepository? repository;
  final bool isRootTab;
  final ValueChanged<Server>? onOpenServer;
  final VoidCallback? onCreateServer;

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
  double _width = 0;

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
    _attention = ServerQuestionAttention(
      repository: _repository,
      isVisible: widget.isVisible,
    )..addListener(_onAttention);
  }

  void _onAttention() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _attention
      ..removeListener(_onAttention)
      ..dispose();
    super.dispose();
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
    if (_width >= ServerWorkspaceScreen.tabletBreakpoint) {
      setState(() => _inlineServerId = server.id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServerWorkspaceScreen(
          serverId: server.id,
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
                    child: _directory(context, copy),
                  ),
                ),
                if (hosting)
                  ServerWorkspaceScreen(
                    key: ValueKey('servers-inline-$inline'),
                    serverId: inline,
                    repository: _repository,
                    isRootTab: true,
                    chatService: widget.chatService,
                    connector: widget.connector,
                    isVisible: widget.isVisible,
                    questionAttention: _attention,
                    onBack: () => setState(() => _inlineServerId = null),
                    // The workspace's server rail switches servers IN this
                    // slot. Without this callback it falls back to
                    // `pushReplacement` on the root navigator, which would
                    // replace the route that holds the whole app shell.
                    onOpenServer: (server) =>
                        setState(() => _inlineServerId = server.id),
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
    AppLocalizations copy,
  ) => ResponsiveContentFrame(
    width: ResponsiveContentWidth.dashboard,
    alignment: ResponsiveContentAlignment.topLeft,
    child: StreamBuilder<List<Server>>(
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
              label: copy.text('Loading servers', 'Wczytywanie serwerów'),
              child: const CircularProgressIndicator(),
            ),
          );
        }
        final servers = [
          for (final server in snapshot.data ?? const <Server>[])
            if (!_removedIds.contains(server.id)) server,
        ];
        _attention.trackDirectory(servers);
        return LayoutBuilder(
          builder: (context, constraints) {
            final padding = ResponsiveContentFrame.adaptivePagePadding(
              constraints.maxWidth,
            );
            final contentWidth = constraints.maxWidth - padding.horizontal;
            // Slim: a compact list, not a stack of bordered cards. From the
            // list measure up the rows flow into two columns so a desktop
            // slot is never one phone-width row stretched across 1 200 px.
            final columns = contentWidth >= ResponsiveContentWidth.form.maxWidth
                ? 2
                : 1;
            // Refine-look §8.2: rows are blocks now, so the gaps are the
            // block rhythm — 16 between the columns, 12 between the rows.
            const columnGap = AppRhythm.title;
            final rowWidth =
                (contentWidth - columnGap * (columns - 1)) / columns;
            // The desktop shell's rail draws its own lifted "Stwórz serwer"
            // beside this slot, so there this identical action keeps the
            // gradient and gives up the lift: one lift per screen, exactly as
            // Start does on a desktop. The predicate is MainShell's own
            // (`usesDesktopLayout`, spelled out as the preview shell does):
            // 1 100 px wide AND tall enough for the fixed rail — a wide but
            // short window gets the phone shell, with no rail, and keeps
            // the lift.
            final viewport = MediaQuery.sizeOf(context);
            final railOwnsLift =
                widget.isRootTab &&
                viewport.width >= ServerWorkspaceScreen.desktopBreakpoint &&
                viewport.height >= DesktopSidebar.minimumSupportedHeight;
            final scheme = Theme.of(context).colorScheme;
            Widget tile(Server server) => _ServerTile(
              server: server,
              width: rowWidth,
              questionsWaiting: _attention.isWaiting(server.id),
              onTap: () => _open(server),
              onActions: _repository is ServerManagementRepository
                  ? () => _showActions(server)
                  : null,
              busy: _busyIds.contains(server.id),
            );
            return ListView(
              padding: padding.add(
                const EdgeInsets.only(
                  top: AppRhythm.item,
                  bottom: AppRhythm.page,
                ),
              ),
              children: [
                // One title row, at most 56 px tall at 100 % text: the
                // screen's single headline and its single primary action.
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppRhythm.title,
                    runSpacing: AppRhythm.item,
                    children: [
                      Text(
                        copy.serversTitle,
                        style: AppTypography.headlineMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.appPalette.textPrimary,
                        ),
                      ),
                      // The directory's one CTA (refine-look R5): the
                      // brand action gradient and the rail's lift.
                      ServerGradientFilledButton(
                        buttonKey: const ValueKey('servers-create'),
                        onPressed: _create,
                        gradient: AppGradients.primaryAction(scheme),
                        fill: scheme.primary,
                        foreground: scheme.onPrimary,
                        liftColor: AppColors.primary,
                        lifted: !railOwnsLift,
                        icon: const Icon(Icons.add_rounded),
                        label: Text(
                          copy.text('Create server', 'Stwórz serwer'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppRhythm.item),
                if (servers.isEmpty)
                  YoEmptyState(
                    icon: Icons.hub_outlined,
                    // The first-run invitation carries the real logo (§4):
                    // a bloom in Dark, a contact shadow in Pearl.
                    leading: const YoBrandMark(
                      key: ValueKey('servers-empty-logo'),
                      size: 72,
                    ),
                    title: copy.text(
                      'Your place for shared conversations',
                      'Twoje miejsce na wspólne rozmowy',
                    ),
                    subtitle: copy.text(
                      'Create a server or accept an invitation to get started.',
                      'Stwórz serwer lub przyjmij zaproszenie, aby zacząć.',
                    ),
                  )
                else if (columns == 1)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < servers.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppRhythm.item),
                        tile(servers[i]),
                      ],
                    ],
                  )
                else
                  // Two columns render as row-major pairs, each pair
                  // stretched to the taller block, so a one-line row never
                  // sits beside a three-line one at a different height, and
                  // focus still runs left → right, top → bottom.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < servers.length; i += 2) ...[
                        if (i > 0) const SizedBox(height: AppRhythm.item),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: rowWidth,
                                child: tile(servers[i]),
                              ),
                              const SizedBox(width: columnGap),
                              SizedBox(
                                width: rowWidth,
                                child: i + 1 < servers.length
                                    ? tile(servers[i + 1])
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            );
          },
        );
      },
    ),
  );
}

enum _DirectoryAction { delete, leave }

/// One server in the directory (refine-look §8.2): squircle, name, what kind
/// of server it is and how many members it has, the description on one more
/// line — on the neutral R2 block. The identity lives only in the squircle,
/// never as a tint on the block.
///
/// The block is painted with `Ink` inside the row's own keyed `Material`
/// (`server-directory-<id>`), so the press wash lands on it; Pearl's shadow
/// pair sits on an outer box that the clip cannot cut, and the edge is that
/// box's foreground (as in `YoCard`): `Ink` would pad its child by a border
/// of its own. Hover moves the hairline to `hairlineHover` (and sinks
/// Pearl's drop), keyboard focus swaps it for a 2 px `focus` ring, and
/// neither moves a pixel of layout. No ink ripple except InkSparkle on
/// Android. At least 72 px tall.
class _ServerTile extends StatefulWidget {
  const _ServerTile({
    required this.server,
    required this.width,
    required this.onTap,
    this.onActions,
    this.busy = false,
    this.questionsWaiting = false,
  });
  final Server server;

  /// The row's own width. The stacked 200 % layout is decided from it
  /// rather than from a `LayoutBuilder`, because two-column pairs measure
  /// their rows' intrinsic height and a `LayoutBuilder` has none.
  final double width;
  final VoidCallback onTap;

  /// Listener questions on this podcast server wait for this host: the
  /// squircle carries the shared waiting dot, so the host sees it before
  /// opening the server.
  final bool questionsWaiting;

  /// Opens the row's action sheet (delete for the owner, leave otherwise)
  /// from the trailing button, a long press or a secondary click. Null for a
  /// read-only repository that cannot administer a server.
  final VoidCallback? onActions;

  /// A delete or leave for this row is in flight.
  final bool busy;

  static const double _tileSize = 44;
  static const double minHeight = 72;

  /// The resting edge's width. The edge is a foreground, so this much inset
  /// keeps the content exactly where the in-layout hairline used to leave it.
  static const double _edgeInset = 1;

  @override
  State<_ServerTile> createState() => _ServerTileState();
}

class _ServerTileState extends State<_ServerTile> {
  bool _hovered = false;
  bool _focused = false;

  static InteractiveInkFeatureFactory get _splashFactory =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? InkSparkle.splashFactory
      : NoSplash.splashFactory;

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final onTap = widget.onTap;
    final busy = widget.busy;
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final avatar = ServerWaitingDot.on(
      waiting: widget.questionsWaiting,
      semanticLabel: copy.serverQuestionsWaitingLabel,
      dotKey: ValueKey('server-directory-questions-waiting-${server.id}'),
      child: YoServerTile(
        initial: server.initial,
        type: server.type,
        size: _ServerTile._tileSize,
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          server.name.isEmpty ? copy.serversTitle : server.name,
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          // Non-breaking spaces keep "184 osoby" whole and the dot with the
          // words before it.
          serverMetaLine(
            copy.serverTypeTitle(server.type),
            copy.serverMembers(server.memberCount),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySmall.copyWith(color: palette.textSecondary),
        ),
        if (server.description.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            server.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              color: palette.textTertiary,
            ),
          ),
        ],
      ],
    );
    final chevron = Icon(
      Icons.chevron_right_rounded,
      size: 22,
      color: palette.textTertiary,
    );
    final actions = widget.onActions;
    final Widget arrow = actions == null
        ? chevron
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox.square(
                  dimension: 48,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                IconButton(
                  key: ValueKey('server-directory-actions-${server.id}'),
                  onPressed: actions,
                  tooltip: copy.serverManage,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: palette.textSecondary,
                  ),
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              chevron,
            ],
          );
    final padding = EdgeInsetsDirectional.only(
      start: AppRhythm.item,
      end: actions == null ? AppRhythm.item : AppRhythm.hairline,
      top: AppRhythm.item,
      bottom: AppRhythm.item,
    );
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final innerWidth = widget.width - padding.horizontal;
    final stacked =
        textScale > 1.3 &&
        innerWidth - (actions == null ? 96 : 144) < 160 * textScale;
    final content = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [avatar, const Spacer(), arrow]),
              const SizedBox(height: AppRhythm.item),
              // The row's tight end inset is for the "…" button; the text
              // under it keeps the same 12 px as at the start.
              Padding(
                padding: EdgeInsetsDirectional.only(
                  end: AppRhythm.item - padding.end,
                ),
                child: details,
              ),
            ],
          )
        : Row(
            children: [
              avatar,
              const SizedBox(width: AppRhythm.item),
              Expanded(child: details),
              const SizedBox(width: AppRhythm.tight),
              arrow,
            ],
          );
    final hovered = _hovered && !busy;
    final fill = AppFinish.blockFill(
      palette,
      hovered: hovered,
      highContrast: highContrast,
    );
    final Border edge = _focused
        ? Border.all(color: palette.focus, width: 2)
        : AppFinish.blockEdge(
            palette,
            hovered: hovered,
            highContrast: highContrast,
          );
    final pressedWash = AppFinish.blockPressedWash(palette);
    // R2's touch press: the block settles by .985 (none under Reduce
    // Motion). It listens to raw pointers only, so the row's tap, long press
    // and secondary click keep their own gesture handling.
    return YoPressFeedback(
      enabled: !busy,
      child: AnimatedContainer(
        // Pearl's shadow pair, outside the row's clip.
        duration: AppMotion.resolve(context, AppMotion.quick),
        curve: AppMotion.standardCurve,
        decoration: BoxDecoration(
          borderRadius: AppRadius.block,
          boxShadow: fill.boxShadow,
        ),
        // The hairline, or the focus ring, drawn over the block: a
        // foreground never takes layout, so neither moves the content.
        foregroundDecoration: BoxDecoration(
          borderRadius: AppRadius.block,
          border: edge,
        ),
        child: Material(
          key: ValueKey('server-directory-${server.id}'),
          color: Colors.transparent,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.block),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              color: fill.color,
              gradient: fill.gradient,
              borderRadius: AppRadius.block,
            ),
            child: InkWell(
              onTap: busy ? null : onTap,
              onLongPress: busy ? null : actions,
              onSecondaryTap: busy ? null : actions,
              splashFactory: _splashFactory,
              onHover: (value) {
                if (_hovered != value) setState(() => _hovered = value);
              },
              onFocusChange: (value) {
                if (_focused != value) setState(() => _focused = value);
              },
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) return pressedWash;
                // Hover and focus are carried by the edge, not a wash.
                return Colors.transparent;
              }),
              child: Padding(
                padding: const EdgeInsets.all(_ServerTile._edgeInset),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: _ServerTile.minHeight,
                  ),
                  child: Padding(padding: padding, child: content),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
