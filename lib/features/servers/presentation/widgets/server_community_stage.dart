import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:share_plus/share_plus.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_member_role.dart';
import '../../data/models/server_session_hand.dart';
import '../../data/server_links.dart';
import '../../data/services/server_follow_service.dart';
import '../../data/services/server_broadcast_ingress_service.dart';
import '../../data/services/server_media_connector.dart';
import '../../data/services/server_session_controller.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';
import 'server_channel_scene.dart';
import 'server_local_tabs.dart';
import 'server_module_card.dart';
import 'server_obs_broadcast_sheet.dart';
import 'server_panel.dart';
import 'server_scrolling_details.dart';
import 'server_hand_status.dart';
import 'server_stage_participant_menu.dart';
import 'server_stage_requests.dart';

/// `Scena LIVE` — board 02's centre, the community template's broadcast.
///
/// The channel is `stage / broadcast / video`, so video *receive* is real:
/// once the person has joined through the reviewed token path the 16:9 scene
/// renders whatever screen-share or camera track the provider actually
/// reports. Everything the board shows that has no contract is absent rather
/// than invented:
///
/// * **no viewer, listener or participant count** anywhere — the liveness
///   projection is `{schemaVersion, isLive, startedAt}` and there is no
///   presence writer (contract G6), so the pill says `NA ŻYWO` and the line
///   beside it says *since when*, never *how many*;
/// * **no pre-join host row and no avatar stack** — `channelSessions` and the
///   V1 room anchor are not client-readable (G2/G3). The people named on the
///   scene are the ones the provider reports to this device, and they appear
///   only after joining;
/// * **no reaction counters** — nothing counts a reaction, so no reaction is
///   drawn;
/// * **no episode, recording or transport row** — a live generation has no
///   seek, and recording has no contract at all;
/// * following is backed by the community-follow projection and sharing emits
///   the canonical Server link, so both actions have a real destination;
/// * a host/invitee with a camera source can publish video through the same
///   joined provider session.
///
/// `Poproś o głos` is real: it calls the registered `setServerSessionHandV1`,
/// and only from inside a joined session, because the callable refuses
/// anybody without a participant document and refuses the generation's host.
/// The answer to that call is the only state shown — the participant document
/// itself is not readable, so nothing here guesses at a queue.
/// A joined host or server moderator can also move a reported participant
/// between stage and audience or send an explicit moderator-mute command. The
/// backend re-proves hierarchy, and the client never infers either stored mute
/// flag from provider audio state.
///
/// The ordinary `Salon głosowy` of the same server is **not** this scene: it
/// is a `voice` channel and stays the conversation the shell already draws.
class ServerCommunityStage extends StatefulWidget {
  const ServerCommunityStage({
    required this.server,
    required this.channel,
    required this.session,
    this.role,
    this.channels = const [],
    this.onOpenChannel,
    this.followRepository,
    this.broadcastRepository,
    this.shareServer,
    this.chat,
    this.onOpenChannels,
    this.compact = false,
    super.key,
  });

  final Server server;
  final ServerChannel channel;
  final ServerSessionController session;
  final ServerMemberRole? role;

  /// The server's own channels, so the next-event card can offer the real
  /// `Wydarzenia` channel instead of a module that does not exist.
  final List<ServerChannel> channels;
  final ValueChanged<ServerChannel>? onOpenChannel;
  final ServerFollowRepository? followRepository;
  final ServerBroadcastIngressRepository? broadcastRepository;
  final Future<void> Function(Uri link)? shareServer;

  /// Phone only: the live chat that sits under the local tabs, and the way
  /// into the channel list. Both null at tablet and desktop width, where the
  /// shell owns the tab strip and the context panel.
  final Widget? chat;
  final VoidCallback? onOpenChannels;

  /// Phone: the video leads, the conversation fills the rest of the surface
  /// and the primary action is pinned to the bottom of the scene.
  final bool compact;

  /// A 16:9 scene on a 1920 px desktop would be over a thousand pixels tall
  /// and push the title, the actions and the event card off screen, so the
  /// stage is bounded and centred instead of filling the column.
  static const maxStageHeight = 420.0;

  @override
  State<ServerCommunityStage> createState() => _ServerCommunityStageState();
}

class _ServerCommunityStageState extends State<ServerCommunityStage> {
  /// The last answer `setServerSessionHandV1` gave, with the generation it
  /// answered for. A hand belongs to one generation: when the session ends
  /// or a new one starts, this stops applying and the control returns to
  /// "ask", which is exactly what the backend would say.
  bool _raised = false;
  String? _raisedSessionId;

  /// [ServerSessionController.ownParticipantVersion] when that receipt
  /// arrived: a document snapshot newer than it outranks the receipt.
  int? _receiptVersion;
  bool _busy = false;
  Object? _error;
  bool _followBusy = false;
  bool _shareBusy = false;
  bool? _followOverride;
  Object? _actionError;
  ServerBroadcastIngressRepository? _defaultBroadcastRepository;

