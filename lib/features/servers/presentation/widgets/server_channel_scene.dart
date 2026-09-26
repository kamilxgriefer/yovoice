import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/shared/widgets/badges/yo_badge.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_member_role.dart';
import '../../data/models/server_type.dart';
import '../../data/services/server_session_controller.dart';
import '../../data/services/server_follow_service.dart';
import '../../data/services/server_podcast_episode_repository.dart';
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
    this.liveLamp = false,
    super.key,
  });
  final Server server;
  final ServerChannel channel;
  final bool compact;
  final Widget? trailing;

  /// Whether the scene on screen under this header renders its OWN
  /// `server-live-pill` — the session card, the community stage's picture,
  /// the wide podcast studio. Only then does a live header say LIVE with the
  /// quieter [ServerLiveLamp] (refine-look §8.2), because the word is
  /// already on the card below. Everywhere else — the company meeting,
  /// whose shared-screen surface carries no pill, a host-supplied scene, a
  /// tab that shows the conversation instead of the scene — the header keeps
  /// the pill, so a live screen never loses its "NA ŻYWO".
  final bool liveLamp;

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
    final subtitleStyle = AppTypography.bodySmall.copyWith(
      color: palette.textSecondary,
    );
    return Container(
      key: const ValueKey('server-channel-header'),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 20,
        vertical: compact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: serverDivider(context))),
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
                // Refine-look §8.2: above a scene that carries its own pill
                // the header says LIVE with a lamp — a small live dot before
                // the unchanged "Na żywo od 19:40" — instead of a second red
                // pill. The dot and its line flex together, so at 320 px /
                // 200 % text the line wraps beside the dot instead of being
                // cut.
                if (live && liveLamp)
                  ServerLiveLamp(
                    semanticLabel: copy.serverLivePill,
                    label: subtitle,
                    style: subtitleStyle,
                  )
                else
                  // The pill and the live line share one row while they fit
                  // and fall onto two lines when they do not, instead of the
                  // pill holding its intrinsic width unflexed and being cut:
                  // at 320 px / 200 % text the single piece of
                  // contract-backed truth on this screen rendered as
                  // `NA ŻY`, and on board 04 as a 13-px red bar with no word
                  // in it at all.
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
                        style: subtitleStyle,
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

/// The one liveness marker, used only when the channel document says live.
///
/// A keyed alias of the canonical `YoBadge(variant: YoBadgeVariant.live)`:
/// the `server-live-pill` key is the contract every server test counts
/// (header pill, stage marker and the channel row's trailing marker all share
/// it), so it lives here, once, and the badge itself carries no key.
class ServerLivePill extends StatelessWidget {
  const ServerLivePill({required this.label, super.key});
  final String label;

  @override
  Widget build(BuildContext context) => YoBadge(
    key: const ValueKey('server-live-pill'),
    label: label,
    variant: YoBadgeVariant.live,
  );
}

/// The channel header's LIVE lamp (refine-look §8.2), used only in the
/// header above a scene that carries its own pill: a live dot in
/// [AppColors.live], a gap, then the unchanged "Na żywo od 19:40".
///
/// The dot is [dotSize] (8 px) with a [gap] of 6 px at 100 % text and grows
/// with the reader's text size up to [maxDotSize] (12 px, gap 9 px), so at
/// 200 % it still reads as a lamp beside the line rather than as a list
/// bullet.
///
/// The dot pulses exactly like the live badge's own dot — opacity 1 → .55 →
/// 1, three mirrored 1.2 s cycles when it appears, then at rest — so a
/// persistent server screen never ticks forever for a decoration, and it is
/// parked at full opacity under Reduce Motion, accessible navigation or a
/// paused ticker.
///
/// The dot and its line are ONE semantics node, "NA ŻYWO" ([semanticLabel],
/// the same `copy.serverLivePill` the pill says) followed by the line, on
/// the line's own rect: a screen reader stops once, and touch exploration
/// finds the whole line instead of an 8 px dot. Keyed `server-live-lamp`,
/// so "nothing claims liveness" can be asserted for the header beside the
/// `server-live-pill` count.
class ServerLiveLamp extends StatelessWidget {
  const ServerLiveLamp({
    required this.semanticLabel,
    required this.label,
    required this.style,
    super.key = const ValueKey('server-live-lamp'),
  });

  final String semanticLabel;
  final String label;
  final TextStyle style;

  static const double dotSize = 8;
  static const double maxDotSize = 12;
  static const double gap = 6;

