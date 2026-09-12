import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
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
import '../../data/services/server_media_connector.dart';
import '../../data/services/server_screen_share_capability.dart';
import '../../data/services/server_session_controller.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';
import 'server_channel_scene.dart';
import 'server_local_tabs.dart';
import 'server_module_card.dart';
import 'server_panel.dart';

/// Which view of the meeting is on screen. The conversation is a view like
/// the other two, so switching to it is a tab change and nothing else — it
/// never touches the session.
enum ServerMeetingTab { presentation, whiteboard, chat }

/// `Spotkanie zespołu` — board 04's centre, the company template's meeting.
///
/// The channel is `meeting / community / meeting`, which is the one
/// configuration `deriveSessionGrant` gives a camera *and* a screen share to,
/// so this scene is the only place in the product where both matter. What is
/// real here and what is not:
///
/// * **Participant tiles are the provider's own in-session roster** (contract
///   G3): a picture appears only for somebody actually sending one, the mic
///   glyph is that person's real track state, and before a join there are no
///   tiles at all. No count of people is printed anywhere — nothing counts
///   them (G6), and the board's "6 uczestników" has no writer.
/// * **Receiving a shared screen is real** on every platform. *Starting* one
///   is answered by [ServerScreenShareCapability] (contract decision D): the
///   browser can, a phone cannot yet, and the control says which — it is
///   never hidden and never drawn as something that fails.
/// * **Publishing your own camera has no lifecycle on this side yet**
///   (contract §3: permission, requested vs. actual, cleanup per source), so
///   no surface offers to turn it on and the scene says so.
/// * **The whiteboard has no backend at all** (contract G9) — no document, no
///   callable, no rule. Its tab is an honest `Wkrótce` state that states
///   plainly that nothing drawn would be kept, and offers the server's real
///   `Tablica` channel as the destination.
///
/// Switching tabs is pure presentation: the session lives in the shell, so a
/// meeting survives every tab change, and only `Opuść` ends it.
class ServerCompanyMeeting extends StatelessWidget {
  const ServerCompanyMeeting({
    required this.server,
    required this.channel,
    required this.session,
    required this.tab,
    required this.onTabSelected,
    this.role,
    this.channels = const [],
    this.onOpenChannel,
    this.chat,
    this.showParticipants = true,
    this.compact = false,
    super.key,
  });

  final Server server;
  final ServerChannel channel;
  final ServerSessionController session;
  final ServerMemberRole? role;

  /// The view on screen, owned by the shell so the dock's `Tablica` can
  /// change it without reaching into this widget's state.
  final ServerMeetingTab tab;
  final ValueChanged<ServerMeetingTab> onTabSelected;

  /// The server's own channels, so the whiteboard state can offer the real
  /// `Tablica` channel rather than a dead card.
  final List<ServerChannel> channels;
  final ValueChanged<ServerChannel>? onOpenChannel;

  /// The conversation, when this width has nowhere else to put it. Present on
  /// a tablet (it becomes the third tab) and absent on a desktop, where the
  /// shell's context panel keeps it permanently on screen beside the tiles.
  final Widget? chat;

  /// False on a desktop, where the tiles live in the context panel instead.
  final bool showParticipants;

  /// The phone surface: one scrolling column, no tabs of its own — the shell
  /// owns `Spotkanie | Czat | Kanały` there.
  final bool compact;

  bool get _here => session.isIn(channel.id);

  bool get _inRoom =>
      _here &&
      (session.phase == ServerSessionPhase.connected ||
          session.phase == ServerSessionPhase.reconnecting);

  /// Whoever is actually sending a screen right now: a remote presenter
  /// first, because a meeting watches somebody else's screen far more often
  /// than its own.
  ServerMediaParticipant? get _presenter {
    final people = session.participants;
    for (final person in people) {
      if (!person.isLocal && person.isSharingScreen) return person;
    }
    for (final person in people) {
      if (person.isSharingScreen) return person;
    }
    return null;
  }