  /// The phone's local tab when the surface is too small to stack the
  /// conversation under the broadcast: 0 = what this stage is, 1 = the
  /// conversation. Unused while both fit at once.
  int _tab = 0;

  ServerChannel? get _events => widget.channels
      .where((channel) => channel.kind == ServerChannelKind.events)
      .firstOrNull;

  bool get _here => widget.session.isIn(widget.channel.id);

  bool get _inRoom =>
      _here &&
      (widget.session.phase == ServerSessionPhase.connected ||
          widget.session.phase == ServerSessionPhase.reconnecting);

  /// The generation this device is actually in, or null when there is none.
  String? get _sessionId =>
      _inRoom ? widget.session.connection?.sessionId : null;

  /// The host of a generation never queues for its own stage, and the
  /// callable says so; a guest is already on the stage (every participant of
  /// a non-broadcast Community stage starts as one), so there is nothing an
  /// Approve could give them. The control is drawn for neither, nor while a
  /// role change is moving this person onto a new token.
  bool get _canRaiseHand =>
      _sessionId != null &&
      widget.session.reauthorization == null &&
      widget.session.connection?.sessionRole != 'host' &&
      widget.session.connection?.sessionRole != 'guest';

  /// The receipt of this person's own press until their own participant
  /// document says otherwise (`server_hand_status.dart`).
  ({bool up, ServerHandDecision? decision}) get _ownHand => serverOwnHand(
    session: widget.session,
    sessionId: _sessionId,
    receiptRaised: _raised,
    receiptSessionId: _raisedSessionId,
    receiptVersion: _receiptVersion,
  );

  bool get _handIsUp => _ownHand.up;

  /// The active picture: a remote shared screen first, then a remote camera,
  /// because a stage is watched rather than self-viewed. Local sources are
  /// used only when this device is the publisher.
  ServerMediaParticipant? get _publisher {
    final people = widget.session.participants;
    for (final person in people) {
      if (!person.isLocal && person.isSharingScreen) return person;
    }
    for (final person in people) {
      if (person.isSharingScreen) return person;
    }
    for (final person in people) {
      if (!person.isLocal && person.hasCamera) return person;
    }
    for (final person in people) {
      if (person.hasCamera) return person;
    }
    return null;
  }

  String? _roleOf(ServerMediaParticipant person) => person.isLocal
      ? (widget.session.connection?.sessionRole ?? person.sessionRole)
      : person.sessionRole;

  Widget? _participantMenu(
    ServerMediaParticipant person, {
    bool compact = false,
  }) {
    final sessionId = _sessionId;
    final viewerSessionRole = widget.session.connection?.sessionRole;
    if (sessionId == null ||
        (viewerSessionRole != 'host' && !(widget.role?.canModerate ?? false))) {
      return null;
    }
    return ServerStageParticipantMenu(
      repository: widget.session.repository,
      serverId: widget.server.id,
      channelId: widget.channel.id,
      sessionId: sessionId,
      participantId: person.identity,
      participantName: person.name,
      participantRole: _roleOf(person),
      isLocal: person.isLocal,
      viewerSessionRole: viewerSessionRole,
      viewerCanModerate: widget.role?.canModerate ?? false,
      compact: compact,
    );
  }

  Future<void> _toggleHand() async {
    final sessionId = _sessionId;
    if (sessionId == null || _busy || !_canRaiseHand) return;
    final target = !_handIsUp;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repository = widget.session.repository;
    try {
      final result = await repository.setSessionHand(
        serverId: widget.server.id,
        channelId: widget.channel.id,
        sessionId: sessionId,
        raised: target,
        requestId: repository.newRequestId(),
      );
      if (!mounted) return;
      setState(() {
        _raised = result.raised;
        _raisedSessionId = result.sessionId;
        _receiptVersion = widget.session.ownParticipantVersion;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _busy = false;
      });
    }
  }

