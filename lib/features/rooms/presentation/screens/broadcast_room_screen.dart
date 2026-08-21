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
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/sheets/owner_menu_sheet.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/sheets/participants_sheet.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/sheets/settings_sheet.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/sheets/share_room_sheet.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_chat_sheet.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_control_dock.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_ended_state.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_energy_wave.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_header.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_hero_banner.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_quick_actions.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_stage.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

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

  /// The podcast hero's identity footer: the REAL host (roster row first,
  /// the room document as fallback) and, while the show is live, a subtle
  /// waveform bound to the real room audio meter. No live-duration timer —
  /// the schema stores no started-at timestamp, so none is invented.
  Widget _heroFooter(RoomParticipant? host) {
    final name = host?.displayName ?? widget.room.hostName;
    final photoUrl = host?.photoUrl ?? widget.room.hostPhotoUrl;
    final uid = host?.userId ?? widget.room.hostId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            UserAvatar(
              radius: 13,
              photoUrl: photoUrl,
              displayName: name,
              // Takes the podcast coral like every other letter fallback in
              // the room, so the hero credit does not read purple.
              backgroundColor: Color.lerp(
                SpaceIdentity.podcast.primary,
                const Color(0xFF120C1B),
                .45,
              )!,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Hosted by $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .85),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: SpaceIdentity.podcast.wash,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'HOST',
                style: TextStyle(
                  color: BroadcastRoomColors.accentSoft,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                ),
              ),
            ),
            const SizedBox(width: 6),
            UserIdentityBadges(uid: uid, variant: IdentityBadgeVariant.icon),
          ],
        ),
        if (_live) ...[
          const SizedBox(height: 12),
          RoomEnergyWave(
            // The meter belongs to THIS room's session only; another
            // room's audio must never animate this hero.
            energy: _ownsAudioSession ? _voice.roomEnergy : 0,
            color: BroadcastRoomColors.accentSoft,
          ),
        ],
      ],
    );
  }

  /// The floating control dock. The primary slot is decided by the
  /// affordance first: a show that has not started has neither a mic to
  /// mute nor a stage to raise a hand for, so neither control is offered
  /// into it.
  Widget _buildDock({
    required RoomMicAffordance affordance,
    required RoomParticipant? me,
    required List<RoomParticipant> participants,
    required bool desktop,
  }) {
    const accent = BroadcastRoomColors.accent;
    final micBusy =
        _voice.muteChangeInProgress ||
        _muteCoordinator.isBusy ||
        _startingVoice;
    final connected = _voice.isConnected;
    final micMuted = _voice.isMuted;
    final canSpeak = me != null && (me.isSpeaker || me.isHost);
    final handRaised = me?.isHandRaised ?? false;
    final canRaiseHand = me != null && !me.isSpeaker && !me.isHost;

    final Widget primary;
    if (affordance == RoomMicAffordance.startVoice) {
      primary = RoomDockButton(
        icon: Icons.graphic_eq_rounded,
        label: 'Start voice',
        style: RoomDockStyle.accent,
        accentColor: accent,
        showSpinner: micBusy,
        onTap: _ending || micBusy ? null : () => unawaited(_enterVoice()),
      );
    } else if (affordance == RoomMicAffordance.waitingForHost) {
      primary = RoomDockButton(
        icon: Icons.mic_off_rounded,
        label: 'Not live',
        style: RoomDockStyle.neutral,
        accentColor: accent,
        onTap: _ending
            ? null
            : () => _showMessage(
                _entry.message ?? _entry.authority.waitingExplanation,
              ),
      );
    } else if (canSpeak) {
      primary = RoomDockButton(
        icon: switch (affordance) {
          RoomMicAffordance.listenOnly => Icons.headphones_rounded,
          RoomMicAffordance.connecting => Icons.mic_rounded,
          _ => micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
        },
        label: switch (affordance) {
          RoomMicAffordance.connecting => 'Connecting…',
          RoomMicAffordance.listenOnly => 'Listening',
          RoomMicAffordance.unavailable => 'Audio off',
          _ => micMuted ? 'Unmute' : 'Mute',
        },
        style: switch (affordance) {
          RoomMicAffordance.live => RoomDockStyle.accent,
          RoomMicAffordance.muted => RoomDockStyle.warning,
          RoomMicAffordance.unavailable => RoomDockStyle.alert,
          _ => RoomDockStyle.neutral,
        },
        accentColor: accent,
        showSpinner: affordance == RoomMicAffordance.connecting,
        // A blocked mic explains itself instead of sitting dead. Only
        // `connecting` is genuinely untappable — there is nothing to say
        // that the label is not already saying.
        onTap: _ending
            ? null
            : affordance.isMuteControl
            ? (micBusy || !connected ? null : () => unawaited(_toggleMic()))
            : affordance == RoomMicAffordance.connecting
            ? null
            : () => _explainMicState(affordance),
      );
    } else {
      primary = RoomDockButton(
        icon: handRaised
            ? Icons.pan_tool_alt_rounded
            : Icons.back_hand_outlined,
        label: handRaised ? 'Lower hand' : 'Raise hand',
        style: handRaised ? RoomDockStyle.accent : RoomDockStyle.neutral,
        accentColor: accent,
        onTap: _ending || !canRaiseHand
            ? null
            : () => unawaited(_toggleHand(me)),
      );
    }

    return RoomControlDock(
      children: [
        primary,
        if (!desktop)
          RoomDockButton(
            icon: Icons.forum_rounded,
            label: 'Chat',
            style: RoomDockStyle.neutral,
            accentColor: accent,
            onTap: _ending
                ? null
                : () => setState(() => _showCompactChat = true),
          ),
        RoomDockButton(
          icon: Icons.groups_rounded,
          label: 'People',
          style: RoomDockStyle.neutral,
          accentColor: accent,
          onTap: _ending ? null : () => _openParticipants(participants),
        ),
        RoomDockButton(
          icon: Icons.ios_share_rounded,
          label: 'Share',
          style: RoomDockStyle.neutral,
          accentColor: accent,
          onTap: _ending ? null : _openShareSheet,
        ),
        // A host looking at a dormant room has nothing to End — the red
        // control appeared beside "Start voice" and read as a threat to a
        // session that did not exist. A non-host can always Leave.
        if (!_isHost || _live) ...[
          const RoomDockDivider(),
          RoomDockButton(
            icon: _isHost ? Icons.stop_circle_rounded : Icons.logout_rounded,
            label: _isHost ? 'End' : 'Leave',
            style: RoomDockStyle.danger,
            accentColor: accent,
            onTap: _ending
                ? null
                : () =>
                      unawaited(_isHost ? _confirmEndBroadcast() : _leaveRoom()),
          ),
        ],
      ],
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
                // Before the session runs there is no live mic anywhere,
                // so a missing participant row defaults MUTED while dormant
                // — the dormant screen was showing an unmuted accent chip
                // next to "NOT LIVE YET".
                isMuted: hostParticipant?.isMuted ?? !_live,
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
                        child: RoomHeader(
                          identity: SpaceIdentity.podcast,
                          title: widget.room.name,
                          subtitle: _live
                              ? 'PODCAST ROOM'
                              : 'PODCAST ROOM · NOT LIVE YET',
                          // Zero while dormant: "1 Speaking" beside
                          // NOT LIVE YET was three contradictory signals on
                          // one screen.
                          speaking: _live ? stageSpeakers.length : 0,
                          listeners: listeners.length,
                          onBack: () => Navigator.of(context).pop(),
                          onSpeakingTap: () => _openParticipants(
                            participants,
                            initialFilter: 'speakers',
                          ),
                          onListenersTap: () => _openParticipants(
                            participants,
                            initialFilter: 'listeners',
                          ),
                          actions: [
                            IconButton(
                              tooltip: 'Share room',
                              onPressed: _openShareSheet,
                              color: Colors.white,
                              icon: const Icon(
                                Icons.ios_share_rounded,
                                size: 21,
                              ),
                            ),
                            if (_isHost)
                              IconButton(
                                tooltip: 'Manage podcast',
                                onPressed: () => _openOwnerMenu(participants),
                                color: Colors.white,
                                icon: const Icon(Icons.more_vert_rounded),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: RoomWorkspace(
                        showCompactChat: _showCompactChat,
                        // The podcast column fills the same way the
                        // community one does (see
                        // community_voice_room_screen): with a bounded
                        // height the stage takes what the hero, the quick
                        // actions and the audience strip do not, instead of
                        // stranding the cast above a dead band. A short or
                        // narrow viewport keeps scrolling, because there is
                        // no spare height to hand out.
                        stage: _PodcastColumn(
                          // The HOST column carries more fixed content than
                          // the community one (taller hero with the
                          // hosted-by credit and waveform, plus the quick
                          // actions row) — at 720-850px of height the
                          // filled Column overflowed and painted under the
                          // audience strip. The gate buys the stage room to
                          // actually exist; below it, scrolling returns.
                          fillStage:
                              MediaQuery.sizeOf(context).width >= 700 &&
                              MediaQuery.sizeOf(context).height >=
                                  (_isHost ? 880 : 780),
                          children: [
                            RoomHeroBanner(
                              identity: SpaceIdentity.podcast,
                              title: widget.room.name,
                              topic: widget.room.description.trim().isNotEmpty
                                  ? widget.room.description
                                  : widget.room.category,
                              imageUrl: widget.room.imageUrl,
                              // The live pill follows the room document,
                              // not the possibly-stale document this screen
                              // was pushed with.
                              statusPill: RoomHeroStatusPill(
                                label: _live ? 'LIVE PODCAST' : 'NOT LIVE YET',
                                live: _live,
                                identity: SpaceIdentity.podcast,
                              ),
                              footer: _heroFooter(host),
                            ),
                            if (_isHost) ...[
                              const SizedBox(height: 14),
                              // Share is deliberately absent here: the
                              // host's dock and the header already carry
                              // it, and a third copy is noise.
                              RoomQuickActions(
                                identity: SpaceIdentity.podcast,
                                items: [
                                  RoomQuickActionItem(
                                    icon: Icons.groups_rounded,
                                    label: 'Guests',
                                    onTap: () =>
                                        _openParticipants(participants),
                                  ),
                                  RoomQuickActionItem(
                                    icon: Icons.back_hand_rounded,
                                    label: raised.isNotEmpty
                                        ? 'Hands ${raised.length}'
                                        : 'Hands',
                                    highlighted: raised.isNotEmpty,
                                    onTap: () => _openParticipants(
                                      participants,
                                      initialFilter: 'hands',
                                    ),
                                  ),
                                  RoomQuickActionItem(
                                    icon: Icons.tune_rounded,
                                    label: 'Manage',
                                    onTap: () => _openOwnerMenu(participants),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 14),
                            RoomStagePanel(
                              speakers: stageSpeakers,
                              identity: SpaceIdentity.podcast,
                              fill:
                                  MediaQuery.sizeOf(context).width >= 700 &&
                                  MediaQuery.sizeOf(context).height >=
                                      (_isHost ? 880 : 780),
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
                            AudienceStrip(
                              count: listeners.length,
                              identity: SpaceIdentity.podcast,
                              onTap: () => _openParticipants(
                                participants,
                                initialFilter: 'listeners',
                              ),
                              previewPhotoUrls: [
                                for (final listener in listeners.take(6))
                                  listener.photoUrl,
                              ],
                              previewNames: [
                                for (final listener in listeners.take(6))
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
                    _buildDock(
                      affordance: affordance,
                      me: me,
                      participants: participants,
                      desktop: desktop,
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

/// The podcast main column.
///
/// Scrolls when the viewport is narrow or short, and otherwise lays the same
/// children out as a Column whose STAGE — the one child built to fill — takes
/// the leftover height. Keeping both shapes in one widget means the podcast
/// and community screens stay describable as the same layout rule rather than
/// drifting into two.
class _PodcastColumn extends StatelessWidget {
  const _PodcastColumn({required this.fillStage, required this.children});

  final bool fillStage;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!fillStage) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
        children: children,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in children)
            if (child is RoomStagePanel) Expanded(child: child) else child,
        ],
      ),
    );
  }
}
