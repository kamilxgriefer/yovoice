import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_member_role.dart';
import '../../data/models/server_podcast_episode.dart';
import '../../data/services/server_media_connector.dart';
import '../../data/services/server_podcast_episode_repository.dart';
import '../../data/services/server_session_controller.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';
import 'server_channel_scene.dart';
import 'server_module_card.dart';
import 'server_panel.dart';
import 'server_scrolling_details.dart';
import 'server_stage_participant_menu.dart';

/// `Studio LIVE` — board 05's centre, the podcast template's audio stage.
///
/// The channel is `stage / broadcast / audio`, so there is no picture and no
/// player: the scene is the people on the air. What each of them is comes
/// from the role the **server** signed into their own access token
/// (`session_livekit.js mintToken()` writes `{uid, role, …}` into the token's
/// metadata and the same grant sets `canUpdateOwnMetadata: false`), delivered
/// by the provider. That is authority, not a guess — but it exists only
/// inside a joined generation, so before joining this scene names nobody.
///
/// The studio never invents state:
///
/// * **no listener, viewer or participant count** anywhere — the liveness
///   projection is `{schemaVersion, isLive, startedAt}` and no presence
///   writer exists (contract G6), so `NA ŻYWO` and *since when* are drawn and
///   `84 słuchaczy` never is, before or after joining;
/// * recording status comes only from `podcastRecordingState/main`; moderator
///   controls reach revision-fenced callables and playback uses a short-lived,
///   generation-bound URL from the episode service;
/// * the persisted program opens through Events V1 and the archive through the
///   dedicated Episodes channel.
///
/// `Poproś o głos` is real: it calls the registered `setServerSessionHandV1`,
/// only from inside a joined generation, and never for that generation's own
/// host. `Zadaj pytanie` opens the server's persisted Q&A: each member has one
/// vote per question and a moderator can select the single question currently
/// marked `Na antenie`. A joined host or server moderator can move participants
/// between the stage and audience and explicitly apply or release their own
/// moderation-mute dimension. Hierarchy and both mute flags remain backend
/// authority.
class ServerPodcastStage extends StatefulWidget {
  const ServerPodcastStage({
    required this.server,
    required this.channel,
    required this.session,
    required this.episodeRepository,
    this.role,
    this.channels = const [],
    this.onOpenChannel,
    this.compact = false,
    super.key,
  });

  final Server server;
  final ServerChannel channel;
  final ServerSessionController session;
  final ServerPodcastEpisodeRepository? episodeRepository;
  final ServerMemberRole? role;

  /// The server's own channels, so the episode cards and `Zadaj pytanie` can
  /// offer the real `Odcinki`, `Program` and `Pytania` instead of a module
  /// that does not exist.
  final List<ServerChannel> channels;
  final ValueChanged<ServerChannel>? onOpenChannel;

  /// Phone: the studio and what follows it scroll, and the one action that
  /// changes what this person is doing is pinned to the bottom.
  final bool compact;

  /// Two module cards sit side by side only when each still has room for its
  /// own copy and its own controls.
  static const twoCardWidth = 640.0;

  @override
  State<ServerPodcastStage> createState() => _ServerPodcastStageState();
}

class _ServerPodcastStageState extends State<ServerPodcastStage> {
  /// The last answer `setServerSessionHandV1` gave, with the generation it
  /// answered for. A hand belongs to one generation: when the session ends or
  /// a new one starts this stops applying and the control returns to "ask",
  /// which is exactly what the backend would say.
  bool _raised = false;
  String? _raisedSessionId;
  bool _busy = false;
  Object? _error;
  bool _recordingBusy = false;
  Object? _recordingError;

  ServerChannel? _channelOfKind(ServerChannelKind kind) =>
      widget.channels.where((channel) => channel.kind == kind).firstOrNull;

  ServerChannel? get _episodes => _channelOfKind(ServerChannelKind.episodes);
  ServerChannel? get _program => _channelOfKind(ServerChannelKind.events);
  ServerChannel? get _questions => _channelOfKind(ServerChannelKind.questions);

  bool get _here => widget.session.isIn(widget.channel.id);

  bool get _inRoom =>
      _here &&
      (widget.session.phase == ServerSessionPhase.connected ||
          widget.session.phase == ServerSessionPhase.reconnecting);