  Future<void> _toggleFollow(bool following) async {
    final repository = widget.followRepository;
    if (repository == null || _followBusy) return;
    setState(() {
      _followBusy = true;
      _actionError = null;
    });
    try {
      final result = await repository.setCommunityFollow(
        serverId: widget.server.id,
        following: !following,
      );
      if (mounted) setState(() => _followOverride = result);
    } catch (error) {
      if (mounted) setState(() => _actionError = error);
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _share() async {
    if (_shareBusy) return;
    setState(() {
      _shareBusy = true;
      _actionError = null;
    });
    try {
      final link = buildServerLink(
        widget.server.id,
        channelId: widget.channel.id,
      );
      final override = widget.shareServer;
      if (override != null) {
        await override(link);
      } else {
        await SharePlus.instance.share(
          ShareParams(text: '${widget.server.name}\n$link'),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _actionError = error);
    } finally {
      if (mounted) setState(() => _shareBusy = false);
    }
  }

  Future<void> _openObs() async {
    final sessionId = _sessionId;
    if (sessionId == null || !widget.session.isSessionHost) return;
    final repository =
        widget.broadcastRepository ??
        (_defaultBroadcastRepository ??= ServerBroadcastIngressService());
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ServerObsBroadcastSheet(
        repository: repository,
        serverId: widget.server.id,
        channelId: widget.channel.id,
        sessionId: sessionId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.session,
    builder: (context, _) {
      final copy = AppLocalizations.of(context);
      final palette = context.appPalette;
      final colors = ServerIdentity.of(
        widget.server.type,
      ).resolve(Theme.of(context).brightness);
      return widget.compact
          ? _phone(context, copy, palette, colors)
          : _wide(context, copy, palette, colors);
    },
  );

  // ------------------------------------------------------------ arrangements

  /// Tablet and desktop: one scrolling column — scene, title, description,
  /// actions, and the event module when that channel exists. The conversation
  /// is the shell's own context panel (desktop) or local tab (tablet).
  Widget _wide(
    BuildContext context,
    AppLocalizations copy,
    AppPalette palette,
    ServerIdentityVisuals colors,
  ) {
    final events = _events;
    return SingleChildScrollView(
      key: const ValueKey('server-channel-content-scroll'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stage(copy, palette, colors),
          const SizedBox(height: 20),
          // No title and no liveness line here: at tablet and desktop width
          // the shell's channel header two rows above already carries both,
          // and the session title the board shows in this place has no
          // source at all. What is left is what is actually new — what this
          // community says about itself, and who is on the air.
          _description(palette, copy, maxLines: 4, lead: true),
          if (_inRoom) ...[
            const SizedBox(height: 16),
            _OnAir(
              participants: widget.session.participants,
              colors: colors,
              label: copy.serverStageOnAir,
              speaking: copy.serverSpeaking,
              actionBuilder: _participantMenu,
            ),
            if (widget.session.raisedHands.isNotEmpty) ...[
              const SizedBox(height: 16),
              ServerStageRequests(session: widget.session),
            ],
          ],
          const SizedBox(height: 20),
          _actions(copy, palette, colors),
          if (events != null) ...[
            const SizedBox(height: AppSpacing.lg),
            ServerModuleCard(
              key: const ValueKey('server-community-event-card'),
              icon: serverChannelIcon(ServerChannelKind.events),
              title: copy.serverNextEvent,
              body: copy.serverEventsModuleBody,
              colors: colors,
              primaryLabel: copy.serverOpenEvents,
              primaryIcon: Icons.event_available_outlined,
              channel: events,
              onOpenChannel: widget.onOpenChannel,
              available: true,
            ),
          ],
        ],
      ),
    );
  }

  /// Phone: the video leads and stays on screen, the details scroll under it
  /// inside a bounded block, `Czat | Kanały` follows, the conversation takes
  /// the remaining height and the primary action is pinned to the bottom.
  Widget _phone(
    BuildContext context,
    AppLocalizations copy,
    AppPalette palette,
    ServerIdentityVisuals colors,
  ) {
    final events = _events;
    final chat = widget.chat;
    final openChannels = widget.onOpenChannels;
    // A composer (or the read-only notice in its place) is a fixed cost that
    // grows with the text setting and cannot shrink, so at large text the
    // scene yields more of the surface to the conversation instead of
    // pushing it off the bottom.
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 22;
    final stacked = chat != null && !largeText;
    final sceneFlex = largeText ? 45 : 58;
    // The picture and what is said about it divide the scene's own share;
    // the conversation's share below is untouched, so making the picture
    // flexible never squeezes the composer or the read-only notice.
    //
    // The picture keeps 55 % of that share. It was briefly cut to 40 % to give
    // the details pane room for the three secondary actions, and that is the
    // wrong lever: at 200 % text the same factor also drives the non-stacked
    // branch, where the picture is already a sliver, and it shrank it far
    // enough to clip the `NA ŻYWO` marker out of the broadcast entirely.
    // The actions are handled where the problem actually is — board 02's
    // `Obserwuj` is pinned beside the title at 1× (see `_title`).
    final stageFlex = (sceneFlex * 0.55).round();
    final detailsFlex = sceneFlex - stageFlex;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Everything below the picture. The picture itself is pinned above
        // it: with the 16:9 scene inside this scroll, a 320 px phone at
        // 200 % text spent the whole visible block on the picture and cut the
        // channel's name, its live line and every action out of the surface.
        final details = ServerScrollingDetails(
          key: const ValueKey('server-community-details'),
          fadeKey: const ValueKey('server-community-details-fade'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_inRoom) ...[
                  _OnAir(
                    participants: widget.session.participants,
                    colors: colors,
                    label: copy.serverStageOnAir,
                    speaking: copy.serverSpeaking,
                    actionBuilder: (person) =>
                        _participantMenu(person, compact: true),
                  ),
                  const SizedBox(height: 10),
                  if (widget.session.raisedHands.isNotEmpty) ...[
                    ServerStageRequests(session: widget.session),
                    const SizedBox(height: 10),
                  ],
                ],
                _description(palette, copy, maxLines: 3),
                const SizedBox(height: 12),
                _secondaryActions(copy),
                if (events != null) ...[
                  const SizedBox(height: 14),
                  ServerModuleCard(
                    key: const ValueKey('server-community-event-card'),
                    icon: serverChannelIcon(ServerChannelKind.events),
                    title: copy.serverNextEvent,
                    body: copy.serverEventsModuleBody,
                    colors: colors,
                    primaryLabel: copy.serverOpenEvents,
                    primaryIcon: Icons.event_available_outlined,
                    channel: events,
                    onOpenChannel: widget.onOpenChannel,
                    available: true,
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The broadcast holds its place on the surface; only what is said
            // about it scrolls. It is flexible rather than fixed so that a
            // short viewport — a 320 px phone at 200 % text, a landscape
            // phone — shrinks the picture instead of overflowing the surface;
            // `AspectRatio` keeps 16:9 by narrowing it, and `loose` means it
            // never grows past that.
            // At 200 % text the strip below is a real choice, and choosing
            // the conversation means the conversation: the picture steps
            // aside rather than leaving it a band too small for its own
            // composer. At every other size the broadcast always shows.
            if (stacked || _tab == 0)
              Flexible(
                // Without the conversation stacked under it the broadcast can
                // take a larger part of what is left, so the picture stays a
                // picture instead of a band.
                flex: stacked ? stageFlex : 40,
                fit: FlexFit.loose,
                child: _stage(copy, palette, colors),
              ),
            // The phone surface has no channel header over the scene, so the
            // name and the live line belong here — and they hold their place
            // instead of scrolling with the rest, because on a 320 px phone
            // at 200 % text the scrolling remainder collapses to nothing and
            // these were the two lines that disappeared with it. They cost
            // the picture height rather than the surface: the scene above is
            // flexible and yields to them.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _title(copy, palette, large: false),
            ),
            // Board 02's phone keeps the conversation under the broadcast,
            // and at the default text setting it fits: the scene and the chat
            // share what the tab strip and the pinned action leave, with a
            // loose fit so the scene can be shorter than its share.
            if (stacked) ...[
              Flexible(flex: detailsFlex, fit: FlexFit.loose, child: details),
              _tabs(copy, colors, openChannels!, stacked: true),
              Expanded(flex: 100 - sceneFlex, child: chat),
            ]
            // At 200 % text the same surface cannot hold both: the picture
            // collapses to a sliver and the conversation's own composer or
            // read-only line overflows it. So the strip stops being a label
            // for what is already on screen and becomes the choice it always
            // looked like — the broadcast keeps its place, and the rest of
            // the surface is whichever of the two the person picked.
            else if (chat != null && openChannels != null) ...[
              _tabs(copy, colors, openChannels, stacked: false),
              // The weight matters: the picture above is itself flexible, so
              // an unweighted `Expanded` here would leave the chosen pane a
              // sliver of the free space and overflow the conversation's own
              // read-only line.
              Expanded(
                flex: 100 - stageFlex,
                child: _tab == 1 ? chat : details,
              ),
            ] else
              Expanded(flex: 100 - stageFlex, child: details),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: _primary(copy, palette, colors, fullWidth: true),
            ),
          ],
        );
      },
    );
  }

