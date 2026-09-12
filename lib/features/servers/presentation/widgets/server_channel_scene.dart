import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_member_role.dart';
import '../../data/models/server_type.dart';
import '../../data/services/server_session_controller.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';
import 'server_community_stage.dart';
import 'server_module_card.dart';
import 'server_panel.dart';
import 'server_podcast_stage.dart';
import 'server_text_channel_scene.dart';
import 'server_type_symbol.dart';
import 'server_voice_stage.dart';

/// Which scene a channel kind mounts in the centre.
enum ServerSceneKind { thread, session, module }

ServerSceneKind serverSceneKindFor(ServerChannelKind kind) => switch (kind) {
  ServerChannelKind.text ||
  ServerChannelKind.questions ||
  ServerChannelKind.announcements ||
  ServerChannelKind.rules => ServerSceneKind.thread,
  ServerChannelKind.voice ||
  ServerChannelKind.stage ||
  ServerChannelKind.meeting => ServerSceneKind.session,
  _ => ServerSceneKind.module,
};

/// The channel header: kind glyph, name and one honest line under it —
/// "Na żywo od 19:40" from the liveness map, or the quiet state. Never a
/// participant, viewer or listener count (no presence writer exists).
class ServerChannelHeader extends StatelessWidget {
  const ServerChannelHeader({
    required this.server,
    required this.channel,
    this.compact = false,
    this.trailing,
    super.key,
  });
  final Server server;
  final ServerChannel channel;
  final bool compact;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = ServerIdentity.of(
      server.type,
    ).resolve(Theme.of(context).brightness);
    final restricted = channel.access == ServerChannelAccess.restricted;
    final live = channel.liveness.isLive;
    final subtitle = channel.kind.isMedia
        ? (live
              ? copy.serverLiveSince(
                  serverLiveClock(context, channel.liveness.startedAt!),
                )
              : copy.serverQuiet(channel.kind))
        : restricted
        ? copy.serverChannelRestricted
        : copy.serverChannelKindTitle(channel.kind);
    return Container(
      key: const ValueKey('server-channel-header'),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 20,
        vertical: compact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Icon(
            restricted ? Icons.lock_outline : serverChannelIcon(channel.kind),
            color: colors.foreground,
            size: compact ? 22 : 26,
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
                const SizedBox(height: 2),
                // The pill and the live line share one row while they fit and
                // fall onto two lines when they do not, instead of the pill
                // holding its intrinsic width unflexed and being cut: at
                // 320 px / 200 % text the single piece of contract-backed
                // truth on this screen rendered as `NA ŻY`, and on board 04
                // as a 13-px red bar with no word in it at all.
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (live) ServerLivePill(label: copy.serverLivePill),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// "19:40" in the viewer's clock format, from the server-written instant.
String serverLiveClock(BuildContext context, DateTime startedAt) =>
    MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(startedAt.toLocal()));

/// The one liveness colour, used only when the channel document says live.
class ServerLivePill extends StatelessWidget {
  const ServerLivePill({required this.label, super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('server-live-pill'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: const BoxDecoration(
      color: AppColors.live,
      borderRadius: AppRadius.pill,
    ),
    child: Text(
      label,
      // One line, never wrapped and never cut through: a marker that says
      // nothing is worse than no marker, so if the word genuinely cannot fit
      // it elides rather than losing its shape.
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.labelSmall.copyWith(
        color: AppColors.onLive,
        fontWeight: FontWeight.w700,
        letterSpacing: .8,
      ),
    ),
  );
}

/// Mounts the scene a channel kind calls for.
class ServerChannelScene extends StatelessWidget {
  const ServerChannelScene({
    required this.server,
    required this.channel,
    required this.session,
    required this.currentUserId,
    this.role,
    this.chatService,
    this.channels = const [],
    this.onOpenChannel,
    this.moderatorIds = const {},
    this.compact = false,
    super.key,
  });
  final Server server;
  final ServerChannel channel;
  final ServerSessionController session;
  final String currentUserId;
  final ServerMemberRole? role;
  final ClubChatService? chatService;

  /// Everybody in this server whose real role carries moderator power, read
  /// from the member roster. Only these ids earn a badge in a thread.
  final Set<String> moderatorIds;

  /// The server's own channels, so a board can offer the real channel its
  /// module belongs to (the friends board's `Wydarzenia`).
  final List<ServerChannel> channels;
  final ValueChanged<ServerChannel>? onOpenChannel;
  final bool compact;

  /// Board 02's `Scena LIVE` is a scene of its own: a 16:9 broadcast, not the
  /// round-avatar conversation the other media channels mount. The same
  /// server's `Salon głosowy` is a `voice` channel and deliberately keeps the
  /// ordinary session scene.
  /// A held root has no runtime at all, so it keeps the shell's own held
  /// scene rather than a broadcast surface that can do nothing.
  bool get _communityStage =>
      server.type == ServerType.community &&
      channel.kind == ServerChannelKind.stage &&
      !server.isHeld;

  /// Board 05's `Studio LIVE` is an audio stage: a host, guests and an
  /// audience, never the community's 16:9 player and never the round
  /// conversation of a lounge. A held root keeps the shell's own held scene,
  /// exactly as every other template does.
  bool get _podcastStage =>
      server.type == ServerType.podcast &&
      channel.kind == ServerChannelKind.stage &&
      !server.isHeld;

  @override
  Widget build(BuildContext context) {
    if (_communityStage) {
      return ServerCommunityStage(
        key: ValueKey('server-community-${channel.id}'),
        server: server,
        channel: channel,
        session: session,
        role: role,
        channels: channels,
        onOpenChannel: onOpenChannel,
        compact: compact,
      );
    }
    if (_podcastStage) {
      return ServerPodcastStage(
        key: ValueKey('server-podcast-${channel.id}'),
        server: server,
        channel: channel,
        session: session,
        role: role,
        channels: channels,
        onOpenChannel: onOpenChannel,
        compact: compact,
      );
    }
    return _scene(context);
  }

  Widget _scene(BuildContext context) =>
      switch (serverSceneKindFor(channel.kind)) {
        ServerSceneKind.thread => ServerTextChannelScene(
          key: ValueKey('server-thread-${channel.id}'),
          server: server,
          channel: channel,
          currentUserId: currentUserId,
          chatService: chatService,
          moderatorIds: moderatorIds,
          compact: compact,
        ),
        ServerSceneKind.session => ServerSessionScene(
          key: ValueKey('server-session-${channel.id}'),
          server: server,
          channel: channel,
          session: session,
          role: role,
          channels: channels,
          onOpenChannel: onOpenChannel,
          compact: compact,
        ),
        ServerSceneKind.module => ServerChannelEmptyState(
          key: ValueKey('server-module-${channel.id}'),
          server: server,
          channel: channel,
        ),
      };
}

/// The join surface of a voice, stage or meeting channel.
///
/// Before joining it shows the liveness the channel document carries and
/// one explicit action; after joining, the people the provider reports.
/// Camera and screen share have no adapter yet (contract D), so they are
/// labelled unavailable rather than drawn as buttons that fail.
class ServerSessionScene extends StatelessWidget {
  const ServerSessionScene({
    required this.server,
    required this.channel,
    required this.session,
    this.role,
    this.channels = const [],
    this.onOpenChannel,
    this.compact = false,
    super.key,
  });
  final Server server;
  final ServerChannel channel;
  final ServerSessionController session;
  final ServerMemberRole? role;
  final List<ServerChannel> channels;
  final ValueChanged<ServerChannel>? onOpenChannel;
  final bool compact;

  bool get _video =>
      channel.mediaMode == ServerMediaMode.video ||
      channel.mediaMode == ServerMediaMode.meeting;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) {
      final copy = AppLocalizations.of(context);
      final palette = context.appPalette;
      final colors = ServerIdentity.of(
        server.type,
      ).resolve(Theme.of(context).brightness);
      final here = session.isIn(channel.id);
      final inRoom =
          here &&
          (session.phase == ServerSessionPhase.connected ||
              session.phase == ServerSessionPhase.reconnecting);
      final live = channel.liveness.isLive;
      final module = _boardModule(context, copy, colors);
      return SingleChildScrollView(
        key: const ValueKey('server-channel-content-scroll'),
        padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: EdgeInsets.all(compact ? 16 : 24),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: AppRadius.lg,
                border: Border.all(
                  color: here && session.isConnected
                      ? palette.audioAccent
                      : palette.border,
                ),
              ),
              child: Column(
                children: [
                  // Tiles exist only while the provider reports a roster, so
                  // before a join the scene is the identity orb and nothing
                  // else; there is no readable pre-join presence (G3).
                  if (_video) _VideoSlot(copy: copy, colors: colors),
                  if (inRoom) ...[
                    if (_video) const SizedBox(height: 20),
                    ServerVoiceStage(
                      participants: session.participants,
                      colors: colors,
                      compact: compact,
                    ),
                  ] else if (!_video)
                    _Orb(server: server, colors: colors, live: live),
                  const SizedBox(height: 20),
                  Text(
                    here && session.isConnected
                        ? copy.serverInConversation
                        : copy.channelEmptyTitle(channel.kind),
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineSmall.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                  // "Nobody is talking yet" is the channel document's
                  // pre-join state. Once the provider has you in the room
                  // with other people it would contradict what is on screen,
                  // so in session only a real live projection still speaks.
                  if (!inRoom || live) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (live) ServerLivePill(label: copy.serverLivePill),
                        Text(
                          live
                              ? copy.serverLiveSince(
                                  serverLiveClock(
                                    context,
                                    channel.liveness.startedAt!,
                                  ),
                                )
                              : copy.serverQuiet(channel.kind),
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMedium.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (server.isHeld)
                    ServerSessionHeld(copy: copy, palette: palette, colors: colors)
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
                      onJoin: () => session.join(server, channel),
                    ),
                  if (_video) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _SoonChip(
                          icon: Icons.videocam_outlined,
                          label:
                              '${copy.serverCamera} · ${copy.serverComingSoon}',
                        ),
                        if (channel.mediaMode == ServerMediaMode.meeting)
                          _SoonChip(
                            icon: Icons.screen_share_outlined,
                            label:
                                '${copy.serverShareScreen} · ${copy.serverComingSoon}',
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (module != null) ...[
              SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
              module,
            ],
          ],
        ),
      );
    },
  );

  /// The board's card under the voice scene.
  ///
  /// Board 01 puts an event card ("Dziś, 20:00 · Wieczór gier · Dołączę")
  /// beneath the Salon. Events have a channel kind and nothing else —
  /// no document, no callable, no Rules (contract G9) — so the card names
  /// the module, says `Wkrótce`, keeps `Dołączę` visibly disabled and offers
  /// the real `Wydarzenia` channel as the way in. It is drawn only when that
  /// channel actually exists in this server.
  Widget? _boardModule(
    BuildContext context,
    AppLocalizations copy,
    ServerIdentityVisuals colors,
  ) {
    if (server.type != ServerType.friends ||
        channel.kind != ServerChannelKind.voice ||
        server.isHeld) {
      return null;
    }
    final events = channels
        .where((candidate) => candidate.kind == ServerChannelKind.events)
        .firstOrNull;
    if (events == null) return null;
    return ServerModuleCard(
      key: const ValueKey('server-friends-event-card'),
      icon: serverChannelIcon(ServerChannelKind.events),
      title: copy.serverNextEvent,
      body: copy.serverEventsModuleBody,
      colors: colors,
      primaryLabel: copy.serverEventRsvp,
      primaryIcon: Icons.event_available_outlined,
      channel: events,
      onOpenChannel: onOpenChannel,
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.server, required this.colors, required this.live});
  final Server server;
  final ServerIdentityVisuals colors;
  final bool live;

  @override
  Widget build(BuildContext context) => Container(
    width: 112,
    height: 112,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: colors.iconSurface,
      border: Border.all(
        color: live ? colors.foreground : colors.iconBorder,
        width: live ? 2 : 1,
      ),
    ),
    child: Center(
      child: ServerTypeSymbol(
        type: server.type,
        color: colors.foreground,
        size: 46,
      ),
    ),
  );
}

class _VideoSlot extends StatelessWidget {
  const _VideoSlot({required this.copy, required this.colors});
  final AppLocalizations copy;
  final ServerIdentityVisuals colors;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surfaceSunken,
          borderRadius: AppRadius.md,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_off_outlined,
              color: colors.foreground,
              size: 44,
            ),
            const SizedBox(height: 8),
            Text(
              '${copy.serverVideoPreview} · ${copy.serverComingSoon}',
              style: AppTypography.labelMedium.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A held root cannot start or join anything: the callable refuses it, so
/// the action is disabled and the reason is on screen beside it.
class ServerSessionHeld extends StatelessWidget {
  const ServerSessionHeld({
    required this.copy,
    required this.palette,
    required this.colors,
    this.fullWidth = false,
    super.key,
  });
  final AppLocalizations copy;
  final AppPalette palette;
  final ServerIdentityVisuals colors;

  /// The family board's lounge card gives its action the full card width.
  final bool fullWidth;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        copy.serverHeldBody,
        textAlign: TextAlign.center,
        style: AppTypography.bodySmall.copyWith(color: palette.textSecondary),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const ValueKey('server-join'),
        onPressed: null,
        style: FilledButton.styleFrom(
          minimumSize: fullWidth
              ? const Size.fromHeight(56)
              : const Size(48, 48),
        ),
        icon: const Icon(Icons.mic_none_rounded, size: 18),
        label: Text(copy.serverJoinConversation),
      ),
    ],
  );
}

