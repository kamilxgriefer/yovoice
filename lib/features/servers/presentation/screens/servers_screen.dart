import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

import '../../data/models/server.dart';
import '../../data/services/server_service.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';
import 'create_server_screen.dart';
import 'server_workspace_screen.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({
    this.repository,
    this.isRootTab = false,
    this.onOpenServer,
    this.onCreateServer,
    super.key,
  });
  final ServerRepository? repository;
  final bool isRootTab;
  final ValueChanged<Server>? onOpenServer;
  final VoidCallback? onCreateServer;

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  late final ServerRepository _repository;
  late Stream<List<Server>> _servers;

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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ServerWorkspaceScreen(serverId: server.id, repository: _repository),
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
        child: ResponsiveContentFrame(
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
                builder: (context, constraints) => ListView(
                  padding: ResponsiveContentFrame.adaptivePagePadding(
                    constraints.maxWidth,
                  ).add(const EdgeInsets.symmetric(vertical: 16)),
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        Text(
                          copy.serversTitle,
                          style: AppTypography.headlineLarge,
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
                    const SizedBox(height: 24),
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
                      ),
                    for (final server in servers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ServerTile(
                          server: server,
                          onTap: () => _open(server),
                        ),
                      ),
                    const SizedBox(height: 32),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.server, required this.onTap});
  final Server server;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final identity = ServerIdentity.of(
      server.type,
    ).resolve(Theme.of(context).brightness);
    final avatar = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: identity.iconSurface,
        borderRadius: AppRadius.md,
      ),
      child: Center(
        child: Text(
          server.initial,
          style: AppTypography.titleLarge.copyWith(color: identity.foreground),
        ),
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          server.name.isEmpty ? copy.serversTitle : server.name,
          style: AppTypography.titleMedium.copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          copy.serverTypeTitle(server.type),
          style: AppTypography.bodySmall.copyWith(color: palette.textSecondary),
        ),
        if (server.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            server.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              color: palette.textSecondary,
            ),
          ),
        ],
      ],
    );
    final arrow = Icon(Icons.chevron_right, color: palette.textSecondary);
    return Material(
      key: ValueKey('server-directory-${server.id}'),
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lg,
        side: BorderSide(color: palette.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lg,
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                    const SizedBox(height: 16),
                    details,
                  ],
                );
              }
              return Row(
                children: [
                  avatar,
                  const SizedBox(width: 16),
                  Expanded(child: details),
                  const SizedBox(width: 8),
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
