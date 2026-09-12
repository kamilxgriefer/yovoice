import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_member_role.dart';
import '../../data/services/server_session_controller.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';
import 'server_channel_scene.dart';
import 'server_module_card.dart';
import 'server_panel.dart';
import 'server_voice_stage.dart';

/// `Rodzinny pulpit` — board 03's home surface.
///
/// It is a **view of the family server**, not a channel: nothing is seeded
/// under this name and no document is invented for it. Everything on it is
/// either real (the lounge, which joins through the reviewed token path) or
/// visibly a module that does not exist yet: the calendar, the memory album
/// and the shared list have channel kinds and no persistence, callable or
/// Rules at all (contract G9), so they render as named `Wkrótce` modules
/// with their action disabled and the real channel offered beside it.
///
/// Family type and targets are one step larger than the other templates',
/// which is the board's own difference.
class ServerFamilyBoard extends StatelessWidget {
  const ServerFamilyBoard({
    required this.server,
    required this.channels,
    required this.session,
    required this.onOpenChannel,
    this.role,
    this.compact = false,
    super.key,
  });

  final Server server;
  final List<ServerChannel> channels;
  final ServerSessionController session;
  final ValueChanged<ServerChannel> onOpenChannel;
  final ServerMemberRole? role;

  /// Phone width: one column, tighter paddings, smaller stage.
  final bool compact;

  /// Three cards across from here, two from [_twoColumnWidth], one below it.
  static const threeColumnWidth = 980.0;
  static const _twoColumnWidth = 620.0;

  ServerChannel? _first(ServerChannelKind kind) =>
      channels.where((channel) => channel.kind == kind).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = ServerIdentity.of(
      server.type,
    ).resolve(Theme.of(context).brightness);
    final lounge = _first(ServerChannelKind.voice);
    final modules = <Widget>[
      if (_first(ServerChannelKind.calendar) case final calendar?)
        ServerModuleCard(
          key: const ValueKey('server-family-plans'),
          icon: serverChannelIcon(ServerChannelKind.calendar),
          title: copy.serverFamilyPlans,
          body: copy.serverFamilyPlansBody,
          colors: colors,
          primaryLabel: copy.serverFamilyPlansRsvp,
          primaryIcon: Icons.check_circle_outline,
          channel: calendar,
          onOpenChannel: onOpenChannel,
          large: true,
        ),
      if (_first(ServerChannelKind.memories) case final memories?)
        ServerModuleCard(
          key: const ValueKey('server-family-memories'),
          icon: serverChannelIcon(ServerChannelKind.memories),
          title: copy.serverFamilyMemories,
          body: copy.serverFamilyMemoriesBody,
          colors: colors,
          primaryLabel: copy.serverFamilyMemoriesPlay,
          primaryIcon: Icons.play_arrow_rounded,
          channel: memories,
          onOpenChannel: onOpenChannel,
          large: true,
        ),
      if (_first(ServerChannelKind.list) case final list?)
        ServerModuleCard(
          key: const ValueKey('server-family-shopping'),
          icon: serverChannelIcon(ServerChannelKind.list),
          title: copy.serverFamilyShopping,
          body: copy.serverFamilyShoppingBody,
          colors: colors,
          primaryLabel: copy.serverFamilyShoppingAdd,
          primaryIcon: Icons.add_rounded,
          channel: list,
          onOpenChannel: onOpenChannel,
          large: true,
        ),
    ];
    return SingleChildScrollView(
      key: const ValueKey('server-family-board'),
      padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Hero(server: server, colors: colors, compact: compact),
          SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
          if (lounge != null) ...[
            _LoungeCard(
              server: server,
              channel: lounge,
              session: session,
              role: role,
              colors: colors,
              compact: compact,
            ),
            SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
          ],
          if (modules.isEmpty)
            Text(
              copy.serverNoChannelsBody,
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textSecondary,
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= threeColumnWidth
                    ? 3
                    : constraints.maxWidth >= _twoColumnWidth
                    ? 2
                    : 1;
                if (columns == 1) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < modules.length; index++) ...[
                        if (index > 0) const SizedBox(height: AppSpacing.md),
                        modules[index],
                      ],
                    ],
                  );
                }
                const gap = AppSpacing.md;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  key: const ValueKey('server-family-modules'),
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final module in modules)
                      SizedBox(width: width, child: module),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

