import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_type.dart';
import '../../data/services/server_service.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';
import '../widgets/server_type_symbol.dart';

typedef ServerChannelBuilder =
    Widget Function(BuildContext context, Server server, ServerChannel channel);

/// Shared directory/workspace shell. Runtime modules are mounted only through
/// an integration callback after server activation; the default is an honest
/// empty-state scaffold, with no demonstration people, sessions or messages.
class ServerWorkspaceScreen extends StatefulWidget {
  const ServerWorkspaceScreen({
    required this.serverId,
    this.repository,
    this.initialChannelId,
    this.isRootTab = false,
    this.onInvite,
    this.channelBuilder,
    super.key,
  });
  final String serverId;
  final ServerRepository? repository;
  final String? initialChannelId;
  final bool isRootTab;
  final ValueChanged<Server>? onInvite;
  final ServerChannelBuilder? channelBuilder;

  @override
  State<ServerWorkspaceScreen> createState() => _ServerWorkspaceScreenState();
}

class _ServerWorkspaceScreenState extends State<ServerWorkspaceScreen> {
  late final ServerRepository _repository;
  late Stream<Server?> _server;
  late Stream<List<ServerChannel>> _channels;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? ServerService();
    _selectedId = widget.initialChannelId;
    _listen();
  }

  void _listen() {
    _server = _repository.watchServer(widget.serverId);
    _channels = _repository.watchChannels(widget.serverId);
  }

  @override
  void didUpdateWidget(ServerWorkspaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverId != widget.serverId) {
      _selectedId = widget.initialChannelId;
      _listen();
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
        child: StreamBuilder<Server?>(
          stream: _server,
          builder: (context, snapshot) {
            if (snapshot.hasError) return _error(snapshot.error!);
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _loading(copy);
            }
            final server = snapshot.data;
            if (server == null) {
              return SingleChildScrollView(
                child: YoEmptyState(
                  icon: Icons.lock_outline,
                  title: copy.text(
                    'Server unavailable',
                    'Serwer jest niedostępny',
                  ),
                  subtitle: copy.text(
                    'It may have been removed or your access may have changed.',
                    'Mógł zostać usunięty lub Twój dostęp się zmienił.',
                  ),
                ),
              );
            }
            return StreamBuilder<List<ServerChannel>>(
              stream: _channels,
              builder: (context, channelsSnapshot) {
                // Do not retain private content behind a failed/revoked read.
                if (channelsSnapshot.hasError) {
                  return _error(channelsSnapshot.error!);
                }
                if (channelsSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return _loading(copy);
                }
                return _workspace(
                  context,
                  server,
                  channelsSnapshot.data ?? const [],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _loading(AppLocalizations copy) => Center(
    child: Semantics(
      label: copy.text('Loading server', 'Wczytywanie serwera'),
      child: const CircularProgressIndicator(),
    ),
  );

  Widget _error(Object error) => SingleChildScrollView(
    child: YoErrorState(error: error, onRetry: () => setState(_listen)),
  );

  Widget _workspace(
    BuildContext context,
    Server server,
    List<ServerChannel> channels,
  ) {
    final copy = AppLocalizations.of(context);
    final selected =
        channels.where((channel) => channel.id == _selectedId).firstOrNull ??
        channels
            .where((channel) => channel.id == server.defaultChannelId)
            .firstOrNull ??
        channels.firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoPanels = constraints.maxWidth >= 768;
        if (!twoPanels) {
          final runtime =
              selected != null &&
              !server.isHeld &&
              widget.channelBuilder != null;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _ServerHeader(
                  server: server,
                  onInvite: server.isHeld ? null : widget.onInvite,
                  onChannels: () => _openChannels(context, server, selected),
                ),
              ),
              if (selected != null)
                SliverToBoxAdapter(
                  child: _ChannelHeader(channel: selected, type: server.type),
                ),
              if (runtime)
                SliverFillRemaining(
                  hasScrollBody: true,
                  child: KeyedSubtree(
                    key: ValueKey('${server.id}/${selected.id}'),
                    child: widget.channelBuilder!(context, server, selected),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: selected == null
                      ? YoEmptyState(
                          icon: Icons.tag_rounded,
                          title: copy.serverNoChannels,
                          subtitle: copy.serverNoChannelsBody,
                        )
                      : ServerChannelEmptyState(
                          server: server,
                          channel: selected,
                          scrollable: false,
                        ),
                ),
            ],
          );
        }
        return ResponsiveContentFrame(
          width: ResponsiveContentWidth.workbench,
          alignment: ResponsiveContentAlignment.topLeft,
          child: Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .5,
                ),
                child: SingleChildScrollView(
                  child: _ServerHeader(
                    server: server,
                    onInvite: server.isHeld ? null : widget.onInvite,
                    onChannels: twoPanels
                        ? null
                        : () => _openChannels(context, server, selected),
                  ),
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (twoPanels)
                      SizedBox(
                        width: constraints.maxWidth >= 1100 ? 248 : 224,
                        child: _ChannelList(
                          server: server,
                          channels: channels,
                          selectedId: selected?.id,
                          onSelected: (channel) =>
                              setState(() => _selectedId = channel.id),
                        ),
                      ),
                    if (twoPanels)
                      VerticalDivider(
                        width: 1,
                        color: context.appPalette.border,
                      ),
                    Expanded(
                      child: selected == null
                          ? SingleChildScrollView(
                              child: YoEmptyState(
                                icon: Icons.tag_rounded,
                                title: copy.serverNoChannels,
                                subtitle: copy.serverNoChannelsBody,
                              ),
                            )
                          : Column(
                              children: [
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: constraints.maxHeight * .25,
                                  ),
                                  child: SingleChildScrollView(
                                    child: _ChannelHeader(
                                      channel: selected,
                                      type: server.type,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child:
                                      !server.isHeld &&
                                          widget.channelBuilder != null
                                      ? KeyedSubtree(
                                          key: ValueKey(
                                            '${server.id}/${selected.id}',
                                          ),
                                          child: widget.channelBuilder!(
                                            context,
                                            server,
                                            selected,
                                          ),
                                        )
                                      : ServerChannelEmptyState(
                                          server: server,
                                          channel: selected,
                                        ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openChannels(
    BuildContext context,
    Server server,
    ServerChannel? selected,
  ) async {
    final picked = await showModalBottomSheet<ServerChannel>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
      builder: (context) => FractionallySizedBox(
        heightFactor: .85,
        child: StreamBuilder<List<ServerChannel>>(
          stream: _repository.watchChannels(widget.serverId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return SingleChildScrollView(
                child: YoErrorState(error: snapshot.error),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _loading(AppLocalizations.of(context));
            }
            return _ChannelList(
              server: server,
              channels: snapshot.data ?? const [],
              selectedId: selected?.id,
              onSelected: (channel) => Navigator.of(context).pop(channel),
            );
          },
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _selectedId = picked.id);
  }
}

class _ServerHeader extends StatelessWidget {
  const _ServerHeader({required this.server, this.onInvite, this.onChannels});
  final Server server;
  final ValueChanged<Server>? onInvite;
  final VoidCallback? onChannels;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = ServerIdentity.of(
      server.type,
    ).resolve(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onChannels != null)
                OutlinedButton.icon(
                  onPressed: onChannels,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  icon: const Icon(Icons.tag_rounded, size: 18),
                  label: Text(copy.serverChannels),
                ),
              OutlinedButton.icon(
                onPressed: onInvite == null ? null : () => onInvite!(server),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: Text(
                  onInvite == null
                      ? copy.text(
                          'Invites · Coming soon',
                          'Zaproszenia · Wkrótce',
                        )
                      : copy.serverInvite,
                ),
              ),
            ],
          );
          final identity = Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.iconSurface,
                  borderRadius: AppRadius.md,
                  border: Border.all(color: colors.iconBorder),
                ),
                child: Center(
                  child: Text(
                    server.initial,
                    style: AppTypography.titleLarge.copyWith(
                      color: colors.foreground,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name.isEmpty ? copy.serversTitle : server.name,
                      style: AppTypography.titleLarge.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: [
                        Text(
                          copy.serverPrivacyTitle(server.privacy),
                          style: AppTypography.bodySmall.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                        Text(
                          copy.serverMembers(server.memberCount),
                          style: AppTypography.bodySmall.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 650) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [identity, const SizedBox(height: 12), actions],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 16),
              Flexible(child: actions),
            ],
          );
        },
      ),
    );
  }
}

class _ChannelList extends StatelessWidget {
  const _ChannelList({
    required this.server,
    required this.channels,
    required this.selectedId,
    required this.onSelected,
  });
  final Server server;
  final List<ServerChannel> channels;
  final String? selectedId;
  final ValueChanged<ServerChannel> onSelected;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final colors = ServerIdentity.of(
      server.type,
    ).resolve(Theme.of(context).brightness);
    return Material(
      color: context.appPalette.surfaceMuted,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: Text(
              copy.serverChannels,
              style: AppTypography.labelMedium.copyWith(
                color: context.appPalette.textSecondary,
              ),
            ),
          ),
          for (final channel in channels)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                key: ValueKey('server-channel-${channel.id}'),
                selected: channel.id == selectedId,
                selectedColor: colors.selectedForeground,
                selectedTileColor: colors.selectedWash,
                minTileHeight: 48,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
                leading: Icon(
                  channel.access == ServerChannelAccess.restricted
                      ? Icons.lock_outline
                      : serverChannelIcon(channel.kind),
                  size: 21,
                ),
                title: Text(channel.name, style: AppTypography.bodyMedium),
                onTap: () => onSelected(channel),
              ),
            ),
          if (channels.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(copy.serverNoChannelsBody),
            ),
        ],
      ),
    );
  }
}