  /// The phone's local strip. `Kanały` is an action, not a destination, at
  /// both sizes: the channel list opens over the surface and the strip's
  /// selection does not move to it.
  Widget _tabs(
    AppLocalizations copy,
    ServerIdentityVisuals colors,
    VoidCallback openChannels, {
    required bool stacked,
  }) {
    final channels = ServerLocalTab(
      key: const ValueKey('server-open-channels'),
      label: copy.serverChannels,
      icon: Icons.tag_rounded,
    );
    final conversation = ServerLocalTab(
      key: const ValueKey('server-tab-chat'),
      label: copy.serverLiveChat,
      icon: Icons.forum_outlined,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: stacked
          ? ServerLocalTabs(
              tabs: [conversation, channels],
              // The conversation is already on screen under the strip, so it
              // stays selected until a channel is picked.
              selectedIndex: 0,
              onSelected: (index) {
                if (index == 1) openChannels();
              },
              colors: colors,
            )
          : ServerLocalTabs(
              tabs: [
                ServerLocalTab(
                  key: const ValueKey('server-tab-scene'),
                  label: widget.channel.name,
                  icon: serverChannelIcon(widget.channel.kind),
                ),
                conversation,
                channels,
              ],
              selectedIndex: _tab,
              onSelected: (index) {
                if (index == 2) {
                  openChannels();
                  return;
                }
                setState(() => _tab = index);
              },
              colors: colors,
            ),
    );
  }

