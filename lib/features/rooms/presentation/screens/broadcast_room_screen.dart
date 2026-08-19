import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/theme/space_identity.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/room_voice_access.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_leave_coordinator.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/data/services/room_mute_coordinator.dart';
import 'package:yovoice/features/rooms/data/services/room_voice_entry_coordinator.dart';
import 'package:yovoice/features/rooms/presentation/room_mic_affordance.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_background.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_bottom_controls.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_owner_controls.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_stage.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/sheets/owner_menu_sheet.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/sheets/participants_sheet.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/sheets/settings_sheet.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/sheets/share_room_sheet.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_chat_sheet.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_ended_state.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_stage.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';

class BroadcastRoomScreen extends StatefulWidget {
  const BroadcastRoomScreen({
    required this.room,
    this.voiceEntry,
    this.roomService,
    this.voiceService,
    this.entryCoordinator,
    super.key,
  });

  final VoiceRoom room;

  /// What [RoomEntryScreen] resolved about this broadcast's voice session.
  /// Null means nothing was resolved, which is treated as "no authority".
  final RoomVoiceEntry? voiceEntry;

  /// Test seams. All three default to the production wiring.
  final RoomService? roomService;
  final VoiceCallService? voiceService;
  final RoomVoiceEntryCoordinator? entryCoordinator;

  @override
  State<BroadcastRoomScreen> createState() => _BroadcastRoomScreenState();
}

class _BroadcastRoomScreenState extends State<BroadcastRoomScreen> {
  late final RoomService _rooms = widget.roomService ?? RoomService();
  // Live audio is part of the room, not a second screen: entering the
  // broadcast connects you (listen-only until promoted — publish rights
  // come from the server-minted LiveKit token, never the client). The
  // old flow pushed a separate PodcastVoiceCallScreen with its own
  // duplicate stage; that screen is gone.
  late final VoiceCallService _voice =
      widget.voiceService ?? VoiceCallService.instance;
  late final RoomVoiceEntryCoordinator _entryCoordinator =
      widget.entryCoordinator ??
      RoomVoiceEntryCoordinator.production(rooms: _rooms);
  final RoomLeaveCoordinator _leaveCoordinator = RoomLeaveCoordinator();
  final RoomMuteCoordinator _muteCoordinator = RoomMuteCoordinator.production;

  /// The resolved voice state, kept current by the room document stream.
  late RoomVoiceEntry _entry =
      widget.voiceEntry ?? RoomVoiceEntry.unresolved(widget.room);

  /// Whether a LiveKit token may legitimately be requested. A persistent
  /// broadcast room is created dormant (`isLive: false`), exactly like a
  /// persistent community room, so this is not a temporary-room-only concern.
  late bool _live = _entry.voiceIsLive;
  StreamSubscription<VoiceRoom>? _roomWatch;
  bool _startingVoice = false;

  // Created once instead of inline in build() -- StreamBuilder resubscribes
  // whenever its `stream` argument is a new instance, and every setState()
  // in this screen (joining, hand-raise, dialogs, host actions) used to
  // hand it a fresh Stream each rebuild, tearing down and re-establishing
  // a live Firestore listener on every single one of them.
  late final Stream<List<RoomParticipant>> _participants;
  StreamSubscription<List<RoomParticipant>>? _participantsWatch;
  bool _wasSeenAsParticipant = false;

  bool _ending = false;
  bool _showCompactChat = false;

  /// Guards the server removal-confirmation against re-entry while an
  /// in-flight check is pending (the roster stream keeps emitting).
  bool _confirmingRemoval = false;
  bool _roomOver = false;

  String get _uid => _rooms.currentUserId;
  bool get _isHost => widget.room.hostId == _uid;
  String get _shareLink => 'https://yovoice.app/rooms/${widget.room.id}';

  @override
  void initState() {
    super.initState();
    _muteCoordinator.addListener(_refreshVoice);
    _voice.addListener(_refreshVoice);
    _participants = _rooms.watchParticipants(widget.room.id);
    _participantsWatch = _participants.listen(_handleParticipantsUpdate);
    _roomWatch = _rooms
        .watchRoom(widget.room.id)
        .listen(_handleRoomState, onError: (Object _) {});
    // A dormant room has no session to connect to. Asking for a token
    // anyway is the "This room is not currently live." failure.
    if (_live) unawaited(_connectVoice());
    _announceEntryFailure();
  }