  ServerChannel? get _boardChannel => channels
      .where((candidate) => candidate.kind == ServerChannelKind.whiteboard)
      .firstOrNull;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) {
      final copy = AppLocalizations.of(context);
      final palette = context.appPalette;
      final colors = ServerIdentity.of(
        server.type,
      ).resolve(Theme.of(context).brightness);
      if (compact) return _phone(context, copy, palette, colors);
      return _wide(context, copy, palette, colors);
    },
  );

  // ------------------------------------------------------------ arrangements

  /// Tablet and desktop: the tab strip, then the view it selects.
  Widget _wide(
    BuildContext context,
    AppLocalizations copy,
    AppPalette palette,
    ServerIdentityVisuals colors,
  ) {
    final tabs = _tabs(copy);
    final current = _index(tabs);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: ServerLocalTabs(
            tabs: [for (final entry in tabs) entry.tab],
            selectedIndex: current,
            onSelected: (index) => onTabSelected(tabs[index].value),
            colors: colors,
          ),
        ),
        Expanded(
          child: switch (tabs[current].value) {
            ServerMeetingTab.presentation => _presentation(
              context,
              copy,
              palette,
              colors,
            ),
            ServerMeetingTab.whiteboard => _whiteboard(copy, colors),
            ServerMeetingTab.chat => chat ?? const SizedBox.shrink(),
          },
        ),
      ],
    );
  }

  /// Phone: the shared screen leads, the whiteboard card and the people
  /// follow under it, exactly as board 04's phone column reads. The tabs at
  /// this width are the shell's own (`Spotkanie | Czat | Kanały`).
  Widget _phone(
    BuildContext context,
    AppLocalizations copy,
    AppPalette palette,
    ServerIdentityVisuals colors,
  ) => SingleChildScrollView(
    key: const ValueKey('server-channel-content-scroll'),
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._presentationBlocks(context, copy, palette, colors),
        const SizedBox(height: AppSpacing.md),
        _board(copy, colors),
      ],
    ),
  );

  Widget _presentation(
    BuildContext context,
    AppLocalizations copy,
    AppPalette palette,
    ServerIdentityVisuals colors,
  ) => SingleChildScrollView(
    key: const ValueKey('server-channel-content-scroll'),
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _presentationBlocks(context, copy, palette, colors),
    ),
  );

  List<Widget> _presentationBlocks(
    BuildContext context,
    AppLocalizations copy,
    AppPalette palette,
    ServerIdentityVisuals colors,
  ) {
    final presenter = _inRoom ? _presenter : null;
    return [
      if (presenter != null) ...[
        _PresenterRow(person: presenter, colors: colors),
        const SizedBox(height: 12),
      ],
      _Screen(
        server: server,
        channel: channel,
        presenter: presenter,
        inRoom: _inRoom,
        colors: colors,
        compact: compact,
      ),
      // Connected and steady is the one state with nothing to say here: the
      // dock holds every control, so no empty block is reserved for it.
      if (!(_here &&
          !server.isHeld &&
          session.phase == ServerSessionPhase.connected)) ...[
        const SizedBox(height: 16),
        _action(copy, palette, colors),
      ],
      const SizedBox(height: 16),
      _MediaNotes(session: session, compact: compact),
      if (showParticipants && session.participants.isNotEmpty) ...[
        const SizedBox(height: 20),
        ServerMeetingPeople(
          participants: session.participants,
          colors: colors,
          title: copy.serverMeetingPeople,
        ),
      ],
    ];
  }

  /// The one control that starts or ends this person's participation, with
  /// every failed, blocked and in-flight state the shared session surface
  /// already names. The connected state draws nothing here: the dock owns
  /// `Mikrofon / Kamera / Udostępnij ekran / Tablica / Opuść`.
  Widget _action(
    AppLocalizations copy,
    AppPalette palette,
    ServerIdentityVisuals colors,
  ) {
    if (server.isHeld) {
      return ServerSessionHeld(copy: copy, palette: palette, colors: colors);
    }
    if (_here) {
      return ServerSessionStatus(
        session: session,
        copy: copy,
        palette: palette,
        colors: colors,
        compact: compact,
        controls: false,
      );
    }
    return ServerJoinAction(
      channel: channel,
      role: role,
      live: channel.liveness.isLive,
      copy: copy,
      colors: colors,
      onJoin: () => session.join(server, channel),
    );
  }

  Widget _whiteboard(AppLocalizations copy, ServerIdentityVisuals colors) =>
      SingleChildScrollView(
        key: const ValueKey('server-channel-content-scroll'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: _board(copy, colors),
      );

  Widget _board(AppLocalizations copy, ServerIdentityVisuals colors) =>
      ServerModuleCard(
        key: const ValueKey('server-meeting-board'),
        icon: serverChannelIcon(ServerChannelKind.whiteboard),
        title: copy.serverMeetingBoard,
        body: copy.serverMeetingBoardBody,
        colors: colors,
        channel: _boardChannel,
        onOpenChannel: onOpenChannel,
      );

  List<_MeetingTab> _tabs(AppLocalizations copy) => [
    _MeetingTab(
      ServerMeetingTab.presentation,
      ServerLocalTab(
        key: const ValueKey('server-tab-presentation'),
        label: copy.serverMeetingPresentation,
        icon: Icons.co_present_outlined,
      ),
    ),
    _MeetingTab(
      ServerMeetingTab.whiteboard,
      ServerLocalTab(
        key: const ValueKey('server-tab-whiteboard'),
        label: copy.serverChannelKindTitle(ServerChannelKind.whiteboard),
        icon: serverChannelIcon(ServerChannelKind.whiteboard),
      ),
    ),
    if (chat != null)
      _MeetingTab(
        ServerMeetingTab.chat,
        ServerLocalTab(
          key: const ValueKey('server-tab-chat'),
          label: copy.serverChat,
          icon: Icons.forum_outlined,
        ),
      ),
  ];

  /// A tab that this width does not offer (the conversation on a desktop,
  /// where it is permanently on screen) falls back to the presentation
  /// rather than leaving the strip pointing at nothing.
  int _index(List<_MeetingTab> tabs) {
    final index = tabs.indexWhere((candidate) => candidate.value == tab);
    return index < 0 ? 0 : index;
  }
}