  // ----------------------------------------------------------------- pieces

  /// The 16:9 scene. Bounded so a wide column does not turn it into a wall,
  /// and never taller than it is wide is allowed to make it.
  Widget _stage(
    AppLocalizations copy,
    AppPalette palette,
    ServerIdentityVisuals colors,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite
          ? math.min(
              constraints.maxWidth,
              ServerCommunityStage.maxStageHeight * 16 / 9,
            )
          : ServerCommunityStage.maxStageHeight * 16 / 9;
      return Align(
        // A wide column is wider than the bounded scene, and a picture
        // floating in the middle of it leaves the title, the actions and the
        // event card hanging off a different left edge. The scene keeps the
        // column's edge; only a phone, where a short surface can narrow the
        // picture below the full width, centres what is left.
        alignment: widget.compact
            ? Alignment.center
            : AlignmentDirectional.centerStart,
        // A bound, not a fixed width: when the surface is shorter than 9/16
        // of the column the picture narrows to stay 16:9 rather than being
        // squashed into whatever height is left.
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: AspectRatio(
            key: const ValueKey('server-community-scene'),
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: AppRadius.md,
              child: Container(
                // In the dark theme a sunken fill alone leaves the scene
                // indistinguishable from the surface behind it, so the empty
                // stage reads as a hole rather than a stage. The template's
                // own wash and the shared border give it an edge, exactly as
                // the selector card is drawn, and cost no new colour.
                decoration: BoxDecoration(
                  border: Border.all(color: palette.border),
                  borderRadius: AppRadius.md,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.alphaBlend(colors.cardWash, palette.surfaceSunken),
                      palette.surfaceSunken,
                    ],
                    stops: const [0, .75],
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, box) => Stack(
                    fit: StackFit.expand,
                    children: [
                      _stageBody(copy, palette, colors),
                      // The marker is bounded by the picture on both axes.
                      // Unbounded it took its intrinsic width inside a
                      // clipping `Stack`, so on a 320-px phone at 200 % text —
                      // where this 16:9 picture collapses to a sliver — it was
                      // cut mid-word into a red smear that says nothing. Below
                      // the height it needs it is not drawn at all: the live
                      // truth is still on screen, in words, as the
                      // `Na żywo od 19:40` line under the title.
                      if (widget.channel.liveness.isLive &&
                          box.maxHeight >= _liveMarkerFloor)
                        PositionedDirectional(
                          top: 10,
                          start: 10,
                          end: 10,
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: ServerLivePill(label: copy.serverLivePill),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  /// The picture has to be at least this tall to carry the marker inside it:
  /// 10 px of inset plus the pill's own height at 200 % text, plus a margin.
  static const _liveMarkerFloor = 52.0;

  Widget _stageBody(
    AppLocalizations copy,
    AppPalette palette,
    ServerIdentityVisuals colors,
  ) {
    final publisher = _inRoom ? _publisher : null;
    final track = publisher?.screenShareTrack ?? publisher?.cameraTrack;
    if (publisher != null && track != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          lk.VideoTrackRenderer(
            track,
            key: const ValueKey('server-community-video'),
          ),
          PositionedDirectional(
            bottom: 10,
            start: 10,
            child: _NameChip(
              label: publisher.isLocal ? copy.serverYou : publisher.name,
            ),
          ),
        ],
      );
    }
    final String message;
    if (widget.server.isHeld) {
      message = copy.serverHeldBody;
    } else if (_inRoom) {
      message = copy.serverStageNoVideo;
    } else if (widget.channel.liveness.isLive) {
      message = copy.serverStageJoinToWatch;
    } else {
      message = copy.serverQuiet(widget.channel.kind);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // A short viewport at 200 % text can leave the picture only a band
        // of its own. The glyph is the first thing to go, then the pill's
        // clearance: what must survive is the sentence saying what the stage
        // is doing.
        final height = constraints.maxHeight;
        final glyph = height > 150;
        // The sentence is measured against the reader's own text size, not a
        // fixed height: below two of their lines plus the pill's clearance
        // the picture is a band, and the sentence would be cut across the
        // middle or drawn under the pill. The name and the live line
        // directly below the picture already carry the same fact, so the
        // band keeps only the pill.
        final line = MediaQuery.textScalerOf(context).scale(16) * 1.45;
        if (height < line * 2 + 24) return const SizedBox.expand();
        return Padding(
          // The live pill sits in the top-left corner; the state below it
          // keeps clear of it whenever there is room to.
          padding: EdgeInsets.fromLTRB(20, height > 90 ? 44 : 4, 20, 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (glyph) ...[
                Icon(
                  _inRoom
                      ? Icons.videocam_off_outlined
                      : Icons.podcasts_rounded,
                  size: widget.compact ? 36 : 48,
                  color: colors.foreground,
                ),
                const SizedBox(height: 10),
              ],
              Flexible(
                child: Text(
                  message,
                  key: const ValueKey('server-community-stage-state'),
                  textAlign: TextAlign.center,
                  maxLines: glyph ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The broadcast's name is the channel's own name — no session carries a
  /// title, so none is invented — with the liveness line under it.
  Widget _title(
    AppLocalizations copy,
    AppPalette palette, {
    required bool large,
  }) {
    final live = widget.channel.liveness.isLive;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.channel.name,
          key: const ValueKey('server-community-title'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style:
              (large ? AppTypography.headlineSmall : AppTypography.titleLarge)
                  .copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          live
              ? copy.serverLiveSince(
                  serverLiveClock(context, widget.channel.liveness.startedAt!),
                )
              : copy.serverQuiet(widget.channel.kind),
          key: const ValueKey('server-community-liveness'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyMedium.copyWith(
            color: palette.textSecondary,
          ),
        ),
      ],
    );
    // Board 02's phone anatomy is "title + `Obserwuj`" (contract §4.2), and
    // the board is right about why: at the default text setting the phone's
    // details pane is a hundred-odd pixels tall, so the three secondary
    // actions inside it were drawn below its edge and the tab strip painted
    // over them. Pinning the one action the board names beside the title
    // fixes that where it happens — at 1×.
    //
    // At 200 % text it must NOT be pinned. The surface takes a different
    // branch there (the strip becomes a real choice and the chosen pane is an
    // `Expanded`, so the actions are on screen anyway), and a 164-px button
    // beside the title on a 320-px phone leaves the heading eight pixels and
    // collapses the broadcast above it to nothing — which is exactly what it
    // did before this guard.
    final pinFollow =
        widget.compact && MediaQuery.textScalerOf(context).scale(16) <= 22;
    if (!pinFollow) return heading;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: heading),
        const SizedBox(width: 8),
        _follow(copy, compactPadding: true),
      ],
    );
  }

  /// What this community says about itself, written at creation. When the
  /// owner left it empty the template's own sentence stands in — copy, not
  /// data pretending to be theirs.
  Widget _description(
    AppPalette palette,
    AppLocalizations copy, {
    required int maxLines,
    bool lead = false,
  }) => Text(
    widget.server.description.isEmpty
        ? copy.serverCommunityStageBody
        : widget.server.description,
    key: const ValueKey('server-community-description'),
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: (lead ? AppTypography.bodyLarge : AppTypography.bodyMedium).copyWith(
      color: lead ? palette.textPrimary : palette.textSecondary,
    ),
  );

  /// Wide: the primary action and the available community actions in one row.
  Widget _actions(
    AppLocalizations copy,
    AppPalette palette,
    ServerIdentityVisuals colors,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _primary(copy, palette, colors, fullWidth: false),
      const SizedBox(height: 12),
      _secondaryActions(copy),
    ],
  );

  Widget _secondaryActions(AppLocalizations copy) {
    // On a phone these three share a pane that is a hundred-odd pixels tall,
    // and with the desktop's 24-px button padding not even two of them fitted
    // on a line: all three were laid out below the pane's edge and the tab
    // strip under it painted over them. A tighter gutter puts the chip and
    // `Obserwuj` on one line at 320 px without changing anything wider.
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: widget.compact
          ? const EdgeInsets.symmetric(horizontal: 12)
          : null,
    );
    final cameraError = widget.session.cameraError;
    final screenError = widget.session.screenShareError;
    final actionError = _actionError ?? cameraError ?? screenError;
    return Column(
      key: const ValueKey('server-community-secondary-actions'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_inRoom && widget.session.canPublishCamera)
              OutlinedButton.icon(
                key: const ValueKey('server-community-camera'),
                onPressed: widget.session.cameraBusy
                    ? null
                    : widget.session.toggleCamera,
                style: style,
                icon: Icon(
                  widget.session.isCameraEnabled
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_outlined,
                  size: 18,
                ),
                label: Text(
                  widget.session.isCameraEnabled
                      ? copy.serverCameraOn
                      : copy.serverCameraOff,
                ),
              ),
            if (_inRoom && widget.session.isSessionHost)
              OutlinedButton.icon(
                key: const ValueKey('server-community-screen-share'),
                onPressed:
                    widget.session.canShareScreen &&
                        !widget.session.screenShareBusy
                    ? widget.session.toggleScreenShare
                    : null,
                style: style,
                icon: Icon(
                  widget.session.isScreenShareEnabled
                      ? Icons.stop_screen_share_outlined
                      : Icons.screen_share_outlined,
                  size: 18,
                ),
                label: Text(
                  widget.session.isScreenShareEnabled
                      ? copy.serverStopSharing
                      : copy.serverShareScreen,
                ),
              ),
            if (_inRoom && widget.session.isSessionHost)
              OutlinedButton.icon(
                key: const ValueKey('server-community-obs'),
                onPressed: _openObs,
                style: style,
                icon: const Icon(Icons.live_tv_rounded, size: 18),
                label: Text(copy.text('OBS', 'OBS')),
              ),
            // The phone draws this one beside the title instead — except at
            // 200 % text, where it does not fit there and belongs back here.
            if (!widget.compact ||
                MediaQuery.textScalerOf(context).scale(16) > 22)
              _follow(copy, compactPadding: widget.compact),
            OutlinedButton.icon(
              key: const ValueKey('server-community-share'),
              onPressed: _shareBusy ? null : _share,
              style: style,
              icon: _shareBusy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share_rounded, size: 18),
              label: Text(copy.serverShare),
            ),
          ],
        ),
        if (actionError != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              serverActionFailureCopy(
                actionError,
                copy,
                fallback: cameraError != null
                    ? copy.serverCameraControlFailed
                    : screenError != null
                    ? copy.serverShareScreenUnavailable
                    : copy.text(
                        'That action could not be completed.',
                        'Nie udało się wykonać tej czynności.',
                      ),
              ),
              key: const ValueKey('server-community-action-error'),
              style: AppTypography.bodySmall.copyWith(
                color: context.appPalette.dangerForeground,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _follow(AppLocalizations copy, {required bool compactPadding}) {
    final repository = widget.followRepository;
    if (repository == null) {
      return OutlinedButton.icon(
        key: const ValueKey('server-community-follow'),
        onPressed: null,
        icon: const Icon(Icons.notifications_none_rounded, size: 18),
        label: Text(copy.serverFollow),
      );
    }
    return StreamBuilder<bool>(
      stream: repository.watchCommunityFollow(widget.server.id),
      initialData: _followOverride,
      builder: (context, snapshot) {
        final following = _followOverride ?? snapshot.data ?? false;
        return OutlinedButton.icon(
          key: const ValueKey('server-community-follow'),
          onPressed: _followBusy || snapshot.hasError
              ? null
              : () => _toggleFollow(following),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: compactPadding
                ? const EdgeInsets.symmetric(horizontal: 12)
                : null,
          ),
          icon: _followBusy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  following
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  size: 18,
                ),
          label: Text(following ? copy.serverFollowing : copy.serverFollow),
        );
      },
    );
  }

  /// The one control that changes what this person is doing: join the stage,
  /// see what the join is doing, or — once the provider really has them in
  /// the generation — ask for the floor.
  Widget _primary(
    AppLocalizations copy,
    AppPalette palette,
    ServerIdentityVisuals colors, {
    required bool fullWidth,
  }) {
    if (widget.server.isHeld) {
      return ServerSessionHeld(
        copy: copy,
        palette: palette,
        colors: colors,
        fullWidth: fullWidth,
      );
    }
    if (!_here) {
      return Align(
        alignment: fullWidth
            ? AlignmentDirectional.center
            : AlignmentDirectional.centerStart,
        child: ServerJoinAction(
          channel: widget.channel,
          role: widget.role,
          live: widget.channel.liveness.isLive,
          copy: copy,
          colors: colors,
          fullWidth: fullWidth,
          onJoin: () => widget.session.join(widget.server, widget.channel),
        ),
      );
    }
    if (!_inRoom) {
      return ServerSessionStatus(
        session: widget.session,
        copy: copy,
        palette: palette,
        colors: colors,
        compact: widget.compact,
      );
    }
    return _hand(copy, palette, colors, fullWidth: fullWidth);
  }

  Widget _hand(
    AppLocalizations copy,
    AppPalette palette,
    ServerIdentityVisuals colors, {
    required bool fullWidth,
  }) {
    final reconnecting =
        widget.session.phase == ServerSessionPhase.reconnecting;
    final error = _error;
    final ownHand = _ownHand;
    final up = ownHand.up;
    final handMessage = serverOwnHandMessage(
      copy,
      up: up,
      decision: ownHand.decision,
    );
    return Column(
      crossAxisAlignment: fullWidth
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        if (reconnecting)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              copy.serverReconnectingFor(widget.session.reauthorization),
              key: const ValueKey('server-session-status'),
              textAlign: fullWidth ? TextAlign.center : TextAlign.start,
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ),
        if (_canRaiseHand) ...[
          _HandButton(
            busy: _busy,
            raised: up,
            fullWidth: fullWidth,
            colors: colors,
            label: _busy
                ? copy.serverHandSending
                : up
                ? copy.serverLowerHand
                : copy.serverRaiseHand,
            onPressed: _busy ? null : _toggleHand,
          ),
          if (handMessage != null || error != null) const SizedBox(height: 6),
          if (error != null)
            Text(
              serverHandFailureCopy(error, copy),
              key: const ValueKey('server-community-hand-error'),
              textAlign: fullWidth ? TextAlign.center : TextAlign.start,
              style: AppTypography.bodySmall.copyWith(
                color: palette.dangerForeground,
              ),
            )
          else if (handMessage != null)
            Semantics(
              liveRegion: true,
              child: Text(
                handMessage,
                key: const ValueKey('server-community-hand-state'),
                textAlign: fullWidth ? TextAlign.center : TextAlign.start,
                style: AppTypography.bodySmall.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ),
        ] else if (widget.session.reauthorization == null)
          Text(
            // The generation's host and its guests are on the stage already;
            // there is nothing for them to ask for.
            copy.serverInConversation,
            key: const ValueKey('server-community-hand-state'),
            textAlign: fullWidth ? TextAlign.center : TextAlign.start,
            style: AppTypography.bodyMedium.copyWith(
              color: palette.textSecondary,
            ),
          ),
      ],
    );
  }
}

class _HandButton extends StatelessWidget {
  const _HandButton({
    required this.busy,
    required this.raised,
    required this.fullWidth,
    required this.colors,
    required this.label,
    required this.onPressed,
  });
  final bool busy;
  final bool raised;
  final bool fullWidth;
  final ServerIdentityVisuals colors;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          )
        : Icon(
            raised ? Icons.back_hand_rounded : Icons.back_hand_outlined,
            size: 18,
          );
    final size = fullWidth ? const Size.fromHeight(56) : const Size(48, 48);
    // A raised hand is a request that can be taken back, so the control that
    // withdraws it is not the same filled call to action that made it.
    return raised
        ? OutlinedButton.icon(
            key: const ValueKey('server-community-hand'),
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: size,
              foregroundColor: colors.linkForeground,
            ),
            icon: icon,
            label: Text(label),
          )
        : FilledButton.icon(
            key: const ValueKey('server-community-hand'),
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: colors.cta,
              foregroundColor: colors.onCta,
              minimumSize: size,
            ).copyWith(side: serverFocusRing(colors.onCta)),
            icon: icon,
            label: Text(label),
          );
  }
}