class ServerJoinAction extends StatelessWidget {
  const ServerJoinAction({
    required this.channel,
    required this.role,
    required this.live,
    required this.copy,
    required this.colors,
    required this.onJoin,
    this.fullWidth = false,
    super.key,
  });
  final ServerChannel channel;
  final ServerMemberRole? role;
  final bool live;
  final AppLocalizations copy;
  final ServerIdentityVisuals colors;
  final VoidCallback onJoin;

  /// Board 03 gives the family lounge a full-width green action; board 01
  /// keeps the compact one.
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    // A video stage is watched as well as heard — `mediaConfiguration()` gives
    // board 02's `Scena LIVE` `broadcast/video` and the grant a camera source
    // — so its join says so. The podcast's audio stage keeps `Słuchaj`.
    final watch = channel.mediaMode == ServerMediaMode.video;
    final String? label = switch (channel.kind) {
      ServerChannelKind.stage =>
        live
            ? (watch ? copy.serverWatch : copy.serverListen)
            : (role?.canModerate ?? false)
            ? copy.serverGoLive
            : null,
      ServerChannelKind.meeting =>
        live ? copy.serverJoinMeeting : copy.serverStartMeeting,
      _ => copy.serverJoinConversation,
    };
    if (label == null) {
      // A listener cannot start a stage generation (`startSession` needs
      // moderator power there), so no button is drawn to fail.
      return Text(
        copy.serverStageWaiting,
        textAlign: TextAlign.center,
        style: AppTypography.bodySmall.copyWith(color: palette.textSecondary),
      );
    }
    return FilledButton.icon(
      key: const ValueKey('server-join'),
      onPressed: onJoin,
      style:
          FilledButton.styleFrom(
            backgroundColor: colors.cta,
            foregroundColor: colors.onCta,
            minimumSize: fullWidth
                ? const Size.fromHeight(56)
                : const Size(48, 48),
            textStyle: fullWidth ? AppTypography.titleSmall : null,
          ).copyWith(side: serverFocusRing(colors.onCta)),
      icon: Icon(
        channel.kind == ServerChannelKind.stage && live
            ? (watch ? Icons.live_tv_rounded : Icons.headphones_rounded)
            : Icons.mic_none_rounded,
        size: 18,
      ),
      label: Text(label),
    );
  }
}