class _MeetingTab {
  const _MeetingTab(this.value, this.tab);
  final ServerMeetingTab value;
  final ServerLocalTab tab;
}

/// The surface the shared screen is drawn on, and — when no screen is being
/// sent — the plain reason why.
class _Screen extends StatelessWidget {
  const _Screen({
    required this.server,
    required this.channel,
    required this.presenter,
    required this.inRoom,
    required this.colors,
    required this.compact,
  });
  final Server server;
  final ServerChannel channel;
  final ServerMediaParticipant? presenter;
  final bool inRoom;
  final ServerIdentityVisuals colors;
  final bool compact;

  /// A shared screen is the widest thing in the product; bounded so a 1920
  /// column does not turn it into a wall.
  static const maxHeight = 460.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Align(
      alignment: compact
          ? Alignment.center
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxHeight * 16 / 9),
        child: AspectRatio(
          key: const ValueKey('server-meeting-screen'),
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: AppRadius.md,
            child: Container(
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
              child: _body(context, palette),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppPalette palette) {
    final copy = AppLocalizations.of(context);
    final person = presenter;
    if (person != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          lk.VideoTrackRenderer(
            person.screenShareTrack!,
            key: const ValueKey('server-meeting-presentation-video'),
          ),
          PositionedDirectional(
            bottom: 10,
            start: 10,
            child: ServerMeetingNameChip(
              label: person.isLocal ? copy.serverYou : person.name,
            ),
          ),
        ],
      );
    }
    final String message;
    if (server.isHeld) {
      message = copy.serverHeldBody;
    } else if (inRoom) {
      message = copy.serverMeetingNoPresentation;
    } else if (channel.liveness.isLive) {
      message = copy.serverMeetingJoinToSee;
    } else {
      message = copy.serverQuiet(channel.kind);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // A short viewport at 200 % text leaves the surface a band. What
        // must survive is the sentence saying what is happening; the glyph
        // goes first, then the sentence itself when even two of the
        // reader's own lines do not fit.
        final height = constraints.maxHeight;
        final line = MediaQuery.textScalerOf(context).scale(16) * 1.45;
        if (height < line * 2) return const SizedBox.expand();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (height > 150) ...[
                Icon(
                  inRoom
                      ? Icons.screen_share_outlined
                      : Icons.co_present_outlined,
                  size: compact ? 36 : 48,
                  color: colors.foreground,
                ),
                const SizedBox(height: 10),
              ],
              Flexible(
                child: Text(
                  message,
                  key: const ValueKey('server-meeting-screen-state'),
                  textAlign: TextAlign.center,
                  maxLines: 3,
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
}

/// "Kamil udostępnia ekran" — named from the provider's roster, so it is the
/// person whose screen this device is actually receiving.
class _PresenterRow extends StatelessWidget {
  const _PresenterRow({required this.person, required this.colors});
  final ServerMediaParticipant person;
  final ServerIdentityVisuals colors;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final label = person.isLocal
        ? copy.serverMeetingYouSharing
        : copy.serverMeetingSharing(person.name);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('server-meeting-presenter'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadius.md,
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            UserAvatar(
              radius: 16,
              userId: person.identity,
              displayName: person.name,
              backgroundColor: colors.iconSurface,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.screen_share_outlined,
              size: 20,
              color: colors.foreground,
            ),
          ],
        ),
      ),
    );
  }
}

