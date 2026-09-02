import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/space_identity.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_overview_screen.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/room_voice_access.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_leave_coordinator.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/data/services/room_mute_coordinator.dart';
import 'package:yovoice/features/rooms/data/services/room_voice_entry_coordinator.dart';
import 'package:yovoice/features/rooms/presentation/room_mic_affordance.dart';
import 'package:yovoice/features/rooms/presentation/voice_room_identity.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_control_dock.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_ended_state.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_chat_sheet.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_header.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_hero_banner.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_stage.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

class CommunityVoiceRoomScreen extends StatefulWidget {
  const CommunityVoiceRoomScreen({
    required this.room,
    this.voiceEntry,
    this.roomService,
    this.voiceService,
    this.entryCoordinator,
    this.muteCoordinator,
    this.clubService,
    this.playInitialJoinSound = true,
    this.startMuted = true,
    super.key,
  });

  final VoiceRoom room;

  /// What [RoomEntryScreen] already resolved about this room's voice
  /// session: whether it is live, and whether THIS account holds the
  /// authority the deployed rules require to start it. Null means nothing
  /// was resolved, which is treated as "no authority" — the screen never
  /// invents a start control it cannot back up.
  final RoomVoiceEntry? voiceEntry;

  /// Test seams. All five default to the production wiring.
  final RoomService? roomService;
  final VoiceCallService? voiceService;
  final RoomVoiceEntryCoordinator? entryCoordinator;
  final RoomMuteCoordinator? muteCoordinator;
  final ClubService? clubService;

  /// Room creation already has its own confirmation; all other entry points
  /// keep the normal connected cue.
  final bool playInitialJoinSound;

  /// Room entry is mic-safe until the person deliberately unmutes.
  final bool startMuted;

  @override
  State<CommunityVoiceRoomScreen> createState() =>
      _CommunityVoiceRoomScreenState();
}

class _CommunityVoiceRoomScreenState extends State<CommunityVoiceRoomScreen> {
  static const _background = Color(0xFF05030A);

  late final VoiceCallService _voice =
      widget.voiceService ?? VoiceCallService.instance;
  late final RoomService _rooms = widget.roomService ?? RoomService();
  late final RoomVoiceEntryCoordinator _entryCoordinator =
      widget.entryCoordinator ??
      RoomVoiceEntryCoordinator.production(rooms: _rooms);
  final _leaveCoordinator = RoomLeaveCoordinator();
  late final RoomMuteCoordinator _muteCoordinator =
      widget.muteCoordinator ?? RoomMuteCoordinator.production;

  /// The resolved voice state. Seeded from what the entry screen decided and
  /// then kept current by the room document stream below, so a host starting
  /// or ending voice elsewhere is reflected here without a rejoin.
  late RoomVoiceEntry _entry =
      widget.voiceEntry ?? RoomVoiceEntry.unresolved(widget.room);

  /// Whether a LiveKit token may legitimately be requested right now.
  /// `createLiveKitToken` refuses one unless the room document says
  /// `status == 'active' && isLive == true`, so this gates every connect.
  late bool _live = _entry.voiceIsLive;
  StreamSubscription<VoiceRoom>? _roomSubscription;
  bool _startingVoice = false;
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
      : (widget.clubService ?? ClubService()).watchClub(widget.room.clubId!);
  StreamSubscription<List<RoomParticipant>>? _participantSubscription;
  bool _joinedDocumentSeen = false;
  bool _leaving = false;
  bool _roomOver = false;
  // Chat opens as a compact bottom dock after entry. Closing it keeps the
  // stage visible, and the dock control below reopens the same surface.
  bool _showCompactChat = true;

  /// Guards the server confirmation below against re-entry while an
  /// in-flight check is pending (the roster stream keeps emitting).
  bool _confirmingRemoval = false;

  String get _uid => _rooms.currentUserId;
  bool get _isHost => _uid == widget.room.hostId;
  bool get _isClubRoom => widget.room.isClubRoom;