class ServerSessionStatus extends StatelessWidget {
  const ServerSessionStatus({
    required this.session,
    required this.copy,
    required this.palette,
    required this.colors,
    required this.compact,
    this.controls = true,
    super.key,
  });
  final ServerSessionController session;
  final AppLocalizations copy;
  final AppPalette palette;
  final ServerIdentityVisuals colors;
  final bool compact;

  /// Board 04's meeting keeps `Mikrofon / Kamera / Udostępnij ekran /
  /// Tablica / Opuść` in the dock, so its scene draws no second set of the
  /// same controls. Every other state — connecting, blocked, failed, the
  /// retry — is identical everywhere and stays here.
  final bool controls;

  @override
  Widget build(BuildContext context) {
    switch (session.phase) {
      case ServerSessionPhase.starting:
      case ServerSessionPhase.authorizing:
      case ServerSessionPhase.connecting:
      case ServerSessionPhase.leaving:
        return Column(
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            const SizedBox(height: 12),
            Text(
              switch (session.phase) {
                ServerSessionPhase.authorizing => copy.serverCheckingAccess,
                ServerSessionPhase.leaving => copy.serverLeaving,
                _ => copy.serverConnecting,
              },
              key: const ValueKey('server-session-status'),
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
        );
      case ServerSessionPhase.blocked:
      case ServerSessionPhase.failed:
        final message = session.phase == ServerSessionPhase.blocked
            ? copy.serverOtherVoiceActive
            : session.error is ServerSessionDisconnected
            ? copy.serverConnectionLost
            : serverActionFailureCopy(
                session.error ?? Object(),
                copy,
                fallback: copy.serverJoinFailed,
              );
        return Column(
          children: [
            Text(
              message,
              key: const ValueKey('server-session-status'),
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: palette.dangerForeground,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (session.phase == ServerSessionPhase.failed)
                  FilledButton.icon(
                    key: const ValueKey('server-join-retry'),
                    onPressed: () {
                      final server = session.server;
                      final channel = session.channel;
                      session.dismiss();
                      if (server != null && channel != null) {
                        session.join(server, channel);
                      }
                    },
                    style:
                        FilledButton.styleFrom(
                          backgroundColor: colors.cta,
                          foregroundColor: colors.onCta,
                          minimumSize: const Size(48, 48),
                        ).copyWith(side: serverFocusRing(colors.onCta)),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(copy.serverTryAgain),
                  ),
                OutlinedButton(
                  key: const ValueKey('server-session-dismiss'),
                  onPressed: session.dismiss,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  child: Text(copy.serverDismiss),
                ),
              ],
            ),
          ],
        );
      case ServerSessionPhase.connected:
      case ServerSessionPhase.reconnecting:
        // The roster itself is drawn by `ServerVoiceStage` above the title;
        // what remains here are the three round controls both boards show.
        return Column(
          children: [
            if (session.phase == ServerSessionPhase.reconnecting)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  copy.serverReconnecting,
                  key: const ValueKey('server-session-status'),
                  style: AppTypography.bodyMedium.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
            if (controls)
              ServerVoiceControls(
                session: session,
                colors: colors,
                compact: compact,
              ),
          ],
        );
      case ServerSessionPhase.idle:
        return const SizedBox.shrink();
    }
  }
}