/// The two facts a person in a company meeting has to be told before they
/// look for a control that is not there: this device cannot start a share
/// (contract decision D), and turning your own camera on is not built yet
/// (contract §3). Both are stated, never implied by a greyed button alone.
class _MediaNotes extends StatelessWidget {
  const _MediaNotes({required this.session, required this.compact});
  final ServerSessionController session;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final share = session.screenShare;
    // Two reasons, in the order they actually bind. A device that cannot
    // capture a screen cannot do it for anybody, whatever the grant says, so
    // that is the sentence it gets. Only where the platform *can* share does
    // the grant become the reason — `deriveSessionGrant` gives
    // `screen_share` to the meeting's host alone.
    final shareNote = !share.canStartShare
        ? copy.serverShareScreenUnavailable
        : session.isConnected &&
              !(session.connection?.canPublishScreenShare ?? false)
        ? copy.serverShareScreenHostOnly
        : null;
    return Column(
      key: const ValueKey('server-meeting-notes'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (shareNote != null)
          _Note(
            icon: Icons.screen_share_outlined,
            text: shareNote,
            color: palette.textSecondary,
          ),
        if (shareNote != null) SizedBox(height: compact ? 6 : 8),
        _Note(
          icon: Icons.videocam_off_outlined,
          text: copy.serverCameraUnavailable,
          color: palette.textSecondary,
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(icon, size: 16, color: color),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: AppTypography.bodySmall.copyWith(color: color),
        ),
      ),
    ],
  );
}

/// Board 04's 2×2 tiles.
///
/// Every tile is somebody the provider reports in this generation; the grid
/// is empty before a join and can never be anything else. No number of people
/// is printed — the tiles are the roster, and nothing counts it (contract G6).
class ServerMeetingPeople extends StatelessWidget {
  const ServerMeetingPeople({
    required this.participants,
    required this.colors,
    this.title,
    super.key,
  });

  final List<ServerMediaParticipant> participants;
  final ServerIdentityVisuals colors;
  final String? title;

  /// Below this a column cannot hold two tiles side by side without the name
  /// chip being clipped, so it holds one.
  static const twoColumnWidth = 300.0;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) return const SizedBox.shrink();
    final palette = context.appPalette;
    final heading = title;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final width = constraints.maxWidth;
        final columns = width >= twoColumnWidth ? 2 : 1;
        final tile = (width - gap * (columns - 1)) / columns;
        return Column(
          key: const ValueKey('server-meeting-people'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (heading != null) ...[
              Text(
                heading,
                style: AppTypography.eyebrow.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final person in participants)
                  ServerMeetingTile(
                    key: ValueKey('server-meeting-tile-${person.identity}'),
                    person: person,
                    colors: colors,
                    width: tile,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// One participant tile: the picture that person is actually sending, or
/// their avatar when they are sending none, with the name chip and the real
/// microphone state board 04 puts on every tile.
class ServerMeetingTile extends StatelessWidget {
  const ServerMeetingTile({
    required this.person,
    required this.colors,
    required this.width,
    super.key,
  });

  final ServerMediaParticipant person;
  final ServerIdentityVisuals colors;
  final double width;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final name = person.isLocal ? copy.serverYou : person.name;
    final track = person.cameraTrack;
    return Semantics(
      label: [
        name,
        if (person.isSpeaking)
          copy.serverSpeaking
        else if (!person.isMicrophoneEnabled)
          copy.serverMicrophoneOff,
      ].join(', '),
      child: ExcludeSemantics(
        child: SizedBox(
          width: width,
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Container(
              decoration: BoxDecoration(
                color: palette.surfaceSunken,
                borderRadius: AppRadius.md,
                border: Border.all(
                  color: person.isSpeaking
                      ? palette.audioAccent
                      : palette.border,
                  width: person.isSpeaking ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: AppRadius.md,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (track != null)
                      lk.VideoTrackRenderer(
                        track,
                        key: ValueKey(
                          'server-meeting-video-${person.identity}',
                        ),
                      )
                    else
                      Center(
                        child: UserAvatar(
                          radius: (width * .16).clamp(18.0, 32.0),
                          userId: person.identity,
                          displayName: person.name,
                          backgroundColor: colors.iconSurface,
                        ),
                      ),
                    PositionedDirectional(
                      bottom: 6,
                      start: 6,
                      end: 6,
                      child: ServerMeetingNameChip(
                        label: name,
                        // The glyph is the person's real published state, not
                        // decoration: muted reads as muted on every tile.
                        icon: person.isMicrophoneEnabled
                            ? Icons.mic_rounded
                            : Icons.mic_off_rounded,
                        speaking: person.isSpeaking,
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
  }
}

/// The name over a picture — the same scrim both themes already put over
/// media, so it reads on a bright frame and a dark one alike.
class ServerMeetingNameChip extends StatelessWidget {
  const ServerMeetingNameChip({
    required this.label,
    this.icon,
    this.speaking = false,
    super.key,
  });
  final String label;
  final IconData? icon;
  final bool speaking;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: EdgeInsets.fromLTRB(icon == null ? 10 : 6, 4, 10, 4),
        decoration: BoxDecoration(
          color: palette.scrim.withValues(alpha: .74),
          borderRadius: AppRadius.pill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: speaking ? palette.audioAccent : AppColors.white,
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
