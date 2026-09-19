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
import '../../data/services/server_media_connector.dart';
import '../../data/services/server_service.dart';
import '../server_localized_copy.dart';
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
        final servers = snapshot.data ?? const <Server>[];
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
class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.server, required this.onTap});
  final Server server;
  final VoidCallback onTap;

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
    final arrow = Icon(
      Icons.chevron_right_rounded,
      size: 22,
      color: palette.textTertiary,
    );
    return Material(
      key: ValueKey('server-directory-${server.id}'),
      color: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppRhythm.item,
            vertical: AppRhythm.item,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final stacked =
                  textScale > 1.3 &&
                  constraints.maxWidth - 96 < 160 * textScale;
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