class _SoonChip extends StatelessWidget {
  const _SoonChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(icon, size: 16),
    // The chip takes its label's intrinsic width; at 200 % text that is wider
    // than the column it sits in, and the pill is cut flat by its edge.
    label: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
  );
}

/// Module channels (events, episodes, calendar, memories, lists, whiteboard,
/// files) have kinds but no persistence yet (contract G9): an honest
/// "Wkrótce" state without fictitious activity or media.
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
    final isBoard = channel.kind == ServerChannelKind.whiteboard;
    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(minHeight: 250),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadius.lg,
          border: Border.all(color: palette.border),
        ),
        child: Column(
          children: [
            if (isBoard)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  decoration: BoxDecoration(
                    color: palette.surfaceSunken,
                    borderRadius: AppRadius.md,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.draw_outlined,
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
                  child: Icon(
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
    );
    return scrollable
        ? SingleChildScrollView(
            key: const ValueKey('server-channel-content-scroll'),
            child: content,
          )
        : content;
  }
}

/// Which of a server's channels carries its conversation next to a media
/// scene: the seeded default text channel, else the first thread channel.
///
/// [prefer] names the kind a particular scene reads instead — board 05 puts
/// `Pytania słuchaczy` beside the studio, and that is the server's real
/// `questions` channel, not its discussion channel. A preference that the
/// server does not have falls back to the ordinary choice rather than leaving
/// the panel empty.
ServerChannel? serverContextThreadChannel(
  Server server,
  List<ServerChannel> channels, {
  ServerChannelKind? prefer,
}) {
  bool thread(ServerChannel channel) =>
      serverSceneKindFor(channel.kind) == ServerSceneKind.thread;
  if (prefer != null) {
    final preferred = channels
        .where((channel) => channel.kind == prefer)
        .where(thread)
        .firstOrNull;
    if (preferred != null) return preferred;
  }
  return channels
          .where((channel) => channel.id == server.defaultChannelId)
          .where(thread)
          .firstOrNull ??
      channels.where(thread).firstOrNull;
}