  /// The dot's diameter for [textScaler]: [dotSize] scaled with the text,
  /// clamped to [dotSize]…[maxDotSize].
  static double dotFor(TextScaler textScaler, {double fontSize = 12}) =>
      (dotSize * textScaler.scale(fontSize) / fontSize).clamp(
        dotSize,
        maxDotSize,
      );

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final fontSize = style.fontSize ?? 12;
    final dot = dotFor(scaler, fontSize: fontSize);
    // The dot sits on the centre of the FIRST line at any text size, so a
    // line that wraps at 200 % never drags it to the middle of two lines.
    final line = scaler.scale(fontSize) * (style.height ?? 1.2);
    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(
              top: ((line - dot) / 2).clamp(0.0, double.infinity),
            ),
            child: Semantics(
              label: semanticLabel,
              child: ExcludeSemantics(child: _LampDot(size: dot)),
            ),
          ),
          SizedBox(width: gap * dot / dotSize),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

/// The lamp's dot and its bounded pulse (see [ServerLiveLamp]).
class _LampDot extends StatefulWidget {
  const _LampDot({required this.size});
  final double size;

  @override
  State<_LampDot> createState() => _LampDotState();
}

class _LampDotState extends State<_LampDot>
    with SingleTickerProviderStateMixin {
  static const int _cycles = 3;
  static const Duration _cycle = Duration(milliseconds: 1200);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _cycle * _cycles,
    value: 1,
  );
  late final Animation<double> _opacity = TweenSequence<double>([
    for (var i = 0; i < _cycles; i++) ...[
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: .55,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: .55,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
    ],
  ]).animate(_controller);
  bool _pulsed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.decorative(context)) {
      if (!_pulsed) {
        _pulsed = true;
        _controller.forward(from: 0);
      }
    } else {
      _pulsed = false;
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: SizedBox.square(
      dimension: widget.size,
      child: const DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.live,
        ),
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
    this.followRepository,
    this.podcastEpisodeRepository,
    this.shareServer,
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
  final ServerFollowRepository? followRepository;
  final ServerPodcastEpisodeRepository? podcastEpisodeRepository;
  final Future<void> Function(Uri link)? shareServer;
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
        followRepository: followRepository,
        shareServer: shareServer,
        compact: compact,
      );
    }
    if (_podcastStage) {
      return ServerPodcastStage(
        key: ValueKey('server-podcast-${channel.id}'),
        server: server,
        channel: channel,
        session: session,
        episodeRepository: podcastEpisodeRepository,
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
/// Camera and screen sharing are presented here as capabilities that become
/// available after joining; their working controls live in the connected
/// conversation dock.
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
      // Refine-look R4 / W2 at card scale. The card is lit only while the
      // channel document says LIVE and this device has not joined it; once
      // connected it carries the voice accent's edge and corner instead,
      // and every other state (quiet, joining, held) is the plain R2 block.
      final cardState = ServerSessionCardState.of(
        held: server.isHeld,
        live: live,
        here: here,
        connected: session.isConnected,
      );
      return SingleChildScrollView(
        key: const ValueKey('server-channel-content-scroll'),
        padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ServerSessionCard(
              state: cardState,
              accent: ServerIdentity.of(server.type).accent,
              colors: colors,
              // One ignite per live generation of this channel.
              igniteKey: serverLiveGeneration(server, channel),
              padding: EdgeInsets.all(compact ? 16 : 24),
              child: Column(
                children: [
                  // Tiles exist only while the provider reports a roster, so
                  // before a join the scene is the identity orb and nothing
                  // else; there is no readable pre-join presence (G3).
                  if (_video)
                    _VideoSlot(copy: copy, colors: colors, connected: inRoom),
                  if (inRoom) ...[
                    if (_video) const SizedBox(height: 20),
                    ServerVoiceStage(
                      participants: session.participants,
                      colors: colors,
                      compact: compact,
                    ),
                  ] else if (!_video)
                    _Orb(
                      server: server,
                      colors: colors,
                      // The gem is lit by the same fact as the card: a live
                      // generation this device has not joined.
                      live: cardState == ServerSessionCardState.live,
                    ),
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
                    ServerSessionHeld(
                      copy: copy,
                      palette: palette,
                      colors: colors,
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
                              '${copy.serverCamera} · ${copy.serverAvailableAfterJoining}',
                        ),
                        if (channel.mediaMode == ServerMediaMode.meeting)
                          _SoonChip(
                            icon: Icons.screen_share_outlined,
                            label:
                                '${copy.serverShareScreen} · ${copy.serverAvailableAfterJoining}',
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
  /// Board 01 puts the persisted Events module beneath the Salon. The card
  /// opens the real Events V1 board and is drawn only when that channel exists
  /// in this server.
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
      primaryLabel: copy.serverOpenEvents,
      primaryIcon: Icons.event_available_outlined,
      channel: events,
      onOpenChannel: onOpenChannel,
      available: true,
    );
  }
}

/// Which light a session card carries (refine-look R4).
enum ServerSessionCardState {
  /// The plain R2 block: quiet, joining or held.
  quiet,

  /// LIVE and not joined on this device: the W2 recipe at card scale, the
  /// workspace's one emitted light.
  live,

  /// This device is in the conversation: the voice accent's edge and a
  /// corner tint, no glow.
  connected;

  /// The one rule every live surface of a server shares: a held server is
  /// quiet whatever its channel says; this device in the conversation is
  /// [connected]; a live generation this device has not joined is [live];
  /// anything else is [quiet].
  static ServerSessionCardState of({
    required bool held,
    required bool live,
    required bool here,
    required bool connected,
  }) {
    if (held) return ServerSessionCardState.quiet;
    if (here && connected) return ServerSessionCardState.connected;
    if (live && !here) return ServerSessionCardState.live;
    return ServerSessionCardState.quiet;
  }
}

/// The ignite key of a live generation (server, channel and the server's own
/// `startedAt`), or null when the channel is not live. Shared by every live
/// surface of the channel, so a generation ignites once however many of
/// them show it.
String? serverLiveGeneration(Server server, ServerChannel channel) {
  final startedAt = channel.liveness.startedAt;
  if (!channel.liveness.isLive || startedAt == null) return null;
  return '${server.id}/${channel.id}/${startedAt.microsecondsSinceEpoch}';
}

/// A server's live surface (refine-look R4 / W2 at card scale): the session
/// card, the family lounge, the podcast studio — and, as sunken pictures
/// (`elevated: false`), the community stage and the company meeting's
/// shared screen.
///
/// * [ServerSessionCardState.quiet] — R2: the top-lit block fill (or the
///   surface's own [fill]), a 1 px hairline edge and Pearl's shadow pair (a
///   sunken picture casts none).
/// * [ServerSessionCardState.live] — the live tile's base (the identity wash
///   over `surfaceRaised`, or the surface's own [fill]), a corner light in the
///   identity [accent] whose reach is capped at 200 px, the 1 px live rim, a
///   Dark specular top line and the live under-glow at card scale
///   ([cardGlow]), which replaces the block shadow (never both). The first
///   time a live generation ([igniteKey]) is shown, the glow and the corner
///   light fade in over [AppMotion.entrance] and then rest; rebuilds,
///   channel switches and returns never replay it, and a new generation
///   does. Under Reduce Motion it renders at rest.
/// * [ServerSessionCardState.connected] — a 1.5 px `audioAccent` edge and
///   an `audioAccent` corner tint (.12 / .08). No glow.
///
/// Every edge is painted as a foreground, so a state change never moves the
/// content by a pixel. High contrast: a flat `surface` (a sunken picture:
/// `surfaceSunken`) and a 1 px `borderStrong` edge (1.5 px solid live /
/// `audioAccent` in the lit states), no gradient, tint or glow.
class ServerSessionCard extends StatefulWidget {
  const ServerSessionCard({
    required this.state,
    required this.accent,
    required this.colors,
    required this.padding,
    required this.child,
    this.igniteKey,
    this.radius = AppRadius.block,
    this.fill,
    this.elevated = true,
    this.cardKey = const ValueKey('server-session-card'),
    super.key,
  });

  final ServerSessionCardState state;

  /// The template's bright accent ([ServerIdentity.accent]).
  final Color accent;
  final ServerIdentityVisuals colors;
  final EdgeInsets padding;
  final Widget child;

  /// The live generation shown ([serverLiveGeneration]), or null when the
  /// channel is not live.
  final String? igniteKey;

  /// The surface's corner radius: `AppRadius.block` for a card; a picture
  /// keeps its own.
  final BorderRadius radius;

  /// The surface's own fill where it already has one — the podcast studio's
  /// coral wash, a picture's sunken wash. It replaces the block fill and the
  /// live base in every state, so only the edge and the light change.
  final Gradient? fill;

  /// False for a picture sunk into the scene (the community stage, the
  /// meeting's shared screen): no Pearl block shadow, and `surfaceSunken`
  /// under high contrast.
  final bool elevated;

  /// The key of the painted surface itself (its decorations are what the
  /// tests read).
  final Key cardKey;

  /// The connected corner tint's peak (Dark / Pearl): below the lead-block
  /// tint, because the edge already says "connected".
  static const double connectedTintDark = .12;
  static const double connectedTintPearl = .08;

  /// The connected edge.
  static const double connectedEdgeWidth = 1.5;

  /// The live under-glow's geometry at card scale. The live TILE's glow
  /// (blur 32, y 14, spread -12) is sized for a 16:9 thumbnail in a 24 px
  /// gap; under a card twice as tall, in a 16 px phone gap, it filled the
  /// whole gap and tinted the next block's top edge and the gutters. At
  /// blur 20 / y 8 it still reads as light right under the card and is
  /// under 2 % of its colour 16 px below it, where the next block starts.
  static const double cardGlowBlur = 20;
  static const double cardGlowY = 8;
  static const double cardGlowSpread = -12;

  /// The live under-glow at card scale: the palette's `liveGlow` in the
  /// geometry above, plus Pearl's plum drop exactly as the live tile has it.
  static List<BoxShadow> cardGlow(AppPalette palette) {
    final tile = AppFinish.liveGlow(palette);
    if (tile.isEmpty) return tile;
    return [
      BoxShadow(
        color: tile.first.color,
        blurRadius: cardGlowBlur,
        offset: const Offset(0, cardGlowY),
        spreadRadius: cardGlowSpread,
      ),
      ...tile.skip(1),
    ];
  }

  /// Forgets which live generations have already ignited (tests only).
  @visibleForTesting
  static void debugResetIgnitions() => _ignitedSessions.clear();

  @override
  State<ServerSessionCard> createState() => _ServerSessionCardState();
}

/// The live generations whose session card has already ignited. App-lifetime
/// on purpose: the scene is rebuilt on every session tick and re-mounted on
/// every channel switch, and neither may replay the ignite. Bounded: only the
/// most recent generations are remembered.
final Set<String> _ignitedSessions = <String>{};
const int _ignitedMemory = 32;

class _ServerSessionCardState extends State<ServerSessionCard>
    with SingleTickerProviderStateMixin {
  AnimationController? _ignite;
  Animation<double> _light = kAlwaysCompleteAnimation;
  bool _checked = false;

  bool get _lit => widget.state == ServerSessionCardState.live;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    _maybeIgnite();
  }

  @override
  void didUpdateWidget(covariant ServerSessionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.igniteKey != widget.igniteKey ||
        oldWidget.state != widget.state) {
      _maybeIgnite();
    }
  }

  /// First sight of a lit generation fades its light in once.
  void _maybeIgnite() {
    final key = widget.igniteKey;
    if (!_lit || key == null || _ignitedSessions.contains(key)) return;
    _ignitedSessions.add(key);
    if (_ignitedSessions.length > _ignitedMemory) {
      _ignitedSessions.remove(_ignitedSessions.first);
    }
    if (!AppMotion.decorative(context)) {
      _light = kAlwaysCompleteAnimation;
      return;
    }
    final controller = _ignite ??= AnimationController(
      vsync: this,
      duration: AppMotion.entrance,
    );
    _light = CurvedAnimation(
      parent: controller,
      curve: AppMotion.entranceCurve,
    );
    controller.forward(from: 0);
  }

  @override
  void dispose() {
    _ignite?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final live = _lit;
    final connected = widget.state == ServerSessionCardState.connected;
    final radius = widget.radius;
    final own = widget.fill;

    final BoxDecoration fill;
    if (highContrast) {
      fill = BoxDecoration(
        color: widget.elevated ? palette.surface : palette.surfaceSunken,
        borderRadius: radius,
      );
    } else if (own != null) {
      fill = BoxDecoration(
        gradient: own,
        borderRadius: radius,
        // The live under-glow replaces the block shadow (never both).
        boxShadow: live
            ? const <BoxShadow>[]
            : AppFinish.blockShadows(palette, elevated: widget.elevated),
      );
    } else if (live) {
      fill = BoxDecoration(
        color: Color.alphaBlend(widget.colors.cardWash, palette.surfaceRaised),
        borderRadius: radius,
      );
    } else {
      fill = AppFinish.blockFill(palette, radius: radius);
    }

    final Border edge;
    if (live) {
      edge = AppFinish.liveRim(palette, highContrast: highContrast);
    } else if (connected) {
      edge = Border.all(
        color: palette.audioAccent,
        width: ServerSessionCard.connectedEdgeWidth,
      );
    } else {
      edge = AppFinish.blockEdge(palette, highContrast: highContrast);
    }

    final specular = live
        ? AppFinish.liveSpecular(palette, highContrast: highContrast)
        : null;
    final tintAlpha = palette.isDark
        ? ServerSessionCard.connectedTintDark
        : ServerSessionCard.connectedTintPearl;

    final card = AnimatedContainer(
      key: widget.cardKey,
      duration: AppMotion.resolve(context, AppMotion.quick),
      curve: AppMotion.standardCurve,
      decoration: fill,
      foregroundDecoration: BoxDecoration(borderRadius: radius, border: edge),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          // The content keeps the card's full width (a loose Stack would let
          // the centred column shrink to its widest line).
          fit: StackFit.passthrough,
          children: [
            if (live && !highContrast)
              Positioned.fill(
                child: IgnorePointer(
                  child: FadeTransition(
                    opacity: _light,
                    child: LayoutBuilder(
                      builder: (context, constraints) => DecoratedBox(
                        key: const ValueKey('server-session-corner'),
                        decoration: BoxDecoration(
                          gradient: AppFinish.liveCorner(
                            widget.accent,
                            palette,
                            shortestSide: constraints.biggest.shortestSide,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (connected && !highContrast)
              PositionedDirectional(
                key: const ValueKey('server-session-tint'),
                top: AppFinish.cornerTintTop,
                end: AppFinish.cornerTintEnd,
                width: AppFinish.cornerTintSize,
                height: AppFinish.cornerTintSize,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          palette.audioAccent.withValues(alpha: tintAlpha),
                          palette.audioAccent.withValues(alpha: 0),
                        ],
                        stops: const [0, .68],
                      ),
                    ),
                  ),
                ),
              ),
            if (specular != null)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 1,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: specular),
                  ),
                ),
              ),
            // The edge is a foreground; one extra pixel keeps the content
            // exactly where the old in-layout 1 px border left it.
            Padding(
              padding: widget.padding + const EdgeInsets.all(1),
              child: widget.child,
            ),
          ],
        ),
      ),
    );
    if (!live || highContrast) return card;
    // The under-glow is its own layer behind the card, so the card's clip
    // never cuts it, the ignite fades only the light (never the card) and
    // it replaces the block shadow rather than adding one.
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: FadeTransition(
              opacity: _light,
              child: DecoratedBox(
                key: const ValueKey('server-session-glow'),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: ServerSessionCard.cardGlow(palette),
                ),
              ),
            ),
          ),
        ),
        card,
      ],
    );
  }
}

