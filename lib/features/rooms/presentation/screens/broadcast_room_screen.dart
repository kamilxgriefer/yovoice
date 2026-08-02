import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/features/calls/presentation/screens/podcast_voice_call_screen.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

class BroadcastRoomScreen extends StatefulWidget {
  const BroadcastRoomScreen({required this.room, super.key});

  final VoiceRoom room;

  @override
  State<BroadcastRoomScreen> createState() => _BroadcastRoomScreenState();
}

class _BroadcastRoomScreenState extends State<BroadcastRoomScreen>
    with SingleTickerProviderStateMixin {
  static const _background = Color(0xFF090305);
  static const _surface = Color(0xFF1A0B0F);
  static const _surfaceSoft = Color(0xFF241015);
  static const _border = Color(0xFF5D202A);
  static const _accent = Color(0xFFFF314F);
  static const _accentSoft = Color(0xFFFF6A76);
  static const _muted = Color(0xFFB79CA2);

  final RoomService _rooms = RoomService();
  late final AnimationController _pulse;

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
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
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
      backgroundColor: _surface,
      builder: (_) => FractionallySizedBox(
        heightFactor: .86,
        child: _BroadcastParticipantsSheet(
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
      backgroundColor: _surface,
      showDragHandle: true,
      builder: (_) => _ShareRoomSheet(
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
      backgroundColor: _surface,
      builder: (_) => _BroadcastSettingsSheet(
        room: widget.room,
        service: _rooms,
      ),
    );

    if (!mounted || saved != true) return;
    _showMessage('Room settings updated.');
  }

  void _openOwnerMenu(List<RoomParticipant> participants) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      showDragHandle: true,
      builder: (_) => _OwnerMenuSheet(
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
      backgroundColor: _surface,
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
              style: TextStyle(color: _muted),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _AnalyticsTile(
                    label: 'Total',
                    value: participants.length,
                    icon: Icons.groups_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AnalyticsTile(
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
                  child: _AnalyticsTile(
                    label: 'Listening',
                    value: listeners,
                    icon: Icons.headphones_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AnalyticsTile(
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
        backgroundColor: _surface,
        title: const Text(
          'End broadcast?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Everyone will be disconnected, the room will disappear from Discover and this broadcast will be marked as closed.',
          style: TextStyle(color: _muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: _accent),
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
        backgroundColor: _surface,
        title: const Text(
          'Delete room permanently?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'This removes the broadcast, participants and room messages. This action cannot be undone.',
          style: TextStyle(color: _muted, height: 1.4),
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
          backgroundColor: isError ? const Color(0xFF4D1722) : _surfaceSoft,
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
      backgroundColor: _background,
      body: SafeArea(
        child: StreamBuilder<List<RoomParticipant>>(
          stream: _rooms.watchParticipants(widget.room.id),
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
                const Positioned.fill(child: _BroadcastBackground()),
                Column(
                  children: [
                    _TopBar(
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
                          _LiveBadge(isLive: widget.room.isLive),
                          const SizedBox(height: 18),
                          _HostStage(
                            participant: host,
                            fallbackName: widget.room.hostName,
                            pulse: _pulse,
                          ),
                          if (_isHost) ...[
                            const SizedBox(height: 16),
                            _OwnerQuickActions(
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
                          _ClickableStats(
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
                          _SectionHeader(
                            title: 'On stage',
                            subtitle: 'Host and approved speakers',
                            count: speakers.length + 1,
                          ),
                          const SizedBox(height: 12),
                          if (speakers.isEmpty)
                            const _EmptyStage()
                          else
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: speakers
                                  .map(
                                    (speaker) => _SpeakerTile(
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
                          _SectionHeader(
                            title: 'Audience',
                            subtitle: 'Listeners can request the stage',
                            count: listeners.length,
                          ),
                          const SizedBox(height: 12),
                          _AudiencePreview(
                            listeners: listeners,
                            onOpen: () => _openParticipants(
                              participants,
                              initialFilter: 'listeners',
                            ),
                          ),
                        ],
                      ),
                    ),
                    _BottomControls(
                      isHost: _isHost,
                      joining: _joining,
                      ending: _ending,
                      handRaised: me?.isHandRaised ?? false,
                      canRaiseHand:
                          me != null && !me.isSpeaker && !me.isHost,
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
                        child: CircularProgressIndicator(color: _accent),
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

class _BroadcastBackground extends StatelessWidget {
  const _BroadcastBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -.42),
          radius: 1.15,
          colors: [Color(0xFF391018), Color(0xFF13070A), Color(0xFF090305)],
        ),
      ),
      child: CustomPaint(painter: _SpotlightPainter()),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x33FF314F), Color(0x00FF314F)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path()
      ..moveTo(size.width * .2, 0)
      ..lineTo(size.width * .46, size.height)
      ..lineTo(size.width * .58, size.height)
      ..lineTo(size.width * .78, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.count,
    required this.isHost,
    required this.onBack,
    required this.onPeople,
    required this.onMenu,
    required this.onShare,
  });

  final String title;
  final int count;
  final bool isHost;
  final VoidCallback onBack;
  final VoidCallback onPeople;
  final VoidCallback onMenu;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            color: Colors.white,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'BROADCAST ROOM',
                  style: TextStyle(
                    color: _BroadcastRoomScreenState._accentSoft,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Share room',
            onPressed: onShare,
            color: Colors.white,
            icon: const Icon(Icons.ios_share_rounded, size: 21),
          ),
          TextButton.icon(
            onPressed: onPeople,
            icon: const Icon(Icons.groups_rounded, size: 18),
            label: Text('$count'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
          if (isHost)
            IconButton(
              tooltip: 'Manage broadcast',
              onPressed: onMenu,
              color: Colors.white,
              icon: const Icon(Icons.more_vert_rounded),
            ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.isLive});

  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return Align(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0x33FF314F),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: const Color(0x88FF314F)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 4,
              backgroundColor: _BroadcastRoomScreenState._accent,
            ),
            const SizedBox(width: 8),
            Text(
              isLive ? 'LIVE BROADCAST' : 'OFFLINE',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HostStage extends StatelessWidget {
  const _HostStage({
    required this.participant,
    required this.fallbackName,
    required this.pulse,
  });

  final RoomParticipant? participant;
  final String fallbackName;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final name = participant?.displayName ?? fallbackName;
    final initial = name.trim().isEmpty ? 'H' : name.trim()[0].toUpperCase();

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      decoration: BoxDecoration(
        color: const Color(0xCC1A0B0F),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF772635)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44FF314F),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.podcasts_rounded,
            color: _BroadcastRoomScreenState._accent,
            size: 30,
          ),
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation: pulse,
            builder: (context, child) => Transform.scale(
              scale: 1 + pulse.value * .025,
              child: child,
            ),
            child: CircleAvatar(
              radius: 61,
              backgroundColor: const Color(0xFF7A1C2D),
              backgroundImage: participant?.photoUrl == null
                  ? null
                  : NetworkImage(participant!.photoUrl!),
              child: participant?.photoUrl == null
                  ? Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 13),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'HOST • ON AIR',
            style: TextStyle(
              color: _BroadcastRoomScreenState._accentSoft,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnerQuickActions extends StatelessWidget {
  const _OwnerQuickActions({
    required this.raisedHands,
    required this.onParticipants,
    required this.onHands,
    required this.onManage,
    required this.onShare,
  });

  final int raisedHands;
  final VoidCallback onParticipants;
  final VoidCallback onHands;
  final VoidCallback onManage;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xE61A0B0F),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _BroadcastRoomScreenState._border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _QuickAction(
              icon: Icons.groups_rounded,
              label: 'Guests',
              onTap: onParticipants,
            ),
          ),
          Expanded(
            child: _QuickAction(
              icon: Icons.back_hand_rounded,
              label: raisedHands > 0 ? 'Hands $raisedHands' : 'Hands',
              onTap: onHands,
              highlighted: raisedHands > 0,
            ),
          ),
          Expanded(
            child: _QuickAction(
              icon: Icons.tune_rounded,
              label: 'Manage',
              onTap: onManage,
            ),
          ),
          Expanded(
            child: _QuickAction(
              icon: Icons.ios_share_rounded,
              label: 'Share',
              onTap: onShare,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: highlighted
                    ? _BroadcastRoomScreenState._accent
                    : const Color(0xFF37141B),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: Colors.white, size: 19),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClickableStats extends StatelessWidget {
  const _ClickableStats({
    required this.speakers,
    required this.listeners,
    required this.raisedHands,
    required this.onSpeakers,
    required this.onListeners,
    required this.onHands,
  });

  final int speakers;
  final int listeners;
  final int raisedHands;
  final VoidCallback onSpeakers;
  final VoidCallback onListeners;
  final VoidCallback onHands;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Speaking',
            value: speakers,
            icon: Icons.graphic_eq_rounded,
            onTap: onSpeakers,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Listeners',
            value: listeners,
            icon: Icons.headphones_rounded,
            onTap: onListeners,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Hands',
            value: raisedHands,
            icon: Icons.back_hand_rounded,
            onTap: onHands,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final int value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _BroadcastRoomScreenState._surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Icon(
                icon,
                color: _BroadcastRoomScreenState._accentSoft,
                size: 20,
              ),
              const SizedBox(height: 5),
              Text(
                '$value',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: _BroadcastRoomScreenState._muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.count,
  });

  final String title;
  final String subtitle;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _BroadcastRoomScreenState._muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        CircleAvatar(
          radius: 14,
          backgroundColor: const Color(0xFF6D1D2B),
          child: Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _SpeakerTile extends StatelessWidget {
  const _SpeakerTile({
    required this.participant,
    required this.isHostView,
    required this.onManage,
  });

  final RoomParticipant participant;
  final bool isHostView;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final initial = participant.displayName.trim().isEmpty
        ? 'Y'
        : participant.displayName.trim()[0].toUpperCase();

    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _BroadcastRoomScreenState._surfaceSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF64212D)),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: const Color(0xFF812033),
            backgroundImage: participant.photoUrl == null
                ? null
                : NetworkImage(participant.photoUrl!),
            child: participant.photoUrl == null
                ? Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 9),
          Text(
            participant.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                participant.isMuted
                    ? Icons.mic_off_rounded
                    : Icons.mic_rounded,
                color: participant.isMuted
                    ? _BroadcastRoomScreenState._muted
                    : _BroadcastRoomScreenState._accentSoft,
                size: 17,
              ),
              if (isHostView) ...[
                const SizedBox(width: 5),
                InkWell(
                  onTap: onManage,
                  child: const Icon(
                    Icons.more_horiz_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyStage extends StatelessWidget {
  const _EmptyStage();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _BroadcastRoomScreenState._surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _BroadcastRoomScreenState._border),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.chair_alt_rounded,
            color: _BroadcastRoomScreenState._accentSoft,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'No guest speakers yet. Raised hands will appear in the participant panel.',
              style: TextStyle(
                color: _BroadcastRoomScreenState._muted,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AudiencePreview extends StatelessWidget {
  const _AudiencePreview({required this.listeners, required this.onOpen});

  final List<RoomParticipant> listeners;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _BroadcastRoomScreenState._surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                height: 42,
                child: Stack(
                  children: [
                    for (
                      var index = 0;
                      index < listeners.take(4).length;
                      index++
                    )
                      Positioned(
                        left: index * 28,
                        child: CircleAvatar(
                          radius: 21,
                          backgroundColor: const Color(0xFF69202C),
                          backgroundImage: listeners[index].photoUrl == null
                              ? null
                              : NetworkImage(listeners[index].photoUrl!),
                          child: listeners[index].photoUrl == null
                              ? Text(
                                  listeners[index].displayName.isEmpty
                                      ? 'Y'
                                      : listeners[index]
                                            .displayName[0]
                                            .toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  listeners.isEmpty
                      ? 'Audience is waiting'
                      : '${listeners.length} listening now',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: _BroadcastRoomScreenState._muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.isHost,
    required this.joining,
    required this.ending,
    required this.handRaised,
    required this.canRaiseHand,
    required this.onJoin,
    required this.onRaiseHand,
    required this.onShare,
    required this.onParticipants,
    required this.onEnd,
  });

  final bool isHost;
  final bool joining;
  final bool ending;
  final bool handRaised;
  final bool canRaiseHand;
  final VoidCallback onJoin;
  final VoidCallback onRaiseHand;
  final VoidCallback onShare;
  final VoidCallback onParticipants;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xF21A0B0F),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _BroadcastRoomScreenState._border),
      ),
      child: isHost
          ? Row(
              children: [
                Expanded(
                  child: _HostBottomAction(
                    icon: Icons.headphones_rounded,
                    label: joining ? 'Joining…' : 'Enter',
                    onTap: joining || ending ? null : onJoin,
                  ),
                ),
                Expanded(
                  child: _HostBottomAction(
                    icon: Icons.groups_rounded,
                    label: 'Guests',
                    onTap: ending ? null : onParticipants,
                  ),
                ),
                Expanded(
                  child: _HostBottomAction(
                    icon: Icons.ios_share_rounded,
                    label: 'Share',
                    onTap: ending ? null : onShare,
                  ),
                ),
                Expanded(
                  child: _HostBottomAction(
                    icon: Icons.stop_circle_rounded,
                    label: 'End',
                    destructive: true,
                    onTap: ending ? null : onEnd,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: joining ? null : onJoin,
                    icon: const Icon(Icons.headphones_rounded),
                    label: Text(joining ? 'Joining…' : 'Join broadcast'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _BroadcastRoomScreenState._accent,
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  onPressed: canRaiseHand ? onRaiseHand : null,
                  style: IconButton.styleFrom(
                    backgroundColor: handRaised
                        ? const Color(0xFFFF6A76)
                        : const Color(0xFF37141B),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(52, 52),
                  ),
                  icon: Icon(
                    handRaised
                        ? Icons.pan_tool_alt_rounded
                        : Icons.back_hand_outlined,
                  ),
                  tooltip: handRaised ? 'Lower hand' : 'Raise hand',
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: onShare,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF37141B),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(52, 52),
                  ),
                  icon: const Icon(Icons.ios_share_rounded),
                  tooltip: 'Share room',
                ),
              ],
            ),
    );
  }
}

class _HostBottomAction extends StatelessWidget {
  const _HostBottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: onTap == null
                  ? Colors.white30
                  : destructive
                  ? _BroadcastRoomScreenState._accentSoft
                  : Colors.white,
              size: 23,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: onTap == null
                    ? Colors.white30
                    : destructive
                    ? _BroadcastRoomScreenState._accentSoft
                    : Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnerMenuSheet extends StatelessWidget {
  const _OwnerMenuSheet({
    required this.onShare,
    required this.onParticipants,
    required this.onHands,
    required this.onSettings,
    required this.onAnalytics,
    required this.onEnd,
    required this.onDelete,
  });

  final VoidCallback onShare;
  final VoidCallback onParticipants;
  final VoidCallback onHands;
  final VoidCallback onSettings;
  final VoidCallback onAnalytics;
  final VoidCallback onEnd;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.fromLTRB(6, 0, 6, 10),
                child: Text(
                  'Manage broadcast',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            _OwnerMenuItem(
              icon: Icons.ios_share_rounded,
              title: 'Share room',
              subtitle: 'Copy the invitation link or room ID',
              onTap: onShare,
            ),
            _OwnerMenuItem(
              icon: Icons.groups_rounded,
              title: 'Participants',
              subtitle: 'Manage stage, audience, mute and removal',
              onTap: onParticipants,
            ),
            _OwnerMenuItem(
              icon: Icons.back_hand_rounded,
              title: 'Raised hands',
              subtitle: 'Review listeners requesting the stage',
              onTap: onHands,
            ),
            _OwnerMenuItem(
              icon: Icons.settings_rounded,
              title: 'Room settings',
              subtitle: 'Edit details, capacity and moderation options',
              onTap: onSettings,
            ),
            _OwnerMenuItem(
              icon: Icons.analytics_rounded,
              title: 'Live analytics',
              subtitle: 'View the current broadcast snapshot',
              onTap: onAnalytics,
            ),
            const Divider(color: Color(0xFF3B171E), height: 22),
            _OwnerMenuItem(
              icon: Icons.stop_circle_rounded,
              title: 'End broadcast',
              subtitle: 'Disconnect everyone and close this broadcast',
              onTap: onEnd,
              destructive: true,
            ),
            _OwnerMenuItem(
              icon: Icons.delete_forever_rounded,
              title: 'Delete room permanently',
              subtitle: 'Remove the room and its messages from YoVoice',
              onTap: onDelete,
              destructive: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnerMenuItem extends StatelessWidget {
  const _OwnerMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? _BroadcastRoomScreenState._accentSoft
        : Colors.white;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      leading: Container(
        width: 43,
        height: 43,
        decoration: BoxDecoration(
          color: destructive
              ? const Color(0xFF45151F)
              : const Color(0xFF301219),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: _BroadcastRoomScreenState._muted,
          fontSize: 12,
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: color),
    );
  }
}

class _ShareRoomSheet extends StatelessWidget {
  const _ShareRoomSheet({
    required this.roomName,
    required this.roomId,
    required this.shareLink,
    required this.onCopyLink,
    required this.onCopyRoomId,
  });

  final String roomName;
  final String roomId;
  final String shareLink;
  final Future<void> Function() onCopyLink;
  final Future<void> Function() onCopyRoomId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share broadcast',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              roomName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _BroadcastRoomScreenState._muted),
            ),
            const SizedBox(height: 18),
            _CopyValueTile(
              icon: Icons.link_rounded,
              title: 'Invite link',
              value: shareLink,
              onTap: () async {
                await onCopyLink();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 10),
            _CopyValueTile(
              icon: Icons.key_rounded,
              title: 'Room ID',
              value: roomId,
              onTap: () async {
                await onCopyRoomId();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyValueTile extends StatelessWidget {
  const _CopyValueTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _BroadcastRoomScreenState._surfaceSoft,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Icon(icon, color: _BroadcastRoomScreenState._accentSoft),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _BroadcastRoomScreenState._muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.copy_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _BroadcastSettingsSheet extends StatefulWidget {
  const _BroadcastSettingsSheet({required this.room, required this.service});

  final VoiceRoom room;
  final RoomService service;

  @override
  State<_BroadcastSettingsSheet> createState() =>
      _BroadcastSettingsSheetState();
}

class _BroadcastSettingsSheetState extends State<_BroadcastSettingsSheet> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late final TextEditingController _language;
  late final TextEditingController _capacity;
  late final TextEditingController _slowMode;

  late String _visibility;
  late bool _approvalRequired;
  late bool _autoMuteNewUsers;
  late bool _membersCanStartVoice;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final room = widget.room;
    _name = TextEditingController(text: room.name);
    _description = TextEditingController(text: room.description);
    _category = TextEditingController(text: room.category);
    _language = TextEditingController(text: room.language);
    _capacity = TextEditingController(
      text: room.maxParticipants?.toString() ?? '',
    );
    _slowMode = TextEditingController(text: room.slowModeSeconds.toString());
    _visibility = room.visibility;
    _approvalRequired = room.approvalRequired;
    _autoMuteNewUsers = room.autoMuteNewUsers;
    _membersCanStartVoice = room.membersCanStartVoice;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _category.dispose();
    _language.dispose();
    _capacity.dispose();
    _slowMode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    final capacityText = _capacity.text.trim();
    final capacity = capacityText.isEmpty ? null : int.tryParse(capacityText);
    final slowMode = int.tryParse(_slowMode.text.trim()) ?? 0;

    if (capacityText.isNotEmpty && (capacity == null || capacity <= 0)) {
      _showError('Capacity must be a positive number.');
      return;
    }

    if (slowMode < 0) {
      _showError('Slow mode cannot be negative.');
      return;
    }

    setState(() => _saving = true);

    try {
      await widget.service.updateRoomSettings(
        roomId: widget.room.id,
        name: _name.text,
        description: _description.text,
        category: _category.text.trim().isEmpty
            ? widget.room.category
            : _category.text.trim(),
        visibility: _visibility,
        language: _language.text.trim().isEmpty
            ? widget.room.language
            : _language.text.trim(),
        maxParticipants: capacity,
        approvalRequired: _approvalRequired,
        slowModeSeconds: slowMode,
        autoMuteNewUsers: _autoMuteNewUsers,
        membersCanStartVoice: _membersCanStartVoice,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(
        error
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Invalid argument(s): ', ''),
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 10,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const Text(
              'Room settings',
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Changes are saved directly to this broadcast.',
              style: TextStyle(color: _BroadcastRoomScreenState._muted),
            ),
            const SizedBox(height: 20),
            _SettingsField(
              controller: _name,
              label: 'Room name',
              maxLength: 80,
            ),
            const SizedBox(height: 12),
            _SettingsField(
              controller: _description,
              label: 'Description',
              maxLines: 3,
              maxLength: 300,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SettingsField(
                    controller: _category,
                    label: 'Category',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SettingsField(
                    controller: _language,
                    label: 'Language',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SettingsField(
                    controller: _capacity,
                    label: 'Capacity',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SettingsField(
                    controller: _slowMode,
                    label: 'Slow mode (sec)',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _visibility,
              dropdownColor: _BroadcastRoomScreenState._surfaceSoft,
              decoration: _settingsDecoration('Visibility'),
              style: const TextStyle(color: Colors.white),
              items: const [
                DropdownMenuItem(value: 'public', child: Text('Public')),
                DropdownMenuItem(value: 'private', child: Text('Private')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _visibility = value);
              },
            ),
            const SizedBox(height: 14),
            _SettingsSwitch(
              title: 'Auto-mute new listeners',
              subtitle: 'New participants enter without an active microphone.',
              value: _autoMuteNewUsers,
              onChanged: (value) =>
                  setState(() => _autoMuteNewUsers = value),
            ),
            _SettingsSwitch(
              title: 'Approval required',
              subtitle: 'Keep this option ready for invite approval workflows.',
              value: _approvalRequired,
              onChanged: (value) =>
                  setState(() => _approvalRequired = value),
            ),
            _SettingsSwitch(
              title: 'Members can start voice',
              subtitle: 'Stored for compatibility with the shared room model.',
              value: _membersCanStartVoice,
              onChanged: (value) =>
                  setState(() => _membersCanStartVoice = value),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: _BroadcastRoomScreenState._accent,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_saving ? 'Saving…' : 'Save settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      cursorColor: _BroadcastRoomScreenState._accent,
      decoration: _settingsDecoration(label),
    );
  }
}

InputDecoration _settingsDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: _BroadcastRoomScreenState._muted),
    filled: true,
    fillColor: _BroadcastRoomScreenState._surfaceSoft,
    counterStyle: const TextStyle(color: _BroadcastRoomScreenState._muted),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _BroadcastRoomScreenState._border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(
        color: _BroadcastRoomScreenState._accent,
        width: 1.4,
      ),
    ),
  );
}

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      activeTrackColor: _BroadcastRoomScreenState._accent,
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: _BroadcastRoomScreenState._muted,
          fontSize: 12,
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _AnalyticsTile extends StatelessWidget {
  const _AnalyticsTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _BroadcastRoomScreenState._surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _BroadcastRoomScreenState._border),
      ),
      child: Column(
        children: [
          Icon(icon, color: _BroadcastRoomScreenState._accentSoft),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: _BroadcastRoomScreenState._muted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _BroadcastParticipantsSheet extends StatefulWidget {
  const _BroadcastParticipantsSheet({
    required this.roomId,
    required this.participants,
    required this.isHost,
    required this.initialFilter,
    required this.service,
  });

  final String roomId;
  final List<RoomParticipant> participants;
  final bool isHost;
  final String initialFilter;
  final RoomService service;

  @override
  State<_BroadcastParticipantsSheet> createState() =>
      _BroadcastParticipantsSheetState();
}

class _BroadcastParticipantsSheetState
    extends State<_BroadcastParticipantsSheet> {
  late String _filter = widget.initialFilter;

  List<RoomParticipant> get _visible {
    return switch (_filter) {
      'speakers' => widget.participants.where((p) => p.isSpeaker).toList(),
      'listeners' => widget.participants.where((p) => !p.isSpeaker).toList(),
      'hands' => widget.participants.where((p) => p.isHandRaised).toList(),
      _ => widget.participants,
    };
  }

  Future<void> _action(Future<void> Function() callback) async {
    try {
      await callback();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;

    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Broadcast participants',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(
                Icons.groups_rounded,
                color: _BroadcastRoomScreenState._accentSoft,
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (
                final filter in const [
                  ('all', 'All'),
                  ('speakers', 'Stage'),
                  ('listeners', 'Audience'),
                  ('hands', 'Raised hands'),
                ]
              )
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: _filter == filter.$1,
                    onSelected: (_) => setState(() => _filter = filter.$1),
                    label: Text(filter.$2),
                    selectedColor: const Color(0xFF762333),
                    backgroundColor: const Color(0xFF2B1117),
                    labelStyle: const TextStyle(color: Colors.white),
                    side: BorderSide.none,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text(
                    'Nobody here yet.',
                    style: TextStyle(
                      color: _BroadcastRoomScreenState._muted,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 22),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(
                    color: Color(0xFF3B171E),
                    height: 1,
                  ),
                  itemBuilder: (context, index) {
                    final person = items[index];

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 5,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF792032),
                        backgroundImage: person.photoUrl == null
                            ? null
                            : NetworkImage(person.photoUrl!),
                        child: person.photoUrl == null
                            ? Text(
                                person.displayName.isEmpty
                                    ? 'Y'
                                    : person.displayName[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              )
                            : null,
                      ),
                      title: Text(
                        person.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        person.isHost
                            ? 'Host'
                            : person.isSpeaker
                            ? 'Speaker${person.isMuted ? ' • muted' : ''}'
                            : person.isHandRaised
                            ? 'Listener • hand raised'
                            : 'Listener',
                        style: TextStyle(
                          color: person.isHandRaised
                              ? _BroadcastRoomScreenState._accentSoft
                              : _BroadcastRoomScreenState._muted,
                        ),
                      ),
                      trailing: !widget.isHost || person.isHost
                          ? Icon(
                              person.isHandRaised
                                  ? Icons.back_hand_rounded
                                  : person.isSpeaker
                                  ? Icons.mic_rounded
                                  : Icons.headphones_rounded,
                              color: person.isHandRaised
                                  ? _BroadcastRoomScreenState._accentSoft
                                  : _BroadcastRoomScreenState._muted,
                            )
                          : PopupMenuButton<String>(
                              color: const Color(0xFF261016),
                              iconColor: Colors.white,
                              onSelected: (value) {
                                switch (value) {
                                  case 'stage':
                                    _action(
                                      () => widget.service
                                          .setParticipantSpeakerStatus(
                                            roomId: widget.roomId,
                                            participantId: person.userId,
                                            isSpeaker: true,
                                          ),
                                    );
                                  case 'audience':
                                    _action(
                                      () => widget.service
                                          .setParticipantSpeakerStatus(
                                            roomId: widget.roomId,
                                            participantId: person.userId,
                                            isSpeaker: false,
                                          ),
                                    );
                                  case 'mute':
                                    _action(
                                      () => widget.service
                                          .moderateParticipantMute(
                                            roomId: widget.roomId,
                                            participantId: person.userId,
                                            isMuted: true,
                                          ),
                                    );
                                  case 'unmute':
                                    _action(
                                      () => widget.service
                                          .moderateParticipantMute(
                                            roomId: widget.roomId,
                                            participantId: person.userId,
                                            isMuted: false,
                                          ),
                                    );
                                  case 'remove':
                                    _action(
                                      () => widget.service.removeParticipant(
                                        roomId: widget.roomId,
                                        participantId: person.userId,
                                      ),
                                    );
                                }
                              },
                              itemBuilder: (_) => [
                                if (!person.isSpeaker)
                                  const PopupMenuItem(
                                    value: 'stage',
                                    child: Text(
                                      'Invite to stage',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                if (person.isSpeaker)
                                  const PopupMenuItem(
                                    value: 'audience',
                                    child: Text(
                                      'Move to audience',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                if (person.isSpeaker && !person.isMuted)
                                  const PopupMenuItem(
                                    value: 'mute',
                                    child: Text(
                                      'Mute participant',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                if (person.isSpeaker && person.isMuted)
                                  const PopupMenuItem(
                                    value: 'unmute',
                                    child: Text(
                                      'Allow microphone',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text(
                                    'Remove from room',
                                    style: TextStyle(color: Color(0xFFFF6A76)),
                                  ),
                                ),
                              ],
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
