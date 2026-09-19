import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/navigation/yo_server_rail_item.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_member_role.dart';
import '../../data/services/server_media_connector.dart';
import '../../data/services/server_service.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import '../widgets/server_delete_flow.dart';
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

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? ServerService();
    _servers = _repository.watchMyServers();
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
            const columnGap = AppRhythm.section;
            final rowWidth =
                (contentWidth - columnGap * (columns - 1)) / columns;
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
                          fontWeight: FontWeight.w800,
                          color: context.appPalette.textPrimary,
                        ),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('servers-create'),
                        onPressed: _create,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
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
                    title: copy.text(
                      'Your place for shared conversations',
                      'Twoje miejsce na wspólne rozmowy',
                    ),
                    subtitle: copy.text(
                      'Create a server or accept an invitation to get started.',
                      'Stwórz serwer lub przyjmij zaproszenie, aby zacząć.',
                    ),
                  )
                else
                  Wrap(
                    spacing: columnGap,
                    runSpacing: AppRhythm.hairline,
                    children: [
                      for (final server in servers)
                        SizedBox(
                          width: rowWidth,
                          child: _ServerTile(
                            server: server,
                            onTap: () => _open(server),
                            onActions: _repository is ServerManagementRepository
                                ? () => _showActions(server)
                                : null,
                            busy: _busyIds.contains(server.id),
                          ),
                        ),
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

/// One server in the directory: a flat 64–68 px row (squircle, name, what
/// kind of server it is and how many members it has, the description on one
/// more line) with a hover / press wash instead of a bordered card.
enum _DirectoryAction { delete, leave }

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.onTap,
    this.onActions,
    this.busy = false,
  });
  final Server server;
  final VoidCallback onTap;

  /// Opens the row's action sheet (delete for the owner, leave otherwise)
  /// from the trailing button, a long press or a secondary click. Null for a
  /// read-only repository that cannot administer a server.
  final VoidCallback? onActions;

  /// A delete or leave for this row is in flight.
  final bool busy;

  static const double _tileSize = 44;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final avatar = YoServerTile(
      initial: server.initial,
      type: server.type,
      size: _tileSize,
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
          '${copy.serverTypeTitle(server.type)} · '
          '${copy.serverMembers(server.memberCount)}',
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
    final actions = onActions;
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
    return Material(
      key: ValueKey('server-directory-${server.id}'),
      color: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        onLongPress: busy ? null : actions,
        onSecondaryTap: busy ? null : actions,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: AppRhythm.item,
            end: actions == null ? AppRhythm.item : AppRhythm.hairline,
            top: AppRhythm.item,
            bottom: AppRhythm.item,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final stacked =
                  textScale > 1.3 &&
                  constraints.maxWidth - (actions == null ? 96 : 144) <
                      160 * textScale;
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [avatar, const Spacer(), arrow]),
                    const SizedBox(height: AppRhythm.item),
                    details,
                  ],
                );
              }
              return Row(
                children: [
                  avatar,
                  const SizedBox(width: AppRhythm.item),
                  Expanded(child: details),
                  const SizedBox(width: AppRhythm.tight),
                  arrow,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