  /// The generation this device is actually in, or null when there is none.
  String? get _sessionId =>
      _inRoom ? widget.session.connection?.sessionId : null;

  /// The host of a generation never queues for their own studio, and the
  /// callable says so; the control is not drawn for them.
  bool get _canRaiseHand =>
      _sessionId != null && widget.session.connection?.sessionRole != 'host';

  bool get _handIsUp => _raised && _raisedSessionId == _sessionId;

  /// The signed role for one person. For this device the token receipt is the
  /// same authority and is always present, so it is preferred; for everybody
  /// else the provider carries the server's own signed metadata.
  String? _roleOf(ServerMediaParticipant person) => person.isLocal
      ? (widget.session.connection?.sessionRole ?? person.sessionRole)
      : person.sessionRole;

  bool _onStage(ServerMediaParticipant person) {
    final role = _roleOf(person);
    return role == 'host' || role == 'guest';
  }

  /// The people on the air, host first — the order board 05 draws them in.
  /// A person whose signed role cannot be read is never promoted onto the
  /// stage; they stay in the audience, where nothing is claimed about them.
  List<ServerMediaParticipant> get _stage {
    final people = _inRoom ? widget.session.participants : const [];
    return [
      for (final person in people)
        if (_roleOf(person) == 'host') person,
      for (final person in people)
        if (_roleOf(person) == 'guest') person,
    ];
  }

  List<ServerMediaParticipant> get _audience => [
    if (_inRoom)
      for (final person in widget.session.participants)
        if (!_onStage(person)) person,
  ];

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