/// The session's identity orb, 112 px (the size and the scene around it are
/// unchanged).
///
/// LIVE and not joined: the template's lit gem
/// ([ServerIdentityVisuals.liveOrbGradient]) with the symbol in its own ink
/// and a 1 px white @ .14 rim — no glow and no pulse of its own (the badge's
/// dot already pulses). Otherwise the unlit identity glass.
class _Orb extends StatelessWidget {
  const _Orb({required this.server, required this.colors, required this.live});
  final Server server;
  final ServerIdentityVisuals colors;
  final bool live;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('server-session-orb'),
    width: 112,
    height: 112,
    decoration: serverOrbDecoration(context, colors, live: live),
    child: Center(
      child: ServerTypeSymbol(
        type: server.type,
        color: live ? colors.onLiveOrb : colors.foreground,
        size: 46,
      ),
    ),
  );
}

/// The decoration of an identity disc (refine-look §8.2): the lit gem when
/// [live]; the unlit identity glass otherwise (the quiet orb, the module
/// empty state) — [ServerIdentityVisuals.unlitGradient], its edge and
/// Pearl's block shadow. High contrast keeps the gem's deeper stop flat (its
/// ink is measured on it), and gives both a `borderStrong` edge with no
/// gradient or shadow.
BoxDecoration serverOrbDecoration(
  BuildContext context,
  ServerIdentityVisuals colors, {
  bool live = false,
}) {
  final palette = context.appPalette;
  final highContrast = MediaQuery.highContrastOf(context);
  if (live) {
    return BoxDecoration(
      shape: BoxShape.circle,
      color: highContrast ? colors.liveOrbGradient.colors.last : null,
      gradient: highContrast ? null : colors.liveOrbGradient,
      border: Border.all(
        color: highContrast
            ? palette.borderStrong
            : AppColors.white.withValues(alpha: .14),
      ),
    );
  }
  return BoxDecoration(
    shape: BoxShape.circle,
    color: highContrast ? palette.surface : null,
    gradient: highContrast ? null : colors.unlitGradient,
    border: Border.all(
      color: highContrast ? palette.borderStrong : colors.unlitEdge,
    ),
    boxShadow: AppFinish.blockShadows(palette, highContrast: highContrast),
  );
}