/// "Dobrze być razem." with the server's real privacy stated beside it.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.server,
    required this.colors,
    required this.compact,
  });
  final Server server;
  final ServerIdentityVisuals colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Column(
      key: const ValueKey('server-family-hero'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // On a phone the surface header carries the lock and the boundary
        // two rows above; repeating it here would say the same thing twice.
        if (!compact) ...[
          Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: 20,
                color: palette.textSecondary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  copy.serverPrivacyTitle(server.privacy),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.eyebrow.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Text(
          copy.serverFamilyHeroTitle,
          style:
              (compact
                      ? AppTypography.headlineSmall
                      : AppTypography.headlineLarge)
                  .copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          copy.serverFamilyHeroBody,
          style:
              (compact ? AppTypography.bodyMedium : AppTypography.bodyLarge)
                  .copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }
}

/// The family lounge, joined for real through the same reviewed path the
/// rest of the shell uses. Pre-join it says only what the channel document
/// carries — live since HH:MM, or that nobody is talking — and never a
/// number of people, because no presence writer exists (contract G6).
class _LoungeCard extends StatelessWidget {
  const _LoungeCard({
    required this.server,
    required this.channel,
    required this.session,
    required this.role,
    required this.colors,
    required this.compact,
  });
  final Server server;
  final ServerChannel channel;
  final ServerSessionController session;
  final ServerMemberRole? role;
  final ServerIdentityVisuals colors;
  final bool compact;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) {
      final copy = AppLocalizations.of(context);
      final palette = context.appPalette;
      final live = channel.liveness.isLive;
      final here = session.isIn(channel.id);
      final inRoom =
          here &&
          (session.phase == ServerSessionPhase.connected ||
              session.phase == ServerSessionPhase.reconnecting);
      return Container(
        key: const ValueKey('server-family-lounge'),
        padding: EdgeInsets.all(compact ? 16 : 24),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadius.lg,
          border: Border.all(
            color: inRoom ? palette.audioAccent : palette.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: compact ? 40 : 48,
                  height: compact ? 40 : 48,
                  decoration: BoxDecoration(
                    color: colors.iconSurface,
                    borderRadius: AppRadius.md,
                    border: Border.all(color: colors.iconBorder),
                  ),
                  child: Icon(
                    serverChannelIcon(channel.kind),
                    size: compact ? 22 : 26,
                    color: colors.foreground,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            (compact
                                    ? AppTypography.titleMedium
                                    : AppTypography.titleLarge)
                                .copyWith(color: palette.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (live) ServerLivePill(label: copy.serverLivePill),
                          Text(
                            here && session.isConnected
                                ? copy.serverInConversation
                                : live
                                ? copy.serverLiveSince(
                                    serverLiveClock(
                                      context,
                                      channel.liveness.startedAt!,
                                    ),
                                  )
                                : copy.serverQuiet(channel.kind),
                            style: AppTypography.bodyMedium.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 16 : 20),
            if (inRoom) ...[
              ServerVoiceStage(
                participants: session.participants,
                colors: colors,
                compact: compact,
              ),
              SizedBox(height: compact ? 16 : 20),
            ],
            if (server.isHeld)
              ServerSessionHeld(
                copy: copy,
                palette: palette,
                colors: colors,
                fullWidth: true,
              )
            else if (here)
              ServerSessionStatus(
                session: session,
                copy: copy,
                palette: palette,
                colors: colors,
                compact: compact,
              )
            else
              ServerJoinAction(
                channel: channel,
                role: role,
                live: live,
                copy: copy,
                colors: colors,
                fullWidth: true,
                onJoin: () => session.join(server, channel),
              ),
          ],
        ),
      );
    },
  );
}