/// Who the provider reports in this generation, after joining.
///
/// This is not a viewer count and cannot become one: it names the people this
/// device is actually connected to, and it does not exist before the join.
class _OnAir extends StatelessWidget {
  const _OnAir({
    required this.participants,
    required this.colors,
    required this.label,
    required this.speaking,
    this.actionBuilder,
  });
  final List<ServerMediaParticipant> participants;
  final ServerIdentityVisuals colors;
  final String label;
  final String speaking;
  final Widget? Function(ServerMediaParticipant person)? actionBuilder;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) return const SizedBox.shrink();
    final palette = context.appPalette;
    return Column(
      key: const ValueKey('server-community-on-air'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.eyebrow.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final person in participants)
              _PersonChip(
                person: person,
                colors: colors,
                speaking: speaking,
                action: actionBuilder?.call(person),
              ),
          ],
        ),
      ],
    );
  }
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({
    required this.person,
    required this.colors,
    required this.speaking,
    this.action,
  });
  final ServerMediaParticipant person;
  final ServerIdentityVisuals colors;
  final String speaking;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: AppRadius.pill,
        border: Border.all(
          color: person.isSpeaking ? palette.audioAccent : palette.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: UserAvatar(
              radius: 13,
              userId: person.identity,
              displayName: person.name,
              backgroundColor: colors.iconSurface,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Semantics(
              container: true,
              label: person.isSpeaking
                  ? '${person.name}, $speaking'
                  : person.name,
              excludeSemantics: true,
              child: Text(
                person.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelMedium.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
          if (!person.isMicrophoneEnabled) ...[
            const SizedBox(width: 6),
            Icon(Icons.mic_off_rounded, size: 14, color: palette.textTertiary),
          ],
          // The participant description and moderation button are sibling
          // nodes. Excluding only the decorative identity avoids duplicate
          // names without deleting the button's tap action.
          if (action != null) ...[const SizedBox(width: 2), action!],
        ],
      ),
    );
  }
}

/// The name over a picture that is actually being sent.
class _NameChip extends StatelessWidget {
  const _NameChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        // The scrim is the dark ink both themes already put over media, so
        // the name reads on a bright frame and on a dark one alike.
        color: palette.scrim.withValues(alpha: .74),
        borderRadius: AppRadius.pill,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelMedium.copyWith(color: AppColors.white),
      ),
    );
  }
}
