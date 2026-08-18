import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/space_identity.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_overview_screen.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/voice_room_identity.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_ended_state.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_chat_sheet.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_stage.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

class CommunityVoiceRoomScreen extends StatefulWidget {
  const CommunityVoiceRoomScreen({required this.room, super.key});

  final VoiceRoom room;

  @override
  State<CommunityVoiceRoomScreen> createState() =>
      _CommunityVoiceRoomScreenState();
}

class _CommunityVoiceRoomScreenState extends State<CommunityVoiceRoomScreen> {
  static const _background = Color(0xFF05030A);

  final _voice = VoiceCallService.instance;
  final _rooms = RoomService();
  // Single shared stream instance -- both the manual subscription below and
  // the StreamBuilder in build() listen to this same Stream, instead of
  // each calling watchParticipants() independently. Firestore's snapshots()
  // streams are broadcast, so this is safe, and it means only one live
  // listener is registered instead of two (and previously, since the
  // StreamBuilder called watchParticipants() inline in build(), every
  // setState() in this screen was tearing down and re-registering its
  // listener on every rebuild).
  late final Stream<List<RoomParticipant>> _participants;

  /// Non-null only for club-lounge rooms — the live club document that
  /// drives the club identity banner and top-bar title (board screen 6).
  late final Stream<Club>? _club = widget.room.clubId == null
      ? null
      : ClubService().watchClub(widget.room.clubId!);
  StreamSubscription<List<RoomParticipant>>? _participantSubscription;
  bool _joinedDocumentSeen = false;
  bool _leaving = false;
  bool _roomOver = false;
  bool _showCompactChat = false;

  /// Guards the server confirmation below against re-entry while an
  /// in-flight check is pending (the roster stream keeps emitting).
  bool _confirmingRemoval = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _isHost => _uid == widget.room.hostId;
  bool get _isClubRoom => widget.room.isClubRoom;

  @override
  void initState() {
    super.initState();
    _voice.addListener(_refresh);
    _participants = _rooms.watchParticipants(widget.room.id);
    _participantSubscription = _participants.listen(_handleParticipantState);
    unawaited(_connect());
  }