  Future<void> _startRecording() async {
    final repository = widget.episodeRepository;
    final episodes = _episodes;
    final sessionId = _sessionId;
    if (repository == null ||
        episodes == null ||
        sessionId == null ||
        widget.session.phase != ServerSessionPhase.connected ||
        !(widget.role?.canModerate ?? false) ||
        _recordingBusy) {
      return;
    }
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const _PodcastRecordingTitleDialog(),
    );
    if (title == null || !mounted) return;
    setState(() {
      _recordingBusy = true;
      _recordingError = null;
    });
    try {
      await repository.startPodcastRecording(
        serverId: widget.server.id,
        channelId: episodes.id,
        studioChannelId: widget.channel.id,
        sessionId: sessionId,
        title: title,
        requestId: repository.newRequestId(),
      );
      if (mounted) setState(() => _recordingBusy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recordingBusy = false;
        _recordingError = error;
      });
    }
  }

  Future<void> _stopRecording(ServerPodcastRecordingState recording) async {
    final repository = widget.episodeRepository;
    if (repository == null ||
        _recordingBusy ||
        !(widget.role?.canModerate ?? false)) {
      return;
    }
    setState(() {
      _recordingBusy = true;
      _recordingError = null;
    });
    try {
      await repository.stopPodcastRecording(
        recording: recording,
        requestId: repository.newRequestId(),
      );
      if (mounted) setState(() => _recordingBusy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recordingBusy = false;
        _recordingError = error;
      });
    }
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

  /// Tablet and desktop: one scrolling column. The channel header two rows
  /// above already carries the studio's name and its live line, and the
  /// episode title board 05 prints here has no source at all, so what follows
  /// the studio is what is actually new.
  Widget _wide(
    BuildContext context,
    AppLocalizations copy,
    AppPalette palette,
    ServerIdentityVisuals colors,
  ) => SingleChildScrollView(
    key: const ValueKey('server-channel-content-scroll'),
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _studio(context, copy, palette, colors),
        const SizedBox(height: 16),
        _recording(context, copy, palette),
        const SizedBox(height: 16),
        _description(palette, copy, maxLines: 4, lead: true),
        const SizedBox(height: 20),
        _actions(copy, palette, colors, fullWidth: false),
        const SizedBox(height: AppSpacing.lg),
        _episodeCards(copy, colors),
      ],
    ),
  );

  /// Phone: the studio and everything said about it scroll together — an
  /// audio stage has no picture to hold in place — while the one action that
  /// changes what this person is doing stays on the surface.
  Widget _phone(
    BuildContext context,
    AppLocalizations copy,
    AppPalette palette,
    ServerIdentityVisuals colors,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // The phone surface draws no channel header over this scene, so the
      // studio's name and its live line belong here — and they hold their
      // place instead of scrolling, which is also what keeps them out of the
      // shell's own bounded header block, where a dock plus a 200 % text
      // setting cuts straight through the `NA ŻYWO` pill.
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: _title(context, copy, palette),
      ),
      Expanded(
        child: ServerScrollingDetails(
          key: const ValueKey('server-podcast-details'),
          fadeKey: const ValueKey('server-podcast-details-fade'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _studio(context, copy, palette, colors),
              const SizedBox(height: 12),
              _recording(context, copy, palette),
              const SizedBox(height: 12),
              _description(palette, copy, maxLines: 3),
              const SizedBox(height: 14),
              _episodeCards(copy, colors),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: _actions(copy, palette, colors, fullWidth: true),
      ),
    ],
  );

  /// The studio's name is the channel's own name — no session carries an
  /// episode title, so none is invented — with the live line under it.
  Widget _title(
    BuildContext context,
    AppLocalizations copy,
    AppPalette palette,
  ) {
    final live = widget.channel.liveness.isLive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.channel.name,
          key: const ValueKey('server-podcast-title'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.titleLarge.copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: 4),
        Wrap(
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
                        widget.channel.liveness.startedAt!,
                      ),
                    )
                  : copy.serverQuiet(widget.channel.kind),
              key: const ValueKey('server-podcast-liveness'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- studio

  /// The stage itself: the host large, the studio's own microphone mark, the
  /// guests beside them, and the audience the provider reports under a rule.
  Widget _studio(
    BuildContext context,
    AppLocalizations copy,
    AppPalette palette,
    ServerIdentityVisuals colors,
  ) {
    final stage = _stage;
    final audience = _audience;
    return Container(
      key: const ValueKey('server-podcast-scene'),
      padding: EdgeInsets.all(widget.compact ? 16 : 24),
      decoration: BoxDecoration(
        border: Border.all(color: _inRoom ? colors.iconBorder : palette.border),
        borderRadius: AppRadius.lg,
        // The template's own coral wash over the card fill, exactly as the
        // accepted selector card is drawn — no new colour.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(colors.cardWash, palette.surface),
            palette.surface,
          ],
          stops: const [0, .75],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The phone has no room to say the same thing twice: the channel
          // header directly above the studio already carries the pill and the
          // since-when line, so the card keeps its height for the people.
          if (widget.channel.liveness.isLive && !widget.compact)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ServerLivePill(label: copy.serverLivePill),
              ),
            ),
          if (stage.isEmpty)
            _quiet(copy, palette, colors)
          else
            _stageRow(context, copy, colors, stage),
          if (audience.isNotEmpty) ...[
            const SizedBox(height: 20),
            Divider(height: 1, color: palette.border),
            const SizedBox(height: 16),
            _AudienceStrip(
              people: audience,
              colors: colors,
              label: copy.serverPodcastAudience,
              actionBuilder: (person) =>
                  _participantMenu(person, compact: true),
            ),
          ],
        ],
      ),
    );
  }

  /// Board 05 puts the host on the left, the studio's microphone mark in the
  /// middle and the guests on the right. A `Wrap` keeps that reading order
  /// and lets a narrow surface fold the guests under the host instead of
  /// pushing them off the card.
  ///
  /// At a large text setting the arrangement changes rather than shrinking:
  /// a tile is only as wide as its avatar, so `Prowadzący` at 200 % would be
  /// cut to an ellipsis under a picture of somebody whose name is also cut.
  /// Each person becomes a row instead, where the name and the role have the
  /// whole card to themselves — the ring, the waveform and the order are all
  /// kept.
  Widget _stageRow(
    BuildContext context,
    AppLocalizations copy,
    ServerIdentityVisuals colors,
    List<ServerMediaParticipant> stage,
  ) {
    final host = stage.first;
    final guests = stage.skip(1).toList();
    final listed = MediaQuery.textScalerOf(context).scale(16) > 22;
    final people = [
      (host, copy.serverPodcastHost, widget.compact || listed ? 100.0 : 148.0),
      for (final guest in guests)
        (
          guest,
          copy.serverPodcastGuest,
          widget.compact || listed ? 84.0 : 104.0,
        ),
    ];
    if (listed) {
      return Column(
        key: const ValueKey('server-podcast-stage'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < people.length; index++) ...[
            if (index > 0) const SizedBox(height: 14),
            _StagePerson(
              person: people[index].$1,
              colors: colors,
              role: people[index].$2,
              speaking: copy.serverSpeaking,
              silent: copy.serverMicrophoneOff,
              you: copy.serverYou,
              size: people[index].$3,
              listed: true,
              action: _participantMenu(people[index].$1),
            ),
          ],
        ],
      );
    }
    final hostTile = _StagePerson(
      person: host,
      colors: colors,
      role: copy.serverPodcastHost,
      speaking: copy.serverSpeaking,
      silent: copy.serverMicrophoneOff,
      you: copy.serverYou,
      size: people.first.$3,
      action: _participantMenu(host),
    );
    final guestTiles = [
      for (var index = 0; index < guests.length; index++)
        _StagePerson(
          person: guests[index],
          colors: colors,
          role: copy.serverPodcastGuest,
          speaking: copy.serverSpeaking,
          silent: copy.serverMicrophoneOff,
          you: copy.serverYou,
          size: people[index + 1].$3,
          action: _participantMenu(guests[index]),
        ),
    ];
    if (widget.compact) {
      // Board 05's phone: the host above, the guests side by side under them,
      // and no studio mark — a 390 px row cannot hold the host, the mark and
      // two guests without dropping one of them to a line of its own.
      return Column(
        key: const ValueKey('server-podcast-stage'),
        children: [
          hostTile,
          if (guestTiles.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: guestTiles,
            ),
          ],
        ],
      );
    }
    return Wrap(
      key: const ValueKey('server-podcast-stage'),
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 20,
      runSpacing: 16,
      children: [
        hostTile,
        // The mark carries the same empty label block the tiles do, so its
        // centre lands exactly on the avatars' centre line at any text size.
        _StudioMark(size: 60, colors: colors, labelSlot: true),
        ...guestTiles,
      ],
    );
  }

  /// No one is on the air: before a join because there is nothing readable to
  /// show, in session because the provider reports nobody holding a stage
  /// role. Both say which of the two it is.
  Widget _quiet(
    AppLocalizations copy,
    AppPalette palette,
    ServerIdentityVisuals colors,
  ) {
    final String message;
    if (widget.server.isHeld) {
      message = copy.serverHeldBody;
    } else if (_inRoom) {
      message = copy.serverPodcastNobodyOnAir;
    } else if (widget.channel.liveness.isLive) {
      message = copy.serverPodcastJoinToListen;
    } else {
      message = copy.serverQuiet(widget.channel.kind);
    }
    return Column(
      children: [
        _StudioMark(size: widget.compact ? 76 : 104, colors: colors),
        const SizedBox(height: 14),
        Text(
          message,
          key: const ValueKey('server-podcast-state'),
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: palette.textSecondary,
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- pieces

  /// Recording state is a Firestore projection written only by the backend.
  /// The red mark is lit exclusively for an authoritative `recording` row.
  Widget _recording(
    BuildContext context,
    AppLocalizations copy,
    AppPalette palette,
  ) {
    final repository = widget.episodeRepository;
    if (repository == null || _episodes == null) {
      return Text(
        copy.serverActionUnavailable,
        key: const ValueKey('server-podcast-recording'),
        style: AppTypography.bodySmall.copyWith(color: palette.textSecondary),
      );
    }
    return StreamBuilder<ServerPodcastRecordingState?>(
      stream: repository.watchPodcastRecording(
        widget.server.id,
        widget.channel.id,
      ),
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (snapshot.hasError) {
          return Semantics(
            liveRegion: true,
            child: Text(
              serverActionFailureCopy(snapshot.error!, copy),
              key: const ValueKey('server-podcast-recording'),
              style: AppTypography.bodySmall.copyWith(
                color: palette.dangerForeground,
              ),
            ),
          );
        }
        if (!snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            key: ValueKey('server-podcast-recording-loading'),
            height: 48,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final active = state?.status == ServerPodcastEpisodeStatus.recording;
        final statusLabel = switch (state?.status) {
          ServerPodcastEpisodeStatus.recording =>
            copy.serverPodcastRecordingActive,
          ServerPodcastEpisodeStatus.processing =>
            copy.serverPodcastRecordingProcessing,
          ServerPodcastEpisodeStatus.ready => copy.serverPodcastEpisodeReady,
          ServerPodcastEpisodeStatus.published =>
            copy.serverPodcastEpisodePublished,
          ServerPodcastEpisodeStatus.error => copy.serverPodcastRecordingError,
          null => copy.serverRecording,
        };
        return Column(
          key: const ValueKey('server-podcast-recording'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              key: const ValueKey('server-podcast-recording-pill'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: active ? palette.dangerSurface : palette.surfaceMuted,
                borderRadius: AppRadius.md,
                border: Border.all(
                  color: active ? palette.dangerForeground : palette.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    active
                        ? Icons.fiber_manual_record
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: active
                        ? palette.dangerForeground
                        : palette.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      state == null
                          ? statusLabel
                          : '$statusLabel · ${state.title}',
                      style: AppTypography.labelLarge.copyWith(
                        color: active
                            ? palette.dangerForeground
                            : palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              state == null
                  ? copy.serverPodcastRecordingIdle
                  : _recordingStateBody(copy, state),
              style: AppTypography.bodySmall.copyWith(
                color: palette.textSecondary,
              ),
            ),
            if (_recordingError != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  serverActionFailureCopy(_recordingError!, copy),
                  key: const ValueKey('server-podcast-recording-error'),
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.dangerForeground,
                  ),
                ),
              ),
            ],
            if (widget.role?.canModerate ?? false) ...[
              const SizedBox(height: 10),
              if (state == null &&
                  _sessionId != null &&
                  widget.session.phase == ServerSessionPhase.connected)
                FilledButton.icon(
                  key: const ValueKey('server-podcast-start-recording'),
                  onPressed: _recordingBusy ? null : _startRecording,
                  icon: const Icon(Icons.fiber_manual_record_rounded),
                  label: Text(copy.serverPodcastStartRecording),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                )
              else if (state?.status == ServerPodcastEpisodeStatus.recording)
                FilledButton.icon(
                  key: const ValueKey('server-podcast-stop-recording'),
                  onPressed: _recordingBusy
                      ? null
                      : () => _stopRecording(state!),
                  icon: const Icon(Icons.stop_rounded),
                  label: Text(copy.serverPodcastStopRecording),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    backgroundColor: palette.dangerForeground,
                    foregroundColor: palette.dangerSurface,
                  ),
                )
              else if (state != null && _episodes != null)
                OutlinedButton.icon(
                  key: const ValueKey('server-podcast-open-episodes'),
                  onPressed: () => widget.onOpenChannel?.call(_episodes!),
                  icon: const Icon(Icons.podcasts_rounded),
                  label: Text(copy.serverRecentEpisodes),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  String _recordingStateBody(
    AppLocalizations copy,
    ServerPodcastRecordingState state,
  ) => switch (state.status) {
    ServerPodcastEpisodeStatus.recording => copy.text(
      'Audio from this live session is being saved.',
      'Dźwięk z tej transmisji jest zapisywany.',
    ),
    ServerPodcastEpisodeStatus.processing => copy.text(
      'The recording is being prepared as an episode.',
      'Nagranie jest przygotowywane jako odcinek.',
    ),
    ServerPodcastEpisodeStatus.ready => copy.text(
      'The episode is ready for a host to publish.',
      'Odcinek jest gotowy do publikacji przez prowadzącego.',
    ),
    ServerPodcastEpisodeStatus.published => copy.text(
      'The episode is available in the archive.',
      'Odcinek jest dostępny w archiwum.',
    ),
    ServerPodcastEpisodeStatus.error => copy.text(
      'Open the archive to retry this recording.',
      'Otwórz archiwum, aby ponowić nagrywanie.',
    ),
  };

  /// What this show says about itself, written at creation. When the owner
  /// left it empty the template's own sentence stands in — copy, not data
  /// pretending to be theirs.
  Widget _description(
    AppPalette palette,
    AppLocalizations copy, {
    required int maxLines,
    bool lead = false,
  }) => Text(
    widget.server.description.isEmpty
        ? copy.serverPodcastStageBody
        : widget.server.description,
    key: const ValueKey('server-podcast-description'),
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: (lead ? AppTypography.bodyLarge : AppTypography.bodyMedium).copyWith(
      color: lead ? palette.textPrimary : palette.textSecondary,
    ),
  );

  /// Board 05's two calls to action. The first is whatever this person can
  /// actually do next; the second exists only when the questions channel does.
  Widget _actions(
    AppLocalizations copy,
    AppPalette palette,
    ServerIdentityVisuals colors, {
    required bool fullWidth,
  }) {
    final questions = _questions;
    final open = widget.onOpenChannel;
    // The phone already has `Pytania` as a local tab beside the studio, so a
    // second control to the same place would be noise — board 05 does not
    // draw one there either.
    final ask = questions == null || open == null || fullWidth
        ? null
        : OutlinedButton.icon(
            key: const ValueKey('server-podcast-ask'),
            onPressed: () => open(questions),
            style: OutlinedButton.styleFrom(
              minimumSize: fullWidth
                  ? const Size.fromHeight(52)
                  : const Size(48, 48),
              foregroundColor: colors.linkForeground,
            ),
            icon: const Icon(Icons.help_outline_rounded, size: 18),
            label: Text(copy.serverAskQuestion),
          );
    final primary = _primary(copy, palette, colors, fullWidth: fullWidth);
    if (!fullWidth) {
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [primary, ?ask],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        primary,
        if (ask != null) ...[const SizedBox(height: 8), ask],
      ],
    );
  }

  /// The one control that changes what this person is doing: join the studio,
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
      // Deliberately not wrapped in an `Align`: on tablet and desktop the two
      // calls to action share one `Wrap`, and an `Align` there is given the
      // whole row's width, which would push `Zadaj pytanie` onto a line of
      // its own. The phone's column stretches it instead.
      return ServerJoinAction(
        channel: widget.channel,
        role: widget.role,
        live: widget.channel.liveness.isLive,
        copy: copy,
        colors: colors,
        fullWidth: fullWidth,
        onJoin: () => widget.session.join(widget.server, widget.channel),
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
    final up = _handIsUp;
    return Column(
      crossAxisAlignment: fullWidth
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        if (reconnecting)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              copy.serverReconnecting,
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
          if (up || error != null) const SizedBox(height: 6),
          if (error != null)
            Text(
              serverActionFailureCopy(
                error,
                copy,
                fallback: copy.serverHandFailed,
              ),
              key: const ValueKey('server-podcast-hand-error'),
              textAlign: fullWidth ? TextAlign.center : TextAlign.start,
              style: AppTypography.bodySmall.copyWith(
                color: palette.dangerForeground,
              ),
            )
          else if (up)
            Text(
              copy.serverHandRaised,
              key: const ValueKey('server-podcast-hand-state'),
              textAlign: fullWidth ? TextAlign.center : TextAlign.start,
              style: AppTypography.bodySmall.copyWith(
                color: palette.textSecondary,
              ),
            ),
        ] else
          Text(
            // The generation's host is on the air already; there is nothing
            // for them to ask for.
            copy.serverStageOnAir,
            key: const ValueKey('server-podcast-hand-state'),
            textAlign: fullWidth ? TextAlign.center : TextAlign.start,
            style: AppTypography.bodyMedium.copyWith(
              color: palette.textSecondary,
            ),
          ),
      ],
    );
  }

  /// `Następny odcinek` and `Ostatnie odcinki`: two honest modules, each drawn
  /// only when the channel it belongs to really exists in this server.
  Widget _episodeCards(AppLocalizations copy, ServerIdentityVisuals colors) {
    final program = _program;
    final episodes = _episodes;
    final cards = <Widget>[
      if (program != null)
        ServerModuleCard(
          key: const ValueKey('server-podcast-next-episode'),
          icon: serverChannelIcon(ServerChannelKind.events),
          title: copy.serverNextEpisode,
          body: copy.serverNextEpisodeBody,
          colors: colors,
          primaryLabel: copy.serverOpenProgram,
          primaryIcon: Icons.notifications_none_rounded,
          channel: program,
          onOpenChannel: widget.onOpenChannel,
          available: true,
        ),
      if (episodes != null)
        ServerModuleCard(
          key: const ValueKey('server-podcast-recent-episodes'),
          icon: serverChannelIcon(ServerChannelKind.episodes),
          title: copy.serverRecentEpisodes,
          body: copy.serverRecentEpisodesBody,
          colors: colors,
          primaryLabel: copy.serverEpisodePlay,
          primaryIcon: Icons.play_arrow_rounded,
          channel: episodes,
          onOpenChannel: widget.onOpenChannel,
          available: widget.episodeRepository != null,
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final side =
            cards.length == 2 &&
            constraints.maxWidth >= ServerPodcastStage.twoCardWidth;
        if (!side) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                if (index > 0) const SizedBox(height: 12),
                cards[index],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards.first),
            const SizedBox(width: 16),
            Expanded(child: cards.last),
          ],
        );
      },
    );
  }
}

/// Owns the title controller for the complete dialog route lifecycle.
///
/// `showDialog` completes when the route is popped, before its reverse
/// transition has necessarily unmounted the text field. Keeping the controller
/// in the dialog state lets Flutter dispose it after the final frame that can
/// still read it.
class _PodcastRecordingTitleDialog extends StatefulWidget {
  const _PodcastRecordingTitleDialog();

  @override
  State<_PodcastRecordingTitleDialog> createState() =>
      _PodcastRecordingTitleDialogState();
}

class _PodcastRecordingTitleDialogState
    extends State<_PodcastRecordingTitleDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final normalized = _controller.text.trim();
    if (normalized.isNotEmpty) Navigator.pop(context, normalized);
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(copy.serverPodcastStartRecording),
      content: TextField(
        key: const ValueKey('server-podcast-recording-title'),
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: copy.serverPodcastRecordingTitle,
          hintText: copy.serverPodcastRecordingTitleHint,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const ValueKey('server-podcast-confirm-recording'),
          onPressed: _submit,
          child: Text(copy.serverPodcastStartRecording),
        ),
      ],
    );
  }
}

