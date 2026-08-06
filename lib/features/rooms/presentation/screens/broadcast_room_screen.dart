import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/features/calls/presentation/screens/podcast_voice_call_screen.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_background.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_bottom_controls.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_owner_controls.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_roster.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_stage.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/sheets/owner_menu_sheet.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/sheets/participants_sheet.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/sheets/settings_sheet.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/sheets/share_room_sheet.dart';

class BroadcastRoomScreen extends StatefulWidget {
  const BroadcastRoomScreen({required this.room, super.key});

  final VoiceRoom room;

  @override
  State<BroadcastRoomScreen> createState() => _BroadcastRoomScreenState();
}

class _BroadcastRoomScreenState extends State<BroadcastRoomScreen>
    with SingleTickerProviderStateMixin {
  final RoomService _rooms = RoomService();
  late final AnimationController _pulse;

  // Created once instead of inline in build() -- StreamBuilder resubscribes
  // whenever its `stream` argument is a new instance, and every setState()
  // in this screen (joining, hand-raise, dialogs, host actions) used to
  // hand it a fresh Stream each rebuild, tearing down and re-establishing
  // a live Firestore listener on every single one of them.
  late final Stream<List<RoomParticipant>> _participants;
  StreamSubscription<List<RoomParticipant>>? _participantsWatch;
  bool _wasSeenAsParticipant = false;

  bool _joining = false;
  bool _ending = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _isHost => widget.room.hostId == _uid;
  String get _shareLink => 'https://yovoice.app/rooms/${widget.room.id}';

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..repeat(reverse: true);
    _participants = _rooms.watchParticipants(widget.room.id);
    _participantsWatch = _participants.listen(_handleParticipantsUpdate);
  }

  @override
  void dispose() {
    _pulse.dispose();
    unawaited(_participantsWatch?.cancel());
    super.dispose();
  }

  // Ending or deleting a broadcast room deletes every participant doc,
  // including every listener's own -- but until now nothing told a
  // listener the room was gone; they'd just see the stage go empty and
  // have to notice and back out manually. The host doesn't need this:
  // _endBroadcast/_confirmDeleteRoom already navigate them out directly.
  void _handleParticipantsUpdate(List<RoomParticipant> participants) {
    final stillIn = participants.any(
      (participant) => participant.userId == _uid,
    );

    if (stillIn) {
      _wasSeenAsParticipant = true;
      return;
    }

    if (!_wasSeenAsParticipant || _isHost || _ending) {
      return;
    }

    _ending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showMessage('This room has ended.');
      Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  Future<void> _joinVoice() async {
    if (_joining) return;
    setState(() => _joining = true);

    try {
      await _rooms.joinRoom(widget.room.id);

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PodcastVoiceCallScreen(
            roomId: widget.room.id,
            roomName: widget.room.name,
            hostId: widget.room.hostId,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(_readableError(error), isError: true);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
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
      backgroundColor: BroadcastRoomColors.surface,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Broadcast analytics',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Live snapshot for this broadcast.',
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
          'End broadcast?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Everyone will be disconnected, the room will disappear from Discover and this broadcast will be marked as closed.',
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
            child: const Text('End broadcast'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _ending = true);

    try {
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
          'This removes the broadcast, participants and room messages. This action cannot be undone.',
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

            return Stack(
              children: [
                const Positioned.fill(child: BroadcastBackground()),
                Column(
                  children: [
                    BroadcastTopBar(
                      title: widget.room.name,
                      count: participants.length,
                      isHost: _isHost,
                      onBack: () => Navigator.of(context).pop(),
                      onPeople: () => _openParticipants(participants),
                      onMenu: () => _openOwnerMenu(participants),
                      onShare: _openShareSheet,
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
                        children: [
                          BroadcastLiveBadge(isLive: widget.room.isLive),
                          const SizedBox(height: 18),
                          BroadcastHostStage(
                            participant: host,
                            fallbackName: widget.room.hostName,
                            pulse: _pulse,
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
                          const SizedBox(height: 22),
                          BroadcastClickableStats(
                            speakers: 1 + speakers.length,
                            listeners: listeners.length,
                            raisedHands: raised.length,
                            onSpeakers: () => _openParticipants(
                              participants,
                              initialFilter: 'speakers',
                            ),
                            onListeners: () => _openParticipants(
                              participants,
                              initialFilter: 'listeners',
                            ),
                            onHands: () => _openParticipants(
                              participants,
                              initialFilter: 'hands',
                            ),
                          ),
                          const SizedBox(height: 22),
                          BroadcastSectionHeader(
                            title: 'On stage',
                            subtitle: 'Host and approved speakers',
                            count: speakers.length + 1,
                          ),
                          const SizedBox(height: 12),
                          if (speakers.isEmpty)
                            const BroadcastEmptyStage()
                          else
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: speakers
                                  .map(
                                    (speaker) => BroadcastSpeakerTile(
                                      participant: speaker,
                                      isHostView: _isHost,
                                      onManage: () => _openParticipants(
                                        participants,
                                        initialFilter: 'speakers',
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          const SizedBox(height: 24),
                          BroadcastSectionHeader(
                            title: 'Audience',
                            subtitle: 'Listeners can request the stage',
                            count: listeners.length,
                          ),
                          const SizedBox(height: 12),
                          BroadcastAudiencePreview(
                            listeners: listeners,
                            onOpen: () => _openParticipants(
                              participants,
                              initialFilter: 'listeners',
                            ),
                          ),
                        ],
                      ),
                    ),
                    BroadcastBottomControls(
                      isHost: _isHost,
                      joining: _joining,
                      ending: _ending,
                      handRaised: me?.isHandRaised ?? false,
                      canRaiseHand: me != null && !me.isSpeaker && !me.isHost,
                      onJoin: _joinVoice,
                      onRaiseHand: () => _toggleHand(me),
                      onShare: _openShareSheet,
                      onParticipants: () => _openParticipants(participants),
                      onEnd: _confirmEndBroadcast,
                    ),
                  ],
                ),
                if (_ending)
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