class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({required this.channel, required this.type});
  final ServerChannel channel;
  final ServerType type;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.appPalette.border)),
    ),
    child: Row(
      children: [
        Icon(
          serverChannelIcon(channel.kind),
          color: ServerIdentity.of(
            type,
          ).resolve(Theme.of(context).brightness).foreground,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            channel.name,
            style: AppTypography.titleLarge.copyWith(
              color: context.appPalette.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Different template focal shapes without fictitious activity or media.
class ServerChannelEmptyState extends StatelessWidget {
  const ServerChannelEmptyState({
    required this.server,
    required this.channel,
    this.scrollable = true,
    super.key,
  });
  final Server server;
  final ServerChannel channel;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = ServerIdentity.of(
      server.type,
    ).resolve(Theme.of(context).brightness);
    final isVideo = channel.mediaMode == ServerMediaMode.video;
    final isBoard = channel.kind == ServerChannelKind.whiteboard;
    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(minHeight: 250),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: AppRadius.lg,
              border: Border.all(color: palette.border),
            ),
            child: Column(
              children: [
                if (isVideo || isBoard)
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      decoration: BoxDecoration(
                        color: palette.surfaceSunken,
                        borderRadius: AppRadius.md,
                      ),
                      child: Center(
                        child: Icon(
                          isVideo
                              ? Icons.videocam_off_outlined
                              : Icons.draw_outlined,
                          color: colors.foreground,
                          size: 48,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.iconSurface,
                      border: Border.all(color: colors.iconBorder),
                    ),
                    child: Center(
                      child: channel.kind.isMedia
                          ? ServerTypeSymbol(
                              type: server.type,
                              color: colors.foreground,
                              size: 46,
                            )
                          : Icon(
                              serverChannelIcon(channel.kind),
                              color: colors.foreground,
                              size: 44,
                            ),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  copy.channelEmptyTitle(channel.kind),
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineSmall.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  server.isHeld
                      ? copy.serverHeldBody
                      : copy.text(
                          'This channel is saved. Its shared tools are coming soon.',
                          'Ten kanał jest zapisany. Wspólne narzędzia pojawią się wkrótce.',
                        ),
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Chip(
                  label: Text(copy.serverComingSoon),
                  avatar: const Icon(Icons.schedule_rounded, size: 16),
                ),
              ],
            ),
          ),
          if (server.type == ServerType.family && channel.kind.isMedia) ...[
            const SizedBox(height: 16),
            _EmptyModuleCard(
              icon: Icons.calendar_month_outlined,
              title: copy.text('Next family plan', 'Najbliższy rodzinny plan'),
              body: copy.text(
                'No events have been planned yet.',
                'Nie zaplanowano jeszcze wydarzeń.',
              ),
            ),
            const SizedBox(height: 12),
            _EmptyModuleCard(
              icon: Icons.photo_library_outlined,
              title: copy.text('Family memories', 'Rodzinne wspomnienia'),
              body: copy.text(
                'No memories have been added yet.',
                'Nie dodano jeszcze wspomnień.',
              ),
            ),
          ] else if (channel.kind.isMedia) ...[
            const SizedBox(height: 16),
            _EmptyModuleCard(
              icon: Icons.event_outlined,
              title: server.type == ServerType.podcast
                  ? copy.text('Next episode', 'Następny odcinek')
                  : copy.text('Next event', 'Następne wydarzenie'),
              body: copy.text(
                'There is nothing scheduled yet.',
                'Nie ma jeszcze zaplanowanego terminu.',
              ),
            ),
          ],
        ],
      ),
    );
    return scrollable
        ? SingleChildScrollView(
            key: const ValueKey('server-channel-content-scroll'),
            child: content,
          )
        : content;
  }
}