/// The studio's own microphone mark. It marks the broadcast itself, never a
/// person and never a count.
class _StudioMark extends StatelessWidget {
  const _StudioMark({
    required this.size,
    required this.colors,
    this.labelSlot = false,
  });
  final double size;
  final ServerIdentityVisuals colors;

  /// Standing between two people, the mark carries the same empty state,
  /// name and role block they do. Both are centred in the same run, so
  /// matching the block is what puts the mark on the avatars' centre line —
  /// at 100 % text and at 200 % alike, without a magic offset.
  final bool labelSlot;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      key: const ValueKey('server-podcast-mark'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.iconSurface,
        border: Border.all(color: colors.iconBorder, width: 1.5),
      ),
      child: Center(
        child: Icon(
          Icons.mic_rounded,
          size: size * .42,
          color: colors.foreground,
        ),
      ),
    );
    if (!labelSlot) return ExcludeSemantics(child: mark);
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          const SizedBox(height: 24),
          Opacity(
            opacity: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('', style: AppTypography.labelLarge),
                Text('', style: AppTypography.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One person on the air, with the ring board 05 draws around them.
///
/// The waveform is bound to [ServerMediaParticipant.isSpeaking] — the
/// provider's own active-speaker signal — and to nothing else. It is a mark,
/// not an animated level meter: the adapter carries no level, so an animated
/// one would be decoration pretending to be data. Its slot keeps its height
/// whether or not somebody is speaking, so the stage never jumps, and the
/// state is carried by the glyph and the spoken label as well as the colour.
class _StagePerson extends StatelessWidget {
  const _StagePerson({
    required this.person,
    required this.colors,
    required this.role,
    required this.speaking,
    required this.silent,
    required this.you,
    required this.size,
    this.listed = false,
    this.action,
  });

  final ServerMediaParticipant person;
  final ServerIdentityVisuals colors;
  final String role;
  final String speaking;
  final String silent;
  final String you;

  /// The avatar's diameter, ring included.
  final double size;

  /// Large text: the avatar keeps its ring and its waveform, and the name and
  /// the role move beside it where they have the whole card's width. Stacked
  /// under an avatar they would both be cut to an ellipsis.
  final bool listed;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final name = person.isLocal ? you : person.name;
    final live = person.isSpeaking;
    final nameStyle = AppTypography.labelLarge.copyWith(
      color: palette.textPrimary,
    );
    final roleStyle = AppTypography.labelSmall.copyWith(
      color: palette.textSecondary,
    );
    final avatar = Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: live ? colors.foreground : colors.iconBorder,
          width: live ? 3 : 1.5,
        ),
      ),
      child: UserAvatar(
        radius: (size - 14) / 2,
        userId: person.identity,
        displayName: person.name,
        backgroundColor: colors.iconSurface,
      ),
    );
    // The slot keeps its height whether or not anybody is speaking, so the
    // stage never jumps when the provider's speaking signal changes.
    final state = SizedBox(
      height: 14,
      child: live
          ? _Waveform(
              key: const ValueKey('server-podcast-waveform'),
              color: colors.foreground,
            )
          : person.isMicrophoneEnabled
          ? null
          : Icon(Icons.mic_off_rounded, size: 14, color: palette.textTertiary),
    );
    return Semantics(
      label: [
        name,
        role,
        if (live) speaking else if (!person.isMicrophoneEnabled) silent,
      ].join(', '),
      child: ExcludeSemantics(
        child: listed
            ? Row(
                children: [
                  avatar,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: nameStyle,
                        ),
                        Text(
                          role,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: roleStyle,
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: state,
                        ),
                      ],
                    ),
                  ),
                  if (action != null) ...[const SizedBox(width: 4), action!],
                ],
              )
            : SizedBox(
                width: size + 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    avatar,
                    const SizedBox(height: 6),
                    state,
                    const SizedBox(height: 4),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: nameStyle,
                    ),
                    Text(
                      role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: roleStyle,
                    ),
                    ?action,
                  ],
                ),
              ),
      ),
    );
  }
}

