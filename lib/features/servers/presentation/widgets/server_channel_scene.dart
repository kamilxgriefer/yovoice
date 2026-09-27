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
import 'package:yovoice/shared/widgets/buttons/yo_action_focus_indicator.dart';

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
                // Refine-look §8.2: above a media scene the header says LIVE
                // with a lamp — a small pulsing dot before the unchanged
                // "Na żywo od 19:40" — instead of a second red pill; the
                // pill itself stays on the scene's card and on the channel
                // rows. The lamp and its line flex together, so at 320 px /
                // 200 % text the line wraps under the dot rather than being
                // cut.
                if (live)
                  ServerLiveLamp(
                    semanticLabel: copy.serverLivePill,
                    label: subtitle,
                    style: subtitleStyle,
                  )
                else
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle,
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
/// the `server-live-pill` key is the contract every server test counts (the
/// session card's pill, the stage marker and the channel row's trailing
/// marker all share it; the channel header says LIVE with
/// [ServerLiveLamp]), so it lives here, once, and the badge itself carries
/// no key.
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

/// The channel header's LIVE lamp (refine-look §8.2): an 8 px dot in
/// [AppColors.live] — pulsing three bounded 1.2 s cycles when it appears, like
/// the badge's own dot, and still under Reduce Motion — then 6 px, then the
/// unchanged "Na żywo od 19:40".
///
/// The dot is the marker and is announced as [semanticLabel] (the same
/// `copy.serverLivePill` the pill says); the line keeps its own text node. The
/// widget carries `server-live-lamp`, so "nothing claims liveness" can still
/// be asserted for the header next to the `server-live-pill` count.
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
  static const double gap = 6;

  @override
  Widget build(BuildContext context) {
    // The dot sits on the centre of the FIRST line at any text size, so a
    // line that wraps at 200 % never drags it down to the middle of two.
    final line =
        MediaQuery.textScalerOf(context).scale(style.fontSize ?? 12) *
        (style.height ?? 1.2);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: ((line - dotSize) / 2).clamp(0, 99)),
          child: Semantics(
            label: semanticLabel,
            child: const ExcludeSemantics(child: _LampDot(size: dotSize)),
          ),
        ),
        const SizedBox(width: gap),
        Flexible(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

/// The lamp's dot: opacity 1 → .55 → 1, three mirrored 1.2 s cycles when it
/// appears, then at rest — the live badge's bounded pulse, so a persistent
/// server screen never ticks forever for a decoration and every surface
/// still settles. Parked at 1 whenever decorative motion is off.
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

/// A server's one labelled CTA with the refine-look R5 finish: an identity
/// (or brand) gradient laid on the button through `backgroundBuilder`, and
/// the rail's tight coloured lift ([AppFinish.actionLift]) on an outer box so
/// the button's own clip never cuts it.
///
/// It is the same `YoGradientFilledButton` recipe, kept here as a real
/// [FilledButton] that carries the caller's key because the servers slice
/// addresses `server-join`, `server-public-join` and `servers-create` as a
/// [FilledButton] (its `onPressed`, its `enabled` and — for the WCAG 1.4.11
/// focus-ring test — its `backgroundColor`). [fill] is therefore still the
/// reported and underlying colour; the gradient's stops only ever move away
/// from [foreground], so the [serverFocusRing] measured on [fill] holds on
/// both stops.
///
/// States: hover and press wash [foreground] at .06 / .10 and move the lift
/// (hover .40 / blur 22, pressed y 3 at 60 %); keyboard focus paints the
/// 2 px [serverFocusRing] as a foreground over the gradient (the style's
/// `side` alone would sit under it, unseen), and on a light canvas or under
/// high contrast a 2 px `palette.focus` band joins it just outside the
/// stadium — the same two-tone indicator as `YoGradientFilledButton`
/// ([YoActionFocusIndicatorPainter]); disabled is the theme's flat
/// sunken fill with no gradient and no lift. [lifted] false keeps the
/// gradient without the lift where another action already owns the screen's
/// one lift. High contrast keeps the gradient (the fill IS the control) and
/// drops the lift. Never for repeated, list, retry or tonal actions.
class ServerGradientFilledButton extends StatefulWidget {
  const ServerGradientFilledButton({
    required this.buttonKey,
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.gradient,
    required this.fill,
    required this.foreground,
    this.liftColor,
    this.lifted = true,
    this.minimumSize = const Size(48, 48),
    this.textStyle,
    super.key,
  });

  /// The key of the [FilledButton] itself.
  final Key buttonKey;
  final VoidCallback? onPressed;
  final Widget icon;
  final Widget label;
  final Gradient gradient;

  /// The solid colour under the gradient, reported as `backgroundColor`.
  final Color fill;
  final Color foreground;

  /// Defaults to [fill].
  final Color? liftColor;
  final bool lifted;
  final Size minimumSize;
  final TextStyle? textStyle;

  @override
  State<ServerGradientFilledButton> createState() =>
      _ServerGradientFilledButtonState();
}

class _ServerGradientFilledButtonState
    extends State<ServerGradientFilledButton> {
  final _states = WidgetStatesController();
  bool _hovered = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _states.addListener(_statesChanged);
  }

  @override
  void dispose() {
    _states
      ..removeListener(_statesChanged)
      ..dispose();
    super.dispose();
  }

  // Only hover and press move the lift; focus and disabled paint nothing
  // here, so they never rebuild this widget.
  void _statesChanged() {
    if (!mounted) return;
    final hovered = _states.value.contains(WidgetState.hovered);
    final pressed = _states.value.contains(WidgetState.pressed);
    if (hovered == _hovered && pressed == _pressed) return;
    setState(() {
      _hovered = hovered;
      _pressed = pressed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final lift =
        !enabled || !widget.lifted || MediaQuery.highContrastOf(context)
        ? const <BoxShadow>[]
        : AppFinish.actionLift(
            widget.liftColor ?? widget.fill,
            hovered: _hovered,
            pressed: _pressed,
          );
    final ink = widget.foreground;
    // Pearl and high contrast: the `palette.focus` band just outside the ink
    // band, as `YoGradientFilledButton` draws it — the ink band alone melts
    // into a light page. Painted over the button and outside its clip, and
    // always in the tree, so focus moves and remounts nothing; Dark keeps
    // the ink band below alone.
    final halo = enabled
        ? YoActionFocusIndicatorPainter.haloFor(
            context.appPalette,
            highContrast: MediaQuery.highContrastOf(context),
          )
        : null;
    return AnimatedContainer(
      duration: AppMotion.resolve(context, AppMotion.quick),
      curve: AppMotion.standardCurve,
      decoration: ShapeDecoration(shape: const StadiumBorder(), shadows: lift),
      child: CustomPaint(
        foregroundPainter: YoActionFocusIndicatorPainter(
          states: _states,
          shape: const StadiumBorder(),
          edge: halo == null ? null : ink,
          halo: halo,
          textDirection: Directionality.maybeOf(context),
        ),
        child: FilledButton.icon(
          key: widget.buttonKey,
          onPressed: widget.onPressed,
          statesController: _states,
          // FilledButton defaults to Clip.none, which would let the gradient
          // `Ink` paint as a rectangle past the stadium.
          clipBehavior: Clip.antiAlias,
          style:
              FilledButton.styleFrom(
                backgroundColor: widget.fill,
                foregroundColor: ink,
                minimumSize: widget.minimumSize,
                textStyle: widget.textStyle,
                elevation: 0,
                shadowColor: Colors.transparent,
              ).copyWith(
                side: serverFocusRing(ink),
                overlayColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.pressed)) {
                    return ink.withValues(alpha: .10);
                  }
                  if (states.contains(WidgetState.hovered)) {
                    return ink.withValues(alpha: .06);
                  }
                  return null;
                }),
                backgroundBuilder: enabled
                    ? (context, states, child) => Ink(
                        // Keep `color` null behind the gradient (see
                        // yo_button.dart).
                        decoration: BoxDecoration(gradient: widget.gradient),
                        // The button's own `Material` paints `side` UNDER its
                        // child (`borderOnForeground: false`), where this
                        // opaque gradient covers it. The focus ring is
                        // therefore drawn again here, as a foreground over the
                        // gradient; a `DecoratedBox` adds no padding, so focus
                        // never moves the label.
                        child: DecoratedBox(
                          key: const ValueKey('server-gradient-focus-ring'),
                          position: DecorationPosition.foreground,
                          decoration: ShapeDecoration(
                            shape: StadiumBorder(
                              side:
                                  serverFocusRing(ink).resolve(states) ??
                                  BorderSide.none,
                            ),
                          ),
                          child: child,
                        ),
                      )
                    : null,
              ),
          icon: widget.icon,
          label: widget.label,
        ),
      ),
    );
  }
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
      // connected it carries the voice accent's edge and corner instead, and
      // every other state is the plain R2 block. A held root is quiet.
      final cardState = server.isHeld
          ? ServerSessionCardState.quiet
          : here && session.isConnected
          ? ServerSessionCardState.connected
          : live && !here
          ? ServerSessionCardState.live
          : ServerSessionCardState.quiet;
      final inset = compact ? AppSpacing.md : AppSpacing.lg;
      final scroll = SingleChildScrollView(
        key: const ValueKey('server-channel-content-scroll'),
        padding: EdgeInsets.all(inset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ServerSessionCard(
              state: cardState,
              accent: ServerIdentity.of(server.type).accent,
              colors: colors,
              igniteKey:
                  cardState == ServerSessionCardState.live &&
                      channel.liveness.startedAt != null
                  ? '${server.id}/${channel.id}/'
                        '${channel.liveness.startedAt!.microsecondsSinceEpoch}'
                  : null,
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
      // Content that scrolls past the scene's end dissolves into the canvas
      // over the last [inset] px instead of stopping on a hard line just
      // above the conversation bar. The fade is exactly as tall as the
      // scroll padding, so at the end of the scroll it lies over empty
      // padding and never dims the last card. High contrast keeps the plain
      // edge (no decorative gradient); the scroller keeps its place in the
      // tree either way.
      return Stack(
        fit: StackFit.passthrough,
        children: [
          scroll,
          if (!MediaQuery.highContrastOf(context))
            PositionedDirectional(
              start: 0,
              end: 0,
              bottom: 0,
              height: inset,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('server-session-edge-fade'),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        palette.background.withValues(alpha: 0),
                        palette.background,
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
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
  /// The plain R2 block: quiet, held, or joining.
  quiet,

  /// LIVE and not joined here: the W2 recipe at card scale.
  live,

  /// This device is in the conversation: the voice accent's edge and a
  /// corner tint, no glow.
  connected,
}

/// The session scene's card.
///
/// * [ServerSessionCardState.quiet] — R2: the top-lit block fill, a 1 px
///   hairline edge and Pearl's shadow pair.
/// * [ServerSessionCardState.live] — W2 at card scale: the live tile's base
///   (the identity wash over `surfaceRaised`), a corner light in the
///   identity [accent] whose reach is capped at 200 px, the 1 px live rim, a
///   Dark specular top line and the live under-glow — which replaces the
///   block shadow. This is the workspace's one emitted light.
/// * [ServerSessionCardState.connected] — a 1.5 px `audioAccent` edge and an
///   `audioAccent` corner tint (.12 / .08). No glow.
///
/// **Ignite (W2).** The first time a live generation ([igniteKey]: server,
/// channel and `startedAt`) is seen, the glow and the corner light fade in
/// over [AppMotion.entrance] and then rest. Rebuilds, a channel switch and a
/// return to the server never replay it; a new `startedAt` is a new key and
/// lights once more. No translate, scale or loop, and nothing at all under
/// Reduce Motion, accessible navigation or a paused ticker.
///
/// Edges are painted as a foreground and the tree is the same in every
/// state, so a state change (a join) never moves the content by a pixel nor
/// remounts it — keyboard focus stays where it was. High contrast: a flat
/// `surface`, a 1 px `borderStrong` edge (1.5 px solid live / `audioAccent`
/// in the lit states), no light.
class ServerSessionCard extends StatefulWidget {
  const ServerSessionCard({
    required this.state,
    required this.accent,
    required this.colors,
    required this.padding,
    required this.child,
    this.igniteKey,
    super.key,
  });

  final ServerSessionCardState state;

  /// The template's bright accent ([ServerIdentity.accent]).
  final Color accent;
  final ServerIdentityVisuals colors;
  final EdgeInsets padding;
  final Widget child;

  /// Names the live generation on screen (`server/channel/startedAt`), so its
  /// light ignites once per generation. Null never ignites.
  final String? igniteKey;

  /// The connected corner tint's peak (Dark / Pearl), below the lead-block
  /// tint because the edge already says "connected".
  static const double connectedTintDark = .12;
  static const double connectedTintPearl = .08;

  /// Forgets which live generations have already ignited (tests only).
  @visibleForTesting
  static void debugResetIgnitions() => _ignited.clear();

  /// App-lifetime on purpose, like Start's live tiles: the workspace is
  /// rebuilt on every channel switch and remounted on every return, and
  /// neither may replay the light. Bounded to the most recent generations.
  static final Set<String> _ignited = <String>{};
  static const int _ignitedMemory = 32;

  /// Whether [key] is seen for the first time (and remembers it).
  static bool _firstSight(String key) {
    if (_ignited.contains(key)) return false;
    _ignited.add(key);
    if (_ignited.length > _ignitedMemory) _ignited.remove(_ignited.first);
    return true;
  }

  @override
  State<ServerSessionCard> createState() => _ServerSessionCardState();
}

class _ServerSessionCardState extends State<ServerSessionCard>
    with SingleTickerProviderStateMixin {
  AnimationController? _ignite;
  CurvedAnimation? _igniteCurve;
  Animation<double> _light = kAlwaysCompleteAnimation;
  bool _checked = false;

  bool get _live => widget.state == ServerSessionCardState.live;

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
    if (widget.igniteKey != oldWidget.igniteKey ||
        widget.state != oldWidget.state) {
      _maybeIgnite();
    }
  }

  void _maybeIgnite() {
    final key = widget.igniteKey;
    if (!_live || key == null || !ServerSessionCard._firstSight(key)) return;
    if (!AppMotion.decorative(context)) {
      _light = kAlwaysCompleteAnimation;
      return;
    }
    // One controller and one curve for the card's lifetime, reused by every
    // later generation, so an ignition never leaves a listener behind.
    final controller = _ignite ??= AnimationController(
      vsync: this,
      duration: AppMotion.entrance,
    );
    _light = _igniteCurve ??= CurvedAnimation(
      parent: controller,
      curve: AppMotion.entranceCurve,
    );
    controller.forward(from: 0);
  }

  @override
  void dispose() {
    _igniteCurve?.dispose();
    _ignite?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final duration = AppMotion.resolve(context, AppMotion.quick);
    final live = _live;
    final connected = widget.state == ServerSessionCardState.connected;

    final BoxDecoration fill;
    if (highContrast) {
      fill = BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.block,
      );
    } else if (live) {
      fill = BoxDecoration(
        color: Color.alphaBlend(widget.colors.cardWash, palette.surfaceRaised),
        borderRadius: AppRadius.block,
      );
    } else {
      fill = AppFinish.blockFill(palette);
    }

    final Border edge;
    if (live) {
      edge = AppFinish.liveRim(palette, highContrast: highContrast);
    } else if (connected) {
      edge = Border.all(color: palette.audioAccent, width: 1.5);
    } else {
      edge = AppFinish.blockEdge(palette, highContrast: highContrast);
    }

    final lit = live && !highContrast;
    final specular = live
        ? AppFinish.liveSpecular(palette, highContrast: highContrast)
        : null;
    final tintAlpha = palette.isDark
        ? ServerSessionCard.connectedTintDark
        : ServerSessionCard.connectedTintPearl;

    final card = AnimatedContainer(
      key: const ValueKey('server-session-card'),
      duration: duration,
      curve: AppMotion.standardCurve,
      decoration: fill,
      foregroundDecoration: BoxDecoration(
        borderRadius: AppRadius.block,
        border: edge,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.block,
        child: Stack(
          // The content keeps the card's full width (a loose Stack would let
          // the centred column shrink to its widest line).
          fit: StackFit.passthrough,
          children: [
            if (lit)
              Positioned.fill(
                key: const ValueKey('server-session-corner-layer'),
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
                key: const ValueKey('server-session-specular'),
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
              key: const ValueKey('server-session-card-content'),
              padding: widget.padding + const EdgeInsets.all(1),
              child: widget.child,
            ),
          ],
        ),
      ),
    );
    // The under-glow is its own layer behind the card, so the card's clip
    // never cuts it and it replaces the block shadow rather than adding one.
    // The layer is there in every state (empty when not lit), so the card
    // itself never changes its place in the tree.
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: FadeTransition(
              opacity: _light,
              child: DecoratedBox(
                key: lit ? const ValueKey('server-session-glow') : null,
                decoration: BoxDecoration(
                  borderRadius: AppRadius.block,
                  boxShadow: lit
                      ? AppFinish.liveGlow(palette)
                      : const <BoxShadow>[],
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

/// The session's identity orb, 112 px.
///
/// LIVE (and not joined): the template's lit gem
/// ([ServerIdentityVisuals.liveOrbGradient]) with the symbol in its own ink
/// and a 1 px white @ .14 rim — no glow and no pulse, the badge's dot
/// already pulses. Otherwise the "unlit" identity glass.
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

/// The decoration of an identity disc: the lit gem when [live], the unlit
/// identity glass otherwise (quiet orbs, the module empty state). High
/// contrast keeps the gem's deeper stop flat (its ink is measured on it) and
/// gives both a `borderStrong` edge, with no gradient or shadow.
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
    // The workspace's one lifted action (refine-look R5, identity variant).
    return ServerGradientFilledButton(
      buttonKey: const ValueKey('server-join'),
      onPressed: onJoin,
      gradient: colors.ctaGradient,
      fill: colors.cta,
      foreground: colors.onCta,
      minimumSize: fullWidth ? const Size.fromHeight(56) : const Size(48, 48),
      textStyle: fullWidth ? AppTypography.titleSmall : null,
      icon: Icon(serverJoinIcon(channel, live: live), size: 18),
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