class _EmptyModuleCard extends StatelessWidget {
  const _EmptyModuleCard({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.appPalette.surface,
      borderRadius: AppRadius.lg,
      border: Border.all(color: context.appPalette.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: context.appPalette.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.titleSmall),
              const SizedBox(height: 4),
              Text(
                body,
                style: AppTypography.bodySmall.copyWith(
                  color: context.appPalette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

IconData serverChannelIcon(ServerChannelKind kind) => switch (kind) {
  ServerChannelKind.text => Icons.tag_rounded,
  ServerChannelKind.voice => Icons.volume_up_outlined,
  ServerChannelKind.stage => Icons.podcasts_rounded,
  ServerChannelKind.events ||
  ServerChannelKind.calendar => Icons.calendar_month_outlined,
  ServerChannelKind.announcements => Icons.campaign_outlined,
  ServerChannelKind.rules => Icons.article_outlined,
  ServerChannelKind.questions => Icons.chat_bubble_outline,
  ServerChannelKind.episodes => Icons.library_music_outlined,
  ServerChannelKind.memories => Icons.photo_library_outlined,
  ServerChannelKind.list => Icons.checklist_outlined,
  ServerChannelKind.meeting => Icons.groups_outlined,
  ServerChannelKind.whiteboard => Icons.draw_outlined,
  ServerChannelKind.files => Icons.insert_drive_file_outlined,
};