/// The speaking mark: five bars, drawn only while the provider says this
/// person is speaking.
class _Waveform extends StatelessWidget {
  const _Waveform({required this.color, super.key});
  final Color color;

  /// Fixed, not random and not animated: it says *that* somebody is speaking,
  /// which is the only thing the provider actually tells us.
  static const _bars = [6.0, 11.0, 14.0, 9.0, 5.0];

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      for (final height in _bars)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: Container(
            width: 3,
            height: height,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
    ],
  );
}

/// Board 05's `Publiczność` row.
///
/// These are the people the provider reports to this device in this
/// generation who hold no stage role — not a listener count, which nothing
/// writes, and nothing at all before joining. The overflow tile counts the
/// avatars that did not fit on this row, never an audience.
class _AudienceStrip extends StatelessWidget {
  const _AudienceStrip({
    required this.people,
    required this.colors,
    required this.label,
    this.actionBuilder,
  });

  final List<ServerMediaParticipant> people;
  final ServerIdentityVisuals colors;
  final String label;
  final Widget? Function(ServerMediaParticipant person)? actionBuilder;

  static const _avatar = 36.0;
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Column(
      key: const ValueKey('server-podcast-audience'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.eyebrow.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final participantWidth = _avatar + (actionBuilder == null ? 0 : 48);
            final slots = constraints.maxWidth.isFinite
                ? ((constraints.maxWidth + _gap) / (participantWidth + _gap))
                      .floor()
                : people.length;
            final room = slots.clamp(1, people.length);
            final shown = room < people.length ? room - 1 : room;
            final hidden = people.length - shown;
            return Row(
              children: [
                for (final person in people.take(shown)) ...[
                  Builder(
                    builder: (_) {
                      final action = actionBuilder?.call(person);
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            label: person.name,
                            excludeSemantics: true,
                            child: UserAvatar(
                              radius: _avatar / 2,
                              userId: person.identity,
                              displayName: person.name,
                              backgroundColor: colors.iconSurface,
                            ),
                          ),
                          ?action,
                        ],
                      );
                    },
                  ),
                  const SizedBox(width: _gap),
                ],
                if (hidden > 0)
                  Semantics(
                    label: '+$hidden',
                    excludeSemantics: true,
                    child: Container(
                      key: const ValueKey('server-podcast-audience-overflow'),
                      width: _avatar,
                      height: _avatar,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.surfaceMuted,
                        border: Border.all(color: palette.border),
                      ),
                      child: Center(
                        child: Text(
                          '+$hidden',
                          style: AppTypography.labelSmall.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// A raised hand is a request that can be taken back, so the control that
/// withdraws it is not the same filled call to action that made it.
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
    final size = fullWidth ? const Size.fromHeight(52) : const Size(48, 48);
    return raised
        ? OutlinedButton.icon(
            key: const ValueKey('server-podcast-hand'),
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: size,
              foregroundColor: colors.linkForeground,
            ),
            icon: icon,
            label: Text(label),
          )
        : FilledButton.icon(
            key: const ValueKey('server-podcast-hand'),
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