  @override
  void dispose() {
    _participantSubscription?.cancel();
    _voice.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _connect() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final name = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : user.email?.split('@').first ?? 'YO Voice user';
    try {
      if (_voice.roomId != widget.room.id || !_voice.isConnected) {
        await _voice.join(
          roomId: widget.room.id,
          roomName: widget.room.name,
          participantName: name,
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_voice.errorMessage ?? 'Could not join voice.')),
      );
    }
  }

  Future<void> _handleParticipantState(
    List<RoomParticipant> participants,
  ) async {
    final own = participants.where((participant) => participant.userId == _uid);
    if (own.isNotEmpty) {
      _joinedDocumentSeen = true;
      final participant = own.first;
      // ONE-WAY enforcement: a moderator's mute must reach the real
      // microphone, but a (possibly stale) unmuted doc must never
      // auto-unmute someone — that raced the user's own Mute tap and
      // instantly reverted it (doc write lands after the local toggle).
      if (participant.isMuted && !_voice.isMuted && _voice.isConnected) {
        await _voice.setMuted(true);
      }
      return;
    }

    if (_joinedDocumentSeen && mounted && !_leaving && !_confirmingRemoval) {
      // The roster stream can emit CACHE-sourced snapshots, so a missing
      // own-document is only a HINT that we were removed — confirm with
      // the server before ejecting anyone (docs/Bugs.md: a host was
      // ejected from a still-live room on a transient snapshot).
      _confirmingRemoval = true;
      final removed = await _rooms.isParticipantRemovedOnServer(
        roomId: widget.room.id,
        userId: _uid,
      );
      _confirmingRemoval = false;
      if (!removed || !mounted || _leaving) return;

      // Removed by the host, or the room ended: cut the audio and show
      // the ended state instead of ejecting with a snackbar.
      _leaving = true;
      await _voice.disconnect();
      if (!mounted) return;
      setState(() => _roomOver = true);
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    await _voice.disconnect();
    // Club lounges get the lounge bookkeeping (isLive drops when the
    // last member leaves) — plain leaveRoom left lounges "live" forever.
    final clubId = widget.room.clubId;
    if (clubId != null) {
      await _rooms.leaveClubLounge(clubId);
    } else {
      await _rooms.leaveRoom(widget.room.id);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _openClubOverview() {
    final clubId = widget.room.clubId;
    if (clubId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClubOverviewScreen(clubId: clubId),
      ),
    );
  }

  Future<void> _toggleMute() async {
    await _voice.toggleMute();
    await _rooms.setMuted(roomId: widget.room.id, isMuted: _voice.isMuted);
  }

  /// The mic can't publish right now — say why instead of a dead tap.
  void _explainMicState() {
    final message = switch (_voice.micState) {
      MicState.connecting => 'Connecting to live audio…',
      MicState.listenOnly =>
        "You're listening — the host controls who can speak here.",
      MicState.unavailable =>
        _voice.errorMessage ??
            'Live audio is not connected. Leave and rejoin to retry.',
      MicState.on || MicState.muted => '',
    };
    if (message.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // One People drawer for the whole room — sections instead of two
  // separate speaker/listener sheets (the sheet sorts host → speakers →
  // listeners and labels roles per row).
  void _openParticipants(List<RoomParticipant> participants) {
    final ordered = [...participants]
      ..sort((a, b) {
        int rank(RoomParticipant p) => p.isHost
            ? 0
            : p.isSpeaker
            ? 1
            : 2;
        final byRank = rank(a).compareTo(rank(b));
        if (byRank != 0) return byRank;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ParticipantsSheet(
        title: 'People · ${participants.length}',
        participants: ordered,
        hostId: widget.room.hostId,
        currentUserId: _uid,
        canModerate: _isHost,
        onMute: (participant, muted) async {
          await _rooms.moderateParticipantMute(
            roomId: widget.room.id,
            participantId: participant.userId,
            isMuted: muted,
          );
        },
        onRemove: (participant) async {
          await _rooms.removeParticipant(
            roomId: widget.room.id,
            participantId: participant.userId,
          );
        },
      ),
    );
  }

  /// Rooms 2.0 stage: identity card + a calm speaker grid + the
  /// audience as a strip. Live speaking state and audio levels come from
  /// LiveKit ([_voice.participants], matched by uid identity); roles and
  /// mute flags come from the Firestore roster. Listeners never render
  /// on the stage — a room with 500 listeners paints the same number of
  /// widgets as a room with 5.
  Widget _buildStage(List<RoomParticipant> roomParticipants, Club? club) {
    final identity = voiceRoomIdentity(widget.room, club: club);
    final voiceByIdentity = {
      for (final v in _voice.participants) v.identity: v,
    };

    final stageSpeakers = [
      for (final p in roomParticipants.where((p) => p.isSpeaker || p.isHost))
        StageSpeaker(
          userId: p.userId,
          displayName: p.displayName,
          photoUrl: p.photoUrl,
          isHost: p.isHost,
          isMuted: p.isMuted,
          isSpeaking: voiceByIdentity[p.userId]?.isSpeaking ?? false,
          audioLevel: voiceByIdentity[p.userId]?.audioLevel ?? 0,
        ),
    ];
    final listeners = roomParticipants
        .where((p) => !p.isSpeaker && !p.isHost)
        .toList(growable: false);
    final anyoneSpeaking = stageSpeakers.any((s) => s.isSpeaking);

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
      children: [
        RoomIdentityCard(
          roomName: widget.room.name,
          topic: widget.room.description.trim().isNotEmpty
              ? widget.room.description
              : club?.description.trim().isNotEmpty == true
              ? club!.description
              : widget.room.category,
          identity: identity,
          imageUrl: widget.room.imageUrl ?? club?.bannerUrl,
          quiet: !anyoneSpeaking,
          trailing: club == null
              ? null
              : IconButton(
                  tooltip: club.isFamilyRoom
                      ? 'Open family space'
                      : 'Open club',
                  onPressed: _openClubOverview,
                  color: identity.accent,
                  icon: const Icon(Icons.arrow_outward_rounded, size: 20),
                ),
        ),
        const SizedBox(height: 14),
        RoomStagePanel(
          speakers: stageSpeakers,
          identity: identity,
          onOverflowTap: () => _openParticipants(_latestParticipants),
          onSpeakerTap: (speaker) => showProfilePreview(
            context,
            userId: speaker.userId,
            displayName: speaker.displayName,
            photoUrl: speaker.photoUrl,
          ),
        ),
        const SizedBox(height: 12),
        ListenersStrip(
          count: listeners.length,
          identity: identity,
          onTap: () => _openParticipants(_latestParticipants),
          previewPhotoUrls: [for (final l in listeners.take(4)) l.photoUrl],
          previewNames: [for (final l in listeners.take(4)) l.displayName],
        ),
      ],
    );
  }

  List<RoomParticipant> _latestParticipants = const [];

  void _openChat() {
    if (RoomWorkspace.usesDesktopLayout(context)) return;
    setState(() => _showCompactChat = true);
  }

  @override
  Widget build(BuildContext context) {
    final clubStream = _club;
    if (clubStream == null) return _buildRoom(null);
    return StreamBuilder<Club>(
      stream: clubStream,
      builder: (context, snapshot) => _buildRoom(snapshot.data),
    );
  }

  Widget _buildRoom(Club? club) {
    final identity = voiceRoomIdentity(widget.room, club: club);
    final desktop = RoomWorkspace.usesDesktopLayout(context);
    return StreamBuilder<List<RoomParticipant>>(
      stream: _participants,
      builder: (context, snapshot) {
        final roomParticipants = snapshot.data ?? const <RoomParticipant>[];
        _latestParticipants = roomParticipants;
        final speaking = roomParticipants
            .where((participant) => participant.isSpeaker)
            .length;
        final listeners = roomParticipants.length - speaking;

        if (_roomOver) {
          return Scaffold(
            backgroundColor: _background,
            body: SafeArea(child: RoomEndedState(roomName: widget.room.name)),
          );
        }

        return Scaffold(
          backgroundColor: _background,
          body: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -1.05),
                      radius: 1.15,
                      colors: [
                        identity.primary.withValues(alpha: .13),
                        _background,
                      ],
                      stops: const [0, .72],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: _TopBar(
                          roomName: club?.name ?? widget.room.name,
                          subtitle: club?.isFamilyRoom == true
                              ? 'FAMILY ROOM'
                              : _isClubRoom
                              ? 'CLUB ROOM'
                              : null,
                          avatarUrl: club?.avatarUrl,
                          avatarName: club?.name,
                          identity: identity,
                          status: _voice.status,
                          speaking: speaking,
                          listeners: listeners,
                          onBack: () => Navigator.of(context).pop(),
                          onSpeakingTap: () =>
                              _openParticipants(roomParticipants),
                          onListenersTap: () =>
                              _openParticipants(roomParticipants),
                        ),
                      ),
                    ),
                    Expanded(
                      child: RoomWorkspace(
                        showCompactChat: _showCompactChat,
                        stage: _buildStage(roomParticipants, club),
                        chat: RoomChatPanel(
                          roomId: widget.room.id,
                          isHost: _isHost,
                          accent: identity.primary,
                          currentUserId: _uid,
                          onClose: desktop
                              ? null
                              : () => setState(() => _showCompactChat = false),
                        ),
                      ),
                    ),
                    _BottomControls(
                      identity: identity,
                      micState: _voice.micState,
                      busy: _voice.muteChangeInProgress,
                      onMute: _toggleMute,
                      onLeave: _leave,
                      onMicBlocked: _explainMicState,
                      onChat: _openChat,
                      onPeople: () => _openParticipants(_latestParticipants),
                      showChat: !desktop,
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
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.roomName,
    required this.status,
    required this.speaking,
    required this.listeners,
    required this.onBack,
    required this.onSpeakingTap,
    required this.onListenersTap,
    required this.identity,
    this.subtitle,
    this.avatarUrl,
    this.avatarName,
  });

  final String roomName;
  final VoiceCallStatus status;
  final int speaking;
  final int listeners;
  final VoidCallback onBack;
  final VoidCallback onSpeakingTap;
  final VoidCallback onListenersTap;
  final SpaceIdentity identity;

  /// Club rooms label themselves ("Club Room") instead of the generic
  /// connection status line.
  final String? subtitle;
  final String? avatarUrl;
  final String? avatarName;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        final identityRow = Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
              color: Colors.white,
            ),
            if (avatarName != null) ...[
              UserAvatar(
                radius: 17,
                photoUrl: avatarUrl,
                displayName: avatarName,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    roomName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    subtitle ?? _statusText(status),
                    style: TextStyle(
                      color: identity.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (!narrow) ...[
              _CounterPill(
                label: 'Speaking',
                value: speaking,
                identity: identity,
                onTap: onSpeakingTap,
              ),
              const SizedBox(width: 8),
              _CounterPill(
                label: 'Listeners',
                value: listeners,
                identity: identity,
                onTap: onListenersTap,
              ),
            ],
          ],
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 6),
          child: Column(
            children: [
              identityRow,
              if (narrow) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const SizedBox(width: 48),
                    Expanded(
                      child: _CounterPill(
                        label: 'Speaking',
                        value: speaking,
                        identity: identity,
                        onTap: onSpeakingTap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CounterPill(
                        label: 'Listeners',
                        value: listeners,
                        identity: identity,
                        onTap: onListenersTap,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _statusText(VoiceCallStatus status) => switch (status) {
    VoiceCallStatus.connected => 'COMMUNITY LIVE',
    VoiceCallStatus.connecting => 'CONNECTING…',
    VoiceCallStatus.reconnecting => 'RECONNECTING…',
    VoiceCallStatus.failed => 'CONNECTION FAILED',
    VoiceCallStatus.disconnected => 'OFFLINE',
  };
}

class _CounterPill extends StatelessWidget {
  const _CounterPill({
    required this.label,
    required this.value,
    required this.onTap,
    required this.identity,
  });

  final String label;
  final int value;
  final VoidCallback onTap;
  final SpaceIdentity identity;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF171020).withValues(alpha: .86),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: identity.outline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFAFA3BA),
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.micState,
    required this.busy,
    required this.onMute,
    required this.onLeave,
    required this.onMicBlocked,
    required this.onChat,
    required this.onPeople,
    required this.identity,
    this.showChat = true,
  });

  final MicState micState;
  final bool busy;
  final Future<void> Function() onMute;
  final Future<void> Function() onLeave;
  final VoidCallback onChat;
  final VoidCallback onPeople;
  final SpaceIdentity identity;
  final bool showChat;

  /// Tapping the mic while it genuinely can't publish explains WHY
  /// instead of silently doing nothing.
  final VoidCallback onMicBlocked;

  @override
  Widget build(BuildContext context) {
    // Every MicState is a visually distinct button — the mic must never
    // look "permanently pressed" or dead while it actually works.
    final (icon, label, style, tappable) = switch (micState) {
      MicState.on => (Icons.mic_rounded, 'Mute', _MicStyle.live, true),
      MicState.muted => (
        Icons.mic_off_rounded,
        'Unmute',
        _MicStyle.muted,
        true,
      ),
      MicState.connecting => (
        Icons.mic_rounded,
        'Connecting…',
        _MicStyle.waiting,
        false,
      ),
      MicState.listenOnly => (
        Icons.headphones_rounded,
        'Listening',
        _MicStyle.info,
        true,
      ),
      MicState.unavailable => (
        Icons.mic_off_rounded,
        'Audio off',
        _MicStyle.error,
        true,
      ),
    };

    return Container(
      padding: EdgeInsets.fromLTRB(
        MediaQuery.sizeOf(context).width < 360 ? 10 : 22,
        12,
        MediaQuery.sizeOf(context).width < 360 ? 10 : 22,
        20,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF09050F).withValues(alpha: .96),
        border: const Border(top: BorderSide(color: Color(0xFF2B1937))),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Row(
            children: [
              Expanded(
                child: _RoundControl(
                  icon: icon,
                  label: label,
                  enabled: tappable && !busy,
                  micStyle: style,
                  identity: identity,
                  showSpinner: micState == MicState.connecting,
                  onTap: micState == MicState.on || micState == MicState.muted
                      ? onMute
                      : () async => onMicBlocked(),
                ),
              ),
              if (showChat) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: _RoundControl(
                    icon: Icons.forum_rounded,
                    label: 'Chat',
                    enabled: true,
                    micStyle: _MicStyle.info,
                    identity: identity,
                    onTap: () async => onChat(),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Expanded(
                child: _RoundControl(
                  icon: Icons.groups_rounded,
                  label: 'People',
                  enabled: true,
                  micStyle: _MicStyle.waiting,
                  identity: identity,
                  onTap: () async => onPeople(),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _RoundControl(
                  icon: Icons.call_end_rounded,
                  label: 'Leave',
                  enabled: true,
                  micStyle: _MicStyle.danger,
                  identity: identity,
                  onTap: onLeave,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _MicStyle { live, muted, waiting, info, error, danger }

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.micStyle,
    required this.identity,
    this.showSpinner = false,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final Future<void> Function() onTap;
  final _MicStyle micStyle;
  final SpaceIdentity identity;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    // Muted is a bright, obviously-tappable amber — never the old
    // near-background dark that read as a disabled button.
    final color = switch (micStyle) {
      _MicStyle.live => identity.primary,
      _MicStyle.muted => const Color(0xFFB3801A),
      _MicStyle.waiting => const Color(0xFF3A2C49),
      _MicStyle.info => const Color(0xFF2A5A8A),
      _MicStyle.error => const Color(0xFF7A2436),
      _MicStyle.danger => const Color(0xFFFF3C68),
    };
    return Opacity(
      // Even "waiting" stays near-opaque: a briefly-connecting mic must
      // not read as a permanently dead control.
      opacity: enabled ? 1 : .8,
      child: InkWell(
        onTap: () => onTap(),
        borderRadius: BorderRadius.circular(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: micStyle == _MicStyle.live
                    ? const [
                        BoxShadow(
                          color: Color(0x88B62CFF),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: showSpinner
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white70,
                      ),
                    )
                  : Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParticipantsSheet extends StatefulWidget {
  const _ParticipantsSheet({
    required this.title,
    required this.participants,
    required this.hostId,
    required this.currentUserId,
    required this.canModerate,
    required this.onMute,
    required this.onRemove,
  });

  final String title;
  final List<RoomParticipant> participants;
  final String hostId;
  final String currentUserId;
  final bool canModerate;
  final Future<void> Function(RoomParticipant participant, bool muted) onMute;
  final Future<void> Function(RoomParticipant participant) onRemove;

  @override
  State<_ParticipantsSheet> createState() => _ParticipantsSheetState();
}

class _ParticipantsSheetState extends State<_ParticipantsSheet> {
  String? _busyId;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .72,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF120B18),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Color(0xFF503064))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF5D4C66),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.title} · ${widget.participants.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
          Flexible(
            child: widget.participants.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(36),
                    child: Text(
                      'Nobody is here yet.',
                      style: TextStyle(color: Color(0xFFB6A9C2)),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 26),
                    itemCount: widget.participants.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Color(0xFF2E2037), height: 1),
                    itemBuilder: (context, index) {
                      final participant = widget.participants[index];
                      final host = participant.userId == widget.hostId;
                      final self = participant.userId == widget.currentUserId;
                      final canAct = widget.canModerate && !host && !self;
                      final busy = _busyId == participant.userId;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 6,
                        ),
                        leading: CircleAvatar(
                          radius: 23,
                          backgroundColor: const Color(0xFF7135A5),
                          child: Text(
                            participant.displayName.isEmpty
                                ? '?'
                                : participant.displayName[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        title: Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              self
                                  ? '${participant.displayName} (you)'
                                  : participant.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            UserIdentityBadges(uid: participant.userId),
                          ],
                        ),
                        subtitle: Text(
                          host
                              ? 'Community owner'
                              : participant.isMuted
                              ? 'Muted'
                              : participant.isSpeaker
                              ? 'Speaking'
                              : 'Listening',
                          style: const TextStyle(color: Color(0xFFB6A9C2)),
                        ),
                        trailing: canAct
                            ? PopupMenuButton<String>(
                                enabled: !busy,
                                color: const Color(0xFF21142A),
                                icon: busy
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.more_vert_rounded,
                                        color: Colors.white,
                                      ),
                                onSelected: (action) async {
                                  setState(() => _busyId = participant.userId);
                                  try {
                                    if (action == 'mute') {
                                      await widget.onMute(
                                        participant,
                                        !participant.isMuted,
                                      );
                                    } else if (action == 'remove') {
                                      await widget.onRemove(participant);
                                      if (!context.mounted) return;
                                      Navigator.of(context).pop();
                                    }
                                  } finally {
                                    if (mounted) setState(() => _busyId = null);
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'mute',
                                    child: Text(
                                      participant.isMuted
                                          ? 'Allow microphone'
                                          : 'Mute participant',
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'remove',
                                    child: Text(
                                      'Remove from room',
                                      style: TextStyle(
                                        color: Color(0xFFFF6688),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Icon(
                                participant.isMuted
                                    ? Icons.mic_off_rounded
                                    : participant.isSpeaker
                                    ? Icons.graphic_eq_rounded
                                    : Icons.headphones_rounded,
                                color: const Color(0xFFC277FF),
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