  /// A refused entry must not be silent — say so once, in the server's own
  /// product copy, instead of leaving it to a tap on the control.
  void _announceEntryFailure() {
    final message = _entry.message;
    if (_entry.outcome != RoomVoiceEntryOutcome.failed || message == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showMessage(message, isError: true);
    });
  }

  @override
  void dispose() {
    _muteCoordinator.removeListener(_refreshVoice);
    _voice.removeListener(_refreshVoice);
    unawaited(_roomWatch?.cancel());
    unawaited(_participantsWatch?.cancel());
    // Deliberately NOT disconnecting here: backing out minimizes the
    // room (the shell's mini bar keeps it live). Only an explicit Leave
    // or the room ending disconnects.
    super.dispose();
  }

  void _refreshVoice() {
    if (mounted) setState(() {});
  }

  bool _roleReconnectInFlight = false;

  Future<void> _reconnectForRole() async {
    await _voice.disconnect(playSound: false);
    await _connectVoice(playSound: false);
  }

  /// Whether an AUTOMATIC audio action from this screen is legitimate.
  ///
  /// [VoiceCallService] is process-wide and a room screen stays MOUNTED
  /// beneath a pushed route, so this broadcast's liveness listener would
  /// otherwise reach into a session the user is having in another room —
  /// `join()` disconnects whatever is connected. A user-initiated start may
  /// still take the session over; a background document change may not.
  bool get _mayAutoConnectAudio {
    final connected = _voice.roomId;
    if (connected == widget.room.id) return true;
    if (connected != null) return false;
    if (!mounted) return false;
    return ModalRoute.of(context)?.isCurrent ?? true;
  }

  /// This screen may only cut audio it actually owns.
  bool get _ownsAudioSession => _voice.roomId == widget.room.id;

  /// The broadcast's liveness authority, followed live so a host opening the
  /// show reaches everyone already waiting on the stage screen.
  void _handleRoomState(VoiceRoom room) {
    // Closed, archived, suspended or half-deleted is NOT dormant. Collapsing
    // the two offered a Start control on an ended broadcast that could only
    // ever answer "This room has ended."
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
              ? RoomVoiceEntryOutcome.live
              : RoomVoiceEntryOutcome.dormant,
          // Stale failure copy described a moment that has passed.
          message: gone
              ? (room.deletionInProgress
                    ? 'This room is being deleted.'
                    : 'This room has ended.')
              : null,
        );
      });
    }
    if (live == wasLive) return;
    if (live) {
      if (_mayAutoConnectAudio) unawaited(_enterVoice());
    } else if (_ownsAudioSession) {
      unawaited(_voice.disconnect(playSound: false));
    }
  }

  /// The one path that turns this broadcast's voice on: liveness first,
  /// roster second, token third — the order the server requires.
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
        await _connectVoice();
        return;
      }
      final message = entry.message;
      if (message != null && mounted) _showMessage(message, isError: true);
    } finally {
      if (mounted) setState(() => _startingVoice = false);
    }
  }

  Future<void> _connectVoice({bool playSound = true}) async {
    // Structural guard: no token request while the room says it is dormant.
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
        );
      }
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        _voice.errorMessage ?? 'Could not join live audio. Please try again.',
        isError: true,
      );
    }
  }

  /// The mic can't publish right now — say why instead of a dead control.
  void _explainMicState(RoomMicAffordance affordance) {
    final message = switch (affordance) {
      RoomMicAffordance.connecting => 'Connecting to live audio…',
      RoomMicAffordance.listenOnly =>
        "You're listening — the host decides who joins the stage.",
      RoomMicAffordance.waitingForHost =>
        _entry.message ?? _entry.authority.waitingExplanation,
      RoomMicAffordance.unavailable =>
        _voice.errorMessage ??
            'Live audio is not connected. Leave and rejoin to retry.',
      RoomMicAffordance.live ||
      RoomMicAffordance.muted ||
      RoomMicAffordance.startVoice => '',
    };
    if (message.isEmpty || !mounted) return;
    _showMessage(message);
  }

  Future<void> _toggleMic() async {
    // `setOwnRoomParticipantMute` is refused on a room that is not live; the
    // affordance already prevents this call, and the guard keeps it true.
    if (!_live) return;
    final outcome = await _muteCoordinator.toggle(roomId: widget.room.id);
    if (!mounted) return;
    switch (outcome) {
      case RoomMuteOutcome.applied:
      case RoomMuteOutcome.busy:
        break;
      case RoomMuteOutcome.sessionEnded:
        _showMessage('This room is no longer live.', isError: true);
        await _leaveCoordinator.leave(
          disconnectAudio: _voice.disconnect,
          navigateAway: () {
            if (mounted) Navigator.of(context).pop();
          },
          cleanupParticipant: () => _rooms.leaveRoom(widget.room.id),
          onCleanupError: (error, _) => debugPrint(
            'Stale-session leave cleanup deferred to the server: $error',
          ),
        );
      case RoomMuteOutcome.failed:
        _showMessage(
          'Could not change microphone state. Try again.',
          isError: true,
        );
    }
  }

  Future<void> _leaveRoom() async {
    if (_ending || _leaveCoordinator.isLeaving) return;
    await _leaveCoordinator.leave(
      disconnectAudio: _voice.disconnect,
      navigateAway: () {
        if (mounted) Navigator.of(context).pop();
      },
      cleanupParticipant: () => _rooms.leaveRoom(widget.room.id),
      onCleanupError: (error, _) => debugPrint(
        'Broadcast leave cleanup will rely on server reconciliation: $error',
      ),
    );
  }

  // Ending or deleting a broadcast room deletes every participant doc,
  // including every listener's own -- but until now nothing told a
  // listener the room was gone; they'd just see the stage go empty and
  // have to notice and back out manually. The host doesn't need this:
  // _endBroadcast/_confirmDeleteRoom already navigate them out directly.
  void _handleParticipantsUpdate(List<RoomParticipant> participants) {
    final mine = participants.where(
      (participant) => participant.userId == _uid,
    );

    if (mine.isNotEmpty) {
      _wasSeenAsParticipant = true;
      // A moderator's mute (or a promotion, which starts muted) must
      // reach the actual microphone — but never auto-UNMUTE from the
      // doc: a stale unmuted flag raced the user's own Mute tap and
      // reverted it (same fix as the community room).
      final me = mine.first;
      if (_voice.isConnected &&
          me.isMuted &&
          !_voice.isMuted &&
          _ownsAudioSession) {
        unawaited(_voice.setMuted(true));
      }

      // Role changed (accepted onto the stage, or moved back to the
      // audience): LiveKit permissions live in the TOKEN, which was
      // minted for the old role — without a fresh one an accepted
      // speaker still can't publish, and a demoted speaker still can.
      // Rejoin mints a token for the real current role. Brief gap;
      // a server-side live permission update (LiveKit server API via a
      // Cloud Function) is the gapless follow-up, tracked in Roadmap.
      final shouldPublish = me.isSpeaker || me.isHost;
      if (_voice.isConnected &&
          _voice.roomId == widget.room.id &&
          shouldPublish != _voice.canPublish &&
          !_roleReconnectInFlight) {
        _roleReconnectInFlight = true;
        unawaited(
          _reconnectForRole().whenComplete(
            () => _roleReconnectInFlight = false,
          ),
        );
      }
      return;
    }

    if (!_wasSeenAsParticipant || _isHost || _ending || _confirmingRemoval) {
      return;
    }

    // The roster stream can emit CACHE-sourced snapshots, so a missing
    // own-document is only a HINT — confirm with the server before
    // ejecting (docs/Bugs.md: a false ended-state on a live room).
    _confirmingRemoval = true;
    unawaited(
      _rooms
          .isParticipantRemovedOnServer(roomId: widget.room.id, userId: _uid)
          .then((removed) {
            _confirmingRemoval = false;
            if (!removed || !mounted || _ending) return;

            // Removed by a moderator, or the room ended and deleted
            // every participant doc: cut audio, show the ended state.
            _ending = true;
            // Only this room's session. A removal here must not hang up a
            // room the user is actually in above this route.
            if (_ownsAudioSession) unawaited(_voice.disconnect());
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _roomOver = true);
            });
          }),
    );
  }

  Future<void> _toggleHand(RoomParticipant? me) async {
    if (me == null || me.isSpeaker || me.isHost) return;

    try {
      await _rooms.setHandRaised(
        roomId: widget.room.id,
        isRaised: !me.isHandRaised,
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(_readableError(error), isError: true);
    }
  }

  void _openParticipants(
    List<RoomParticipant> participants, {
    String initialFilter = 'all',
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 720,
      ),
      backgroundColor: BroadcastRoomColors.surface,
      builder: (_) => FractionallySizedBox(
        heightFactor: .86,
        child: BroadcastParticipantsSheet(
          roomId: widget.room.id,
          participants: participants,
          isHost: _isHost,
          initialFilter: initialFilter,
          service: _rooms,
        ),
      ),
    );
  }

  Future<void> _copyShareLink() async {
    await Clipboard.setData(ClipboardData(text: _shareLink));
    if (!mounted) return;
    _showMessage('Invite link copied.');
  }

  Future<void> _copyRoomId() async {
    await Clipboard.setData(ClipboardData(text: widget.room.id));
    if (!mounted) return;
    _showMessage('Room ID copied.');
  }

  void _openShareSheet() {
    showModalBottomSheet<void>(
      context: context,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 560,
      ),
      backgroundColor: BroadcastRoomColors.surface,
      showDragHandle: true,
      builder: (_) => ShareRoomSheet(
        roomName: widget.room.name,
        roomId: widget.room.id,
        shareLink: _shareLink,
        onCopyLink: _copyShareLink,
        onCopyRoomId: _copyRoomId,
      ),
    );
  }

  Future<void> _openSettings() async {
    if (!_isHost) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 720,
      ),
      backgroundColor: BroadcastRoomColors.surface,
      builder: (_) =>
          BroadcastSettingsSheet(room: widget.room, service: _rooms),
    );

    if (!mounted || saved != true) return;
    _showMessage('Room settings updated.');
  }

  void _openOwnerMenu(List<RoomParticipant> participants) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 560,
      ),
      backgroundColor: BroadcastRoomColors.surface,
      showDragHandle: true,
      builder: (_) => OwnerMenuSheet(
        onShare: () {
          Navigator.of(context).pop();
          _openShareSheet();
        },
        onParticipants: () {
          Navigator.of(context).pop();
          _openParticipants(participants);
        },
        onHands: () {
          Navigator.of(context).pop();
          _openParticipants(participants, initialFilter: 'hands');
        },
        onSettings: () {
          Navigator.of(context).pop();
          _openSettings();
        },
        onAnalytics: () {
          Navigator.of(context).pop();
          _showAnalytics(participants);
        },
        onEnd: () {
          Navigator.of(context).pop();
          _confirmEndBroadcast();
        },
        onDelete: () {
          Navigator.of(context).pop();
          _confirmDeleteRoom();
        },
      ),
    );
  }

  void _showAnalytics(List<RoomParticipant> participants) {
    final speakers = participants.where((p) => p.isSpeaker).length;
    final listeners = participants.where((p) => !p.isSpeaker).length;
    final hands = participants.where((p) => p.isHandRaised).length;

    showModalBottomSheet<void>(
      context: context,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 560,
      ),
      backgroundColor: BroadcastRoomColors.surface,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Podcast analytics',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Live snapshot for this podcast.',
              style: TextStyle(color: BroadcastRoomColors.muted),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: AnalyticsTile(
                    label: 'Total',
                    value: participants.length,
                    icon: Icons.groups_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AnalyticsTile(
                    label: 'Speaking',
                    value: speakers,
                    icon: Icons.graphic_eq_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: AnalyticsTile(
                    label: 'Listening',
                    value: listeners,
                    icon: Icons.headphones_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AnalyticsTile(
                    label: 'Hands',
                    value: hands,
                    icon: Icons.back_hand_rounded,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmEndBroadcast() async {
    if (!_isHost || _ending) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: BroadcastRoomColors.surface,
        title: const Text(
          'End podcast?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Everyone will be disconnected, the room will disappear from Discover and this podcast will be marked as closed.',
          style: TextStyle(color: BroadcastRoomColors.muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: BroadcastRoomColors.accent,
            ),
            child: const Text('End podcast'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _ending = true);

    try {
      await _voice.disconnect();
      await _rooms.setRoomStatus(widget.room.id, RoomStatus.closed);

      if (!mounted) return;

      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      setState(() => _ending = false);
      _showMessage(_readableError(error), isError: true);
    }
  }

  Future<void> _confirmDeleteRoom() async {
    if (!_isHost || _ending) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: BroadcastRoomColors.surface,
        title: const Text(
          'Delete room permanently?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'This removes the podcast, participants and room messages. This action cannot be undone.',
          style: TextStyle(color: BroadcastRoomColors.muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB71C35),
            ),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _ending = true);

    try {
      await _voice.disconnect();
      await _rooms.deleteRoom(widget.room.id);

      if (!mounted) return;

      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      setState(() => _ending = false);
      _showMessage(_readableError(error), isError: true);
    }
  }

  String _readableError(Object error) {
    // Server refusals carry product copy in .message; the
    // "[firebase_functions/…]" prefix is developer noise.
    if (error is FirebaseFunctionsException) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) return message;
      return 'Something went wrong. Please try again.';
    }
    return error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Invalid argument(s): ', '')
        .replaceFirst('Exception: ', '');
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? const Color(0xFF4D1722)
              : BroadcastRoomColors.surfaceSoft,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = RoomWorkspace.usesDesktopLayout(context);
    return Scaffold(
      backgroundColor: BroadcastRoomColors.background,
      body: SafeArea(
        child: StreamBuilder<List<RoomParticipant>>(
          stream: _participants,
          builder: (context, snapshot) {
            final participants = snapshot.data ?? const <RoomParticipant>[];
            final host = participants.where((p) => p.isHost).firstOrNull;
            final speakers = participants
                .where((p) => p.isSpeaker && !p.isHost)
                .toList(growable: false);
            final listeners = participants
                .where((p) => !p.isSpeaker)
                .toList(growable: false);
            final raised = listeners
                .where((p) => p.isHandRaised)
                .toList(growable: false);
            final me = participants.where((p) => p.userId == _uid).firstOrNull;
            final voiceByIdentity = {
              for (final participant in _voice.participants)
                participant.identity: participant,
            };
            final hostParticipant = host;
            final stageSpeakers = <StageSpeaker>[
              StageSpeaker(
                userId: hostParticipant?.userId ?? widget.room.hostId,
                displayName:
                    hostParticipant?.displayName ?? widget.room.hostName,
                photoUrl: hostParticipant?.photoUrl ?? widget.room.hostPhotoUrl,
                isHost: true,
                isMuted: hostParticipant?.isMuted ?? false,
                isSpeaking:
                    voiceByIdentity[hostParticipant?.userId ??
                            widget.room.hostId]
                        ?.isSpeaking ??
                    false,
                audioLevel:
                    voiceByIdentity[hostParticipant?.userId ??
                            widget.room.hostId]
                        ?.audioLevel ??
                    0,
              ),
              for (final participant in speakers)
                StageSpeaker(
                  userId: participant.userId,
                  displayName: participant.displayName,
                  photoUrl: participant.photoUrl,
                  isMuted: participant.isMuted,
                  isSpeaking:
                      voiceByIdentity[participant.userId]?.isSpeaking ?? false,
                  audioLevel:
                      voiceByIdentity[participant.userId]?.audioLevel ?? 0,
                ),
            ];
            final anyoneSpeaking = stageSpeakers.any(
              (speaker) => speaker.isSpeaking,
            );
            // Liveness leads the audio session: a dormant broadcast has no
            // session, so no MicState value could describe the control.
            final affordance = roomMicAffordance(
              roomIsLive: _live,
              canStartVoice: _entry.canStartVoice,
              micState: _voice.micState,
            );

            return Stack(
              children: [
                const Positioned.fill(child: BroadcastBackground()),
                Column(
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: BroadcastTopBar(
                          title: widget.room.name,
                          count: participants.length,
                          isHost: _isHost,
                          onBack: () => Navigator.of(context).pop(),
                          onPeople: () => _openParticipants(participants),
                          onMenu: () => _openOwnerMenu(participants),
                          onShare: _openShareSheet,
                        ),
                      ),
                    ),
                    Expanded(
                      child: RoomWorkspace(
                        showCompactChat: _showCompactChat,
                        stage: ListView(
                          padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
                          children: [
                            RoomIdentityCard(
                              roomName: widget.room.name,
                              topic: widget.room.description.trim().isNotEmpty
                                  ? widget.room.description
                                  : widget.room.category,
                              identity: SpaceIdentity.podcast,
                              imageUrl: widget.room.imageUrl,
                              quiet: !anyoneSpeaking,
                              // The live badge follows the room document,
                              // not the possibly-stale document this screen
                              // was pushed with.
                              trailing: BroadcastLiveBadge(isLive: _live),
                            ),
                            if (_isHost) ...[
                              const SizedBox(height: 16),
                              BroadcastOwnerQuickActions(
                                raisedHands: raised.length,
                                onParticipants: () =>
                                    _openParticipants(participants),
                                onHands: () => _openParticipants(
                                  participants,
                                  initialFilter: 'hands',
                                ),
                                onManage: () => _openOwnerMenu(participants),
                                onShare: _openShareSheet,
                              ),
                            ],
                            const SizedBox(height: 14),
                            RoomStagePanel(
                              speakers: stageSpeakers,
                              identity: SpaceIdentity.podcast,
                              onOverflowTap: () => _openParticipants(
                                participants,
                                initialFilter: 'speakers',
                              ),
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
                              identity: SpaceIdentity.podcast,
                              onTap: () => _openParticipants(
                                participants,
                                initialFilter: 'listeners',
                              ),
                              previewPhotoUrls: [
                                for (final listener in listeners.take(4))
                                  listener.photoUrl,
                              ],
                              previewNames: [
                                for (final listener in listeners.take(4))
                                  listener.displayName,
                              ],
                            ),
                          ],
                        ),
                        chat: RoomChatPanel(
                          roomId: widget.room.id,
                          isHost: _isHost,
                          accent: BroadcastRoomColors.accent,
                          service: _rooms,
                          currentUserId: _uid,
                          onClose: desktop
                              ? null
                              : () => setState(() => _showCompactChat = false),
                        ),
                      ),
                    ),
                    BroadcastBottomControls(
                      isHost: _isHost,
                      ending: _ending,
                      connected: _voice.isConnected,
                      micMuted: _voice.isMuted,
                      micBusy:
                          _voice.muteChangeInProgress ||
                          _muteCoordinator.isBusy ||
                          _startingVoice,
                      affordance: affordance,
                      canSpeak: me != null && (me.isSpeaker || me.isHost),
                      handRaised: me?.isHandRaised ?? false,
                      canRaiseHand: me != null && !me.isSpeaker && !me.isHost,
                      onMic: _toggleMic,
                      onStartVoice: () => unawaited(_enterVoice()),
                      onNotLive: () => _showMessage(
                        _entry.message ?? _entry.authority.waitingExplanation,
                      ),
                      onMicBlocked: () => _explainMicState(affordance),
                      onRaiseHand: () => _toggleHand(me),
                      onShare: _openShareSheet,
                      onParticipants: () => _openParticipants(participants),
                      onEnd: _confirmEndBroadcast,
                      onLeave: _leaveRoom,
                      showChat: !desktop,
                      onChat: () => setState(() => _showCompactChat = true),
                    ),
                  ],
                ),
                if (_ending && !_roomOver)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x99000000),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: BroadcastRoomColors.accent,
                        ),
                      ),
                    ),
                  ),
                if (_roomOver ||
                    _entry.outcome == RoomVoiceEntryOutcome.unavailable)
                  Positioned.fill(
                    child: RoomEndedState(
                      roomName: widget.room.name,
                      accent: BroadcastRoomColors.accent,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