  @override
  void initState() {
    super.initState();
    _muteCoordinator.addListener(_refresh);
    _voice.addListener(_refresh);
    _participants = _rooms.watchParticipants(widget.room.id);
    _participantSubscription = _participants.listen(_handleParticipantState);
    _roomSubscription = _rooms
        .watchRoom(widget.room.id)
        .listen(_handleRoomState, onError: (Object _) {});
    // Only a live room may be connected. Entering a dormant one and asking
    // for a token anyway is exactly the "This room is not currently live."
    // failure this screen used to produce.
    if (_live) {
      unawaited(_connect(playSound: widget.playInitialJoinSound));
    }
    _announceEntryFailure();
  }

  /// A refused entry must not be silent. The affordance already explains
  /// itself on tap, but arriving in a room that could not be opened deserves
  /// to say so once, up front, in the server's own product copy.
  void _announceEntryFailure() {
    final message = _entry.message;
    if (_entry.outcome != RoomVoiceEntryOutcome.failed || message == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  void dispose() {
    _participantSubscription?.cancel();
    _roomSubscription?.cancel();
    // The mute coordinator is a process-wide singleton; a listener left
    // registered here outlives the screen and rebuilds a disposed State.
    _muteCoordinator.removeListener(_refresh);
    _voice.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Whether an AUTOMATIC audio action from this screen is legitimate.
  ///
  /// [VoiceCallService] is process-wide and a room screen stays MOUNTED
  /// beneath a pushed route, so room A's liveness listener would otherwise
  /// reach into the session the user is having in room B — `join()`
  /// disconnects whatever is connected, so A going live yanked B's audio, and
  /// A going dormant hung B up. A user-initiated start may still take the
  /// session over: that is intent. A background document change is not.
  bool get _mayAutoConnectAudio {
    final connected = _voice.roomId;
    if (connected == widget.room.id) return true;
    if (connected != null) return false;
    // Nothing is connected: only the screen actually in front of the user
    // may claim the session.
    if (!mounted) return false;
    return ModalRoute.of(context)?.isCurrent ?? true;
  }

  /// This screen may only cut audio it actually owns. Deliberately NOT
  /// route-gated: a moderator ending the room has to reach the microphone
  /// even while a sheet or profile preview sits on top.
  bool get _ownsAudioSession => _voice.roomId == widget.room.id;

  /// A process-wide voice service can move to another room while the roster
  /// write is awaiting the server. Every continuation of this room's mute
  /// operation must therefore prove it still owns the same audio session.
  bool _isCurrentMuteOperation(String roomId) =>
      mounted &&
      !_leaving &&
      !_roomOver &&
      _live &&
      _voice.isRoomSession &&
      _voice.roomId == roomId;

  /// The room document is the authority on liveness, and it moves while
  /// people are on this screen: a host can end voice, and a member with
  /// start authority can begin it. Following it means someone waiting in a
  /// dormant room is connected the moment it opens, instead of having to
  /// leave and come back.
  void _handleRoomState(VoiceRoom room) {
    final copy = AppLocalizations.of(context);
    // A closed, archived, suspended or half-deleted room is NOT "dormant" —
    // dormant means "no session yet, one could start". Collapsing the two
    // put a Start control on an ended room for anyone who never held a
    // participant row, which snackbarred "This room has ended." and then
    // restored the button on the next snapshot: the exact dead control this
    // path exists to remove.
    final gone = !room.isActive || room.deletionInProgress;
    final live = room.isLive && !gone;
    final wasLive = _live;
    _live = live;
    if (mounted) {
      setState(() {
        _entry = _entry.copyWith(
          room: room,
          outcome: gone
              ? RoomVoiceEntryOutcome.unavailable
              : live
              ? _entry.outcome == RoomVoiceEntryOutcome.started
                    ? RoomVoiceEntryOutcome.started
                    : RoomVoiceEntryOutcome.live
              : RoomVoiceEntryOutcome.dormant,
          // Clear any stale failure copy: it described a moment that has
          // passed, and it is what the control would explain on tap.
          message: gone
              ? (room.deletionInProgress
                    ? copy.text(
                        'This room is being deleted.',
                        'Ten pokój jest usuwany.',
                      )
                    : copy.text(
                        'This room has ended.',
                        'Ten pokój już się zakończył.',
                      ))
              : null,
        );
      });
    }
    if (live == wasLive) return;
    if (live) {
      // Someone else opened the mics. Re-run the shared entry path rather
      // than connecting directly: this account may still have no participant
      // row, and the token function refuses a caller who has not joined.
      if (_mayAutoConnectAudio) unawaited(_enterVoice());
    } else if (_ownsAudioSession) {
      unawaited(_voice.disconnect(playSound: false));
    }
  }

  /// The ONE path that turns voice on from this screen, used both by the
  /// "Start voice" control and by the room going live underneath us. It
  /// performs the liveness transition and the roster join in the order the
  /// server requires, and only then connects audio.
  Future<void> _enterVoice() async {
    // A room-document emission can still be in flight when the screen is
    // torn down; setState on a disposed State would throw from a listener
    // nobody is left to catch.
    if (_startingVoice || !mounted) return;
    setState(() => _startingVoice = true);
    try {
      final entry = await _entryCoordinator.enter(_entry.room);
      if (!mounted) return;
      setState(() {
        _entry = entry;
        _live = entry.voiceIsLive;
      });
      if (entry.voiceIsLive) {
        await _connect();
        return;
      }
      final message = entry.message;
      if (message != null && mounted) {
        final copy = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                copy.isPolish
                    ? 'Nie udało się uruchomić rozmowy głosowej. Spróbuj ponownie.'
                    : message,
              ),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _startingVoice = false);
    }
  }

  Future<void> _connect({bool playSound = true}) async {
    // Structural guard: no token request may leave this screen while the
    // room document says the session does not exist.
    if (!_live) return;
    final name = _rooms.currentUserLabel;
    if (_uid.isEmpty) return;
    try {
      if (_voice.roomId != widget.room.id || !_voice.isConnected) {
        await _voice.join(
          roomId: widget.room.id,
          roomName: widget.room.name,
          participantName: name,
          playSound: playSound,
          startMuted: widget.startMuted,
        );
      }
    } catch (_) {
      if (!mounted) return;
      final copy = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            copy.isPolish
                ? 'Nie udało się dołączyć do rozmowy głosowej.'
                : _voice.errorMessage ?? 'Could not join voice.',
          ),
        ),
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
      if (participant.isMuted &&
          !_voice.isMuted &&
          _voice.isConnected &&
          _ownsAudioSession) {
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
      // Only cut audio if it is THIS room's. Being removed from a room the
      // user left open underneath must not hang up the room they are in.
      if (_ownsAudioSession) await _voice.disconnect();
      if (!mounted) return;
      setState(() => _roomOver = true);
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    final clubId = widget.room.clubId;
    await _leaveCoordinator.leave(
      disconnectAudio: _voice.disconnect,
      navigateAway: () {
        if (mounted) Navigator.of(context).pop();
      },
      // Club lounges get lounge bookkeeping (isLive drops when the last
      // member leaves). Cleanup is idempotent and must not delay navigation.
      cleanupParticipant: () => clubId != null
          ? _rooms.leaveClubLounge(clubId)
          : _rooms.leaveRoom(widget.room.id),
      onCleanupError: (error, _) => debugPrint(
        'Room leave cleanup will rely on server reconciliation: $error',
      ),
    );
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
    // A mute toggle persists through `setOwnRoomParticipantMute`, which the
    // server refuses on a room that is not live. The affordance already
    // prevents this call; the guard keeps it true if a future caller forgets.
    final roomId = widget.room.id;
    if (!_isCurrentMuteOperation(roomId)) return;
    final outcome = await _muteCoordinator.toggle(
      roomId: roomId,
      isOperationCurrent: () => _isCurrentMuteOperation(roomId),
    );
    if (!mounted) return;
    final copy = AppLocalizations.of(context);
    // A valid session-ended outcome disconnects this room before returning,
    // so `roomId == null` is expected. A non-null replacement belongs to a
    // different room and must not receive this screen's UI/leave side effects.
    if (outcome == RoomMuteOutcome.sessionEnded) {
      if (_voice.roomId != null && !_isCurrentMuteOperation(roomId)) return;
    } else if (!_isCurrentMuteOperation(roomId)) {
      return;
    }
    switch (outcome) {
      case RoomMuteOutcome.applied:
      case RoomMuteOutcome.busy:
        break;
      case RoomMuteOutcome.mutedLocally:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                copy.text(
                  "You're muted. Room status couldn't sync; try again.",
                  'Mikrofon jest wyciszony. Nie udało się zsynchronizować statusu pokoju — spróbuj ponownie.',
                ),
              ),
            ),
          );
      case RoomMuteOutcome.sessionEnded:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                copy.text(
                  'This room is no longer live.',
                  'Ten pokój nie jest już na żywo.',
                ),
              ),
            ),
          );
        await _leave();
      case RoomMuteOutcome.failed:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                copy.text(
                  'Could not change microphone state. Try again.',
                  'Nie udało się zmienić stanu mikrofonu. Spróbuj ponownie.',
                ),
              ),
            ),
          );
    }
  }

  /// The mic can't publish right now — say why instead of a dead tap.
  void _explainMicState(RoomMicAffordance affordance) {
    final copy = AppLocalizations.of(context);
    final message = switch (affordance) {
      RoomMicAffordance.connecting => copy.text(
        'Connecting to live audio…',
        'Łączenie z rozmową na żywo…',
      ),
      RoomMicAffordance.listenOnly => copy.text(
        "You're listening — the host controls who can speak here.",
        'Słuchasz — gospodarz decyduje, kto może zabrać głos.',
      ),
      // Honest, and never a permission code: this account genuinely cannot
      // open the mics here, and saying so is the whole point.
      RoomMicAffordance.waitingForHost =>
        copy.isPolish
            ? 'Rozmowa głosowa jeszcze się nie rozpoczęła. Poczekaj na gospodarza.'
            : _entry.message ?? _entry.authority.waitingExplanation,
      RoomMicAffordance.unavailable =>
        copy.isPolish
            ? 'Brak połączenia z rozmową na żywo. Wyjdź i dołącz ponownie.'
            : _voice.errorMessage ??
                  'Live audio is not connected. Leave and rejoin to retry.',
      RoomMicAffordance.live ||
      RoomMicAffordance.muted ||
      RoomMicAffordance.startVoice => '',
    };
    if (message.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // One People drawer for the whole Community room. There is no stage versus
  // listener hierarchy here: the host is first, then everybody else by name.
  void _openParticipants(List<RoomParticipant> participants) {
    final copy = AppLocalizations.of(context);
    final ordered = [...participants]
      ..sort((a, b) {
        int rank(RoomParticipant p) => p.isHost ? 0 : 1;
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
      showDragHandle: false,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 720,
      ),
      builder: (context) => _ParticipantsSheet(
        title: copy.text('People here', 'Osoby w pokoju'),
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

  /// Community presence: one Discord-like people grid. Live speaking state
  /// and audio levels come from LiveKit; identity, host role and moderation
  /// state come from the Firestore roster. Legacy `listener` rows are still
  /// rendered as normal room members because Community has no audience role.
  Widget _buildStage(List<RoomParticipant> roomParticipants, Club? club) {
    final copy = AppLocalizations.of(context);
    final identity = voiceRoomIdentity(widget.room, club: club);
    final voiceByIdentity = {
      for (final v in _voice.participants) v.identity: v,
    };

    final roomPeople = [
      for (final p in roomParticipants)
        StageSpeaker(
          userId: p.userId,
          displayName: p.displayName,
          photoUrl: p.photoUrl,
          isHost: p.isHost,
          isMuted: p.isMuted,
          isSpeaking: voiceByIdentity[p.userId]?.isSpeaking ?? false,
          audioLevel: voiceByIdentity[p.userId]?.audioLevel ?? 0,
          roleLabel: copy.text('Member', 'Członek'),
        ),
    ];

    // WIDE LAYOUTS GIVE THE STAGE THE LEFTOVER HEIGHT.
    //
    // As a plain ListView the three panels stacked at the top and left a
    // dead band beneath the audience strip — a 1440x900 room wasted roughly
    // a third of its main column, and one host read as a small card adrift
    // in a wide box. With a bounded height available, the hero and the
    // audience strip keep their natural size and the stage takes the rest,
    // so the speakers sit optically centred in a panel that looks intended.
    //
    // The scrolling list stays for narrow and SHORT viewports, where there
    // is no leftover height to give away and the content must be reachable.
    final media = MediaQuery.sizeOf(context);
    // 700, not 900: a 768-wide tablet has no side chat panel and 1024px of
    // height, and the scrolling fallback left ~40% of it as the exact dead
    // band this layout exists to remove. Anything narrower is a phone,
    // where the scroll is the right shape.
    final canFillStage = media.width >= 700 && media.height >= 720;

    final hero = RoomHeroBanner(
      identity: identity,
      title: widget.room.name,
      topic: widget.room.description.trim().isNotEmpty
          ? widget.room.description
          : club?.description.trim().isNotEmpty == true
          ? club!.description
          : widget.room.category,
      imageUrl: widget.room.imageUrl ?? club?.bannerUrl,
      action: club == null
          ? null
          : RoomHeroLinkAction(
              label: club.isFamilyRoom
                  ? copy.text('Open family space', 'Otwórz przestrzeń rodzinną')
                  : copy.text('View club', 'Zobacz klub'),
              onTap: _openClubOverview,
              identity: identity,
              // Width alone decides. The family room previously forced
              // the icon-only variant at EVERY width, leaving a lone ↗ in
              // a wide hero that read as decoration, not a control.
              compact: media.width < 520,
            ),
    );
    RoomStagePanel stage({required bool fill}) => RoomStagePanel(
      speakers: roomPeople,
      identity: identity,
      fill: fill,
      title: copy.text('People here', 'Osoby w pokoju'),
      emptyMessage: copy.text(
        'Join the room to start the conversation.',
        'Dołącz do pokoju, aby rozpocząć rozmowę.',
      ),
      icon: Icons.groups_rounded,
      onOverflowTap: () => _openParticipants(_latestParticipants),
      onSpeakerTap: (speaker) => showProfilePreview(
        context,
        userId: speaker.userId,
        displayName: speaker.displayName,
        photoUrl: speaker.photoUrl,
      ),
    );

    if (canFillStage) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            hero,
            const SizedBox(height: 14),
            Expanded(child: stage(fill: true)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
      children: [hero, const SizedBox(height: 14), stage(fill: false)],
    );
  }

  /// Connected LiveKit identities are the real-time presence authority. The
  /// Firestore roster supplies profile/role data but may retain a row after a
  /// crash until server reconciliation. During connect (and in widget-test
  /// seams with no LiveKit cast) the roster is the honest fallback.
  List<RoomParticipant> _activeParticipants(List<RoomParticipant> roster) {
    if (!_voice.isConnected || _voice.roomId != widget.room.id) return roster;
    final connectedIds = _voice.participants
        .map((participant) => participant.identity)
        .where((identity) => identity.isNotEmpty)
        .toSet();
    if (connectedIds.isEmpty) return roster;
    return roster
        .where((participant) => connectedIds.contains(participant.userId))
        .toList(growable: false);
  }

  List<RoomParticipant> _latestParticipants = const [];

  /// The header's identity line. A club room keeps its identity
  /// ("FAMILY ROOM", "CLUB ROOM") and GAINS the dormant marker rather
  /// than losing the identity to it; a dormant room must never read
  /// "OFFLINE" — that describes a broken connection, not a room nobody
  /// has opened the mics in yet.
  String _subtitleText(Club? club) {
    final copy = AppLocalizations.of(context);
    final subtitle = club?.isFamilyRoom == true
        ? copy.text('FAMILY ROOM', 'POKÓJ RODZINNY')
        : _isClubRoom
        ? copy.text('CLUB ROOM', 'POKÓJ KLUBOWY')
        : null;
    if (!_live) {
      final dormant = copy.text('NOT LIVE YET', 'JESZCZE NIE NA ŻYWO');
      return subtitle == null ? dormant : '$subtitle · $dormant';
    }
    return subtitle ?? _statusText(_voice.status, copy);
  }

  static String _statusText(VoiceCallStatus status, AppLocalizations copy) =>
      switch (status) {
        VoiceCallStatus.connected => copy.text(
          'COMMUNITY LIVE',
          'SPOŁECZNOŚĆ NA ŻYWO',
        ),
        VoiceCallStatus.connecting => copy.text('CONNECTING…', 'ŁĄCZENIE…'),
        VoiceCallStatus.reconnecting => copy.text(
          'RECONNECTING…',
          'PONOWNE ŁĄCZENIE…',
        ),
        VoiceCallStatus.failed => copy.text(
          'CONNECTION FAILED',
          'BŁĄD POŁĄCZENIA',
        ),
        VoiceCallStatus.disconnected => copy.text('OFFLINE', 'ROZŁĄCZONO'),
      };

  /// The floating control dock. Every affordance is a visually distinct
  /// button — the mic must never look "permanently pressed" or dead while
  /// it actually works, and a room with no voice session must never show
  /// a mute control at all. A blocked mic explains itself on tap instead
  /// of failing silently.
  Widget _buildDock(
    SpaceIdentity identity,
    RoomMicAffordance affordance, {
    required bool desktop,
  }) {
    final copy = AppLocalizations.of(context);
    final busy =
        _voice.muteChangeInProgress ||
        _muteCoordinator.isBusy ||
        _startingVoice;
    final (icon, label, style) = switch (affordance) {
      RoomMicAffordance.live => (
        Icons.mic_rounded,
        copy.text('Mute', 'Wycisz'),
        RoomDockStyle.accent,
      ),
      RoomMicAffordance.muted => (
        Icons.mic_off_rounded,
        copy.text('Unmute', 'Włącz mikrofon'),
        RoomDockStyle.warning,
      ),
      RoomMicAffordance.connecting => (
        Icons.mic_rounded,
        copy.text('Connecting…', 'Łączenie…'),
        RoomDockStyle.neutral,
      ),
      RoomMicAffordance.listenOnly => (
        Icons.headphones_rounded,
        copy.text('Listening', 'Słuchasz'),
        RoomDockStyle.neutral,
      ),
      RoomMicAffordance.startVoice => (
        Icons.graphic_eq_rounded,
        copy.text('Start voice', 'Uruchom rozmowę'),
        RoomDockStyle.accent,
      ),
      RoomMicAffordance.waitingForHost => (
        Icons.mic_off_rounded,
        copy.text('Not live', 'Nie na żywo'),
        RoomDockStyle.neutral,
      ),
      RoomMicAffordance.unavailable => (
        Icons.mic_off_rounded,
        copy.text('Audio off', 'Dźwięk wyłączony'),
        RoomDockStyle.alert,
      ),
    };

    return RoomControlDock(
      children: [
        RoomDockButton(
          icon: icon,
          label: label,
          style: style,
          accentColor: identity.primary,
          enabled: affordance != RoomMicAffordance.connecting && !busy,
          showSpinner:
              affordance == RoomMicAffordance.connecting ||
              (busy && affordance == RoomMicAffordance.startVoice),
          onTap: () {
            if (affordance.isMuteControl) {
              unawaited(_toggleMute());
            } else if (affordance.isStartControl) {
              unawaited(_enterVoice());
            } else {
              _explainMicState(affordance);
            }
          },
        ),
        if (!desktop)
          RoomDockButton(
            icon: Icons.forum_rounded,
            label: copy.text('Chat', 'Czat'),
            style: RoomDockStyle.neutral,
            accentColor: identity.primary,
            onTap: _openChat,
          ),
        RoomDockButton(
          icon: Icons.groups_rounded,
          label: copy.text('People', 'Osoby'),
          style: RoomDockStyle.neutral,
          accentColor: identity.primary,
          onTap: () => _openParticipants(_latestParticipants),
        ),
        const RoomDockDivider(),
        RoomDockButton(
          icon: Icons.call_end_rounded,
          label: copy.text('Leave', 'Wyjdź'),
          style: RoomDockStyle.danger,
          accentColor: identity.primary,
          onTap: () => unawaited(_leave()),
        ),
      ],
    );
  }

  void _openChat() {
    if (RoomWorkspace.usesDesktopLayout(context)) return;
    setState(() => _showCompactChat = true);
  }

  @override
  Widget build(BuildContext context) {
    final clubStream = _club;
    return YoImmersiveDarkSurface(
      child: clubStream == null
          ? _buildRoom(null)
          : StreamBuilder<Club>(
              stream: clubStream,
              builder: (context, snapshot) => _buildRoom(snapshot.data),
            ),
    );
  }

  Widget _buildRoom(Club? club) {
    final identity = voiceRoomIdentity(widget.room, club: club);
    final desktop = RoomWorkspace.usesDesktopLayout(context);
    return StreamBuilder<List<RoomParticipant>>(
      stream: _participants,
      builder: (context, snapshot) {
        final roster = snapshot.data ?? const <RoomParticipant>[];
        final roomParticipants = _activeParticipants(roster);
        _latestParticipants = roomParticipants;
        // Liveness leads: in a dormant room there is no audio session at
        // all, so no MicState value could describe the control honestly.
        final affordance = roomMicAffordance(
          roomIsLive: _live,
          canStartVoice: _entry.canStartVoice,
          micState: _voice.micState,
        );

        if (_roomOver || _entry.outcome == RoomVoiceEntryOutcome.unavailable) {
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
                        child: RoomHeader(
                          identity: identity,
                          title: club?.name ?? widget.room.name,
                          subtitle: _subtitleText(club),
                          avatarUrl: club?.avatarUrl,
                          avatarName: club?.name,
                          speaking: 0,
                          listeners: 0,
                          people: roomParticipants.length,
                          onBack: () => Navigator.of(context).pop(),
                          onPeopleTap: () =>
                              _openParticipants(roomParticipants),
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
                          service: _rooms,
                          currentUserId: _uid,
                          onClose: desktop
                              ? null
                              : () => setState(() => _showCompactChat = false),
                        ),
                      ),
                    ),
                    _buildDock(identity, affordance, desktop: desktop),
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
    final copy = AppLocalizations.of(context);
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
          YoModalSheetChrome(
            sheetLabel: copy.text('room participants', 'uczestnicy pokoju'),
            surfaceColor: Color(0xFF120B18),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 12, 10),
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
              ],
            ),
          ),
          Flexible(
            child: widget.participants.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(36),
                    child: Text(
                      copy.text(
                        'Nobody is here yet.',
                        'Nikogo tu jeszcze nie ma.',
                      ),
                      style: const TextStyle(color: Color(0xFFB6A9C2)),
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
                        leading: UserAvatar(
                          radius: 23,
                          userId: participant.userId,
                          photoUrl: participant.photoUrl,
                          displayName: participant.displayName,
                          backgroundColor: const Color(0xFF7135A5),
                        ),
                        title: Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              self
                                  ? copy.text(
                                      '${participant.displayName} (you)',
                                      '${participant.displayName} (Ty)',
                                    )
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
                              ? copy.text(
                                  'Community owner',
                                  'Właściciel społeczności',
                                )
                              : participant.isMuted
                              ? copy.text('Muted', 'Wyciszony')
                              : copy.text(
                                  'Microphone ready',
                                  'Mikrofon gotowy',
                                ),
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
                                          ? copy.text(
                                              'Allow microphone',
                                              'Zezwól na mikrofon',
                                            )
                                          : copy.text(
                                              'Mute participant',
                                              'Wycisz uczestnika',
                                            ),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'remove',
                                    child: Text(
                                      copy.text(
                                        'Remove from room',
                                        'Usuń z pokoju',
                                      ),
                                      style: const TextStyle(
                                        color: Color(0xFFFF6688),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Icon(
                                participant.isMuted
                                    ? Icons.mic_off_rounded
                                    : Icons.mic_rounded,
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