class _VideoSlot extends StatelessWidget {
  const _VideoSlot({
    required this.copy,
    required this.colors,
    required this.connected,
  });
  final AppLocalizations copy;
  final ServerIdentityVisuals colors;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return LayoutBuilder(
      builder: (context, constraints) => ConstrainedBox(
        // Keep the normal preview at 16:9, while allowing accessibility text
        // to make the empty state taller instead of overflowing a fixed frame.
        constraints: BoxConstraints(minHeight: constraints.maxWidth * 9 / 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            color: palette.surfaceSunken,
            borderRadius: AppRadius.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.videocam_off_outlined,
                color: colors.foreground,
                size: 44,
              ),
              const SizedBox(height: 8),
              Text(
                connected
                    ? copy.serverStageNoVideo
                    : '${copy.serverVideoPreview} · ${copy.serverAvailableAfterJoining}',
                textAlign: TextAlign.center,
                style: AppTypography.labelMedium.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
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

/// The word a join control uses for this channel in this state.
///
/// One switch for every surface that offers the join — the scene's
/// [ServerJoinAction] and the channel row in `ServerPanel` — so a stage the
/// viewer may not start is silent in both. Null means no join is offered: a
/// listener cannot begin a stage generation (`startSession` needs moderator
/// power there), so no control is drawn to fail.
String? serverJoinLabel(
  AppLocalizations copy,
  ServerChannel channel, {
  required bool live,
  ServerMemberRole? role,
}) {
  // A video stage is watched as well as heard — `mediaConfiguration()` gives
  // board 02's `Scena LIVE` `broadcast/video` and the grant a camera source —
  // so its join says so. The podcast's audio stage keeps `Słuchaj`.
  final watch = channel.mediaMode == ServerMediaMode.video;
  return switch (channel.kind) {
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
}

/// The glyph beside [serverJoinLabel].
IconData serverJoinIcon(ServerChannel channel, {required bool live}) =>
    channel.kind == ServerChannelKind.stage && live
    ? (channel.mediaMode == ServerMediaMode.video
          ? Icons.live_tv_rounded
          : Icons.headphones_rounded)
    : Icons.mic_none_rounded;

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
    final label = serverJoinLabel(copy, channel, live: live, role: role);
    if (label == null) {
      // A listener cannot start a stage generation (`startSession` needs
      // moderator power there), so no button is drawn to fail.
      return Text(
        copy.serverStageWaiting,
        textAlign: TextAlign.center,
        style: AppTypography.bodySmall.copyWith(color: palette.textSecondary),
      );
    }
    // The workspace's one lifted action (refine-look R5, identity variant):
    // the template's CTA gradient, the lift in its own colour. It is still a
    // FilledButton keyed `server-join`, and `cta` stays its reported fill —
    // the colour the [onCta] focus ring is measured against, and the stop
    // the gradient only ever moves away from.
    return YoGradientFilledButton(
      buttonKey: const ValueKey('server-join'),
      onPressed: onJoin,
      gradient: colors.ctaGradient,
      fill: colors.cta,
      foreground: colors.onCta,
      liftColor: colors.cta,
      minimumSize: fullWidth ? const Size.fromHeight(56) : const Size(48, 48),
      // FilledButton.icon's own asymmetric padding, scaled with the text
      // exactly as it scales it.
      padding: serverIconActionPadding(context),
      style: fullWidth
          ? const ButtonStyle(
              textStyle: WidgetStatePropertyAll(AppTypography.titleSmall),
            )
          : null,
      icon: Icon(serverJoinIcon(channel, live: live), size: 18),
      child: Text(label),
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
                    style: FilledButton.styleFrom(
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
                  copy.serverReconnectingFor(session.reauthorization),
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

/// Fallback for a module kind that has no mounted product surface. Persisted
/// Events, Episodes, Family tools, Whiteboard and Company Files are routed by
/// the workspace before this fallback is considered.
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
        // Refine-look R2: the neutral block, its orb the unlit identity
        // glass.
        decoration: AppFinish.block(
          palette,
          highContrast: MediaQuery.highContrastOf(context),
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
                decoration: serverOrbDecoration(context, colors),
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
