import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _isHost => widget.room.hostId == _uid;

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _toggleHand(RoomParticipant? me) async {
    if (me == null || me.isSpeaker || me.isHost) return;
    await _rooms.setHandRaised(
      roomId: widget.room.id,
      isRaised: !me.isHandRaised,
    );
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
                      onBack: () => Navigator.of(context).pop(),
                      onPeople: () => _openParticipants(participants),
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
                      joining: _joining,
                      handRaised: me?.isHandRaised ?? false,
                      canRaiseHand: me != null && !me.isSpeaker && !me.isHost,
                      onJoin: _joinVoice,
                      onRaiseHand: () => _toggleHand(me),
                    ),
                  ],
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
    required this.onBack,
    required this.onPeople,
  });

  final String title;
  final int count;
  final VoidCallback onBack;
  final VoidCallback onPeople;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 10, 4),
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
          TextButton.icon(
            onPressed: onPeople,
            icon: const Icon(Icons.groups_rounded, size: 18),
            label: Text('$count'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
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
          BoxShadow(color: Color(0x44FF314F), blurRadius: 28, spreadRadius: 2),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.podcasts_rounded, color: _BroadcastRoomScreenState._accent, size: 30),
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
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'HOST • ON AIR',
            style: TextStyle(color: _BroadcastRoomScreenState._accentSoft, fontSize: 11, fontWeight: FontWeight.w900),
          ),
        ],
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
        Expanded(child: _StatTile(label: 'Speaking', value: speakers, icon: Icons.graphic_eq_rounded, onTap: onSpeakers)),
        const SizedBox(width: 10),
        Expanded(child: _StatTile(label: 'Listeners', value: listeners, icon: Icons.headphones_rounded, onTap: onListeners)),
        const SizedBox(width: 10),
        Expanded(child: _StatTile(label: 'Hands', value: raisedHands, icon: Icons.back_hand_rounded, onTap: onHands)),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.icon, required this.onTap});
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
              Icon(icon, color: _BroadcastRoomScreenState._accentSoft, size: 20),
              const SizedBox(height: 5),
              Text('$value', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              Text(label, style: const TextStyle(color: _BroadcastRoomScreenState._muted, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle, required this.count});
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
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
              Text(subtitle, style: const TextStyle(color: _BroadcastRoomScreenState._muted, fontSize: 12)),
            ],
          ),
        ),
        CircleAvatar(
          radius: 14,
          backgroundColor: const Color(0xFF6D1D2B),
          child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }
}

class _SpeakerTile extends StatelessWidget {
  const _SpeakerTile({required this.participant, required this.isHostView, required this.onManage});
  final RoomParticipant participant;
  final bool isHostView;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final initial = participant.displayName.trim().isEmpty ? 'Y' : participant.displayName.trim()[0].toUpperCase();
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
            backgroundImage: participant.photoUrl == null ? null : NetworkImage(participant.photoUrl!),
            child: participant.photoUrl == null ? Text(initial, style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900)) : null,
          ),
          const SizedBox(height: 9),
          Text(participant.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(participant.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded, color: participant.isMuted ? _BroadcastRoomScreenState._muted : _BroadcastRoomScreenState._accentSoft, size: 17),
              if (isHostView) ...[
                const SizedBox(width: 5),
                InkWell(onTap: onManage, child: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 18)),
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
          Icon(Icons.chair_alt_rounded, color: _BroadcastRoomScreenState._accentSoft),
          SizedBox(width: 12),
          Expanded(child: Text('No guest speakers yet. Raised hands will appear in the participant panel.', style: TextStyle(color: _BroadcastRoomScreenState._muted, height: 1.35))),
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
                    for (var index = 0; index < listeners.take(4).length; index++)
                      Positioned(
                        left: index * 28,
                        child: CircleAvatar(
                          radius: 21,
                          backgroundColor: const Color(0xFF69202C),
                          backgroundImage: listeners[index].photoUrl == null ? null : NetworkImage(listeners[index].photoUrl!),
                          child: listeners[index].photoUrl == null
                              ? Text(listeners[index].displayName.isEmpty ? 'Y' : listeners[index].displayName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  listeners.isEmpty ? 'Audience is waiting' : '${listeners.length} listening now',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _BroadcastRoomScreenState._muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({required this.joining, required this.handRaised, required this.canRaiseHand, required this.onJoin, required this.onRaiseHand});
  final bool joining;
  final bool handRaised;
  final bool canRaiseHand;
  final VoidCallback onJoin;
  final VoidCallback onRaiseHand;

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
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: joining ? null : onJoin,
              icon: const Icon(Icons.headphones_rounded),
              label: Text(joining ? 'Joining…' : 'Join broadcast'),
              style: FilledButton.styleFrom(backgroundColor: _BroadcastRoomScreenState._accent, minimumSize: const Size.fromHeight(52)),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            onPressed: canRaiseHand ? onRaiseHand : null,
            style: IconButton.styleFrom(
              backgroundColor: handRaised ? const Color(0xFFFF6A76) : const Color(0xFF37141B),
              foregroundColor: Colors.white,
              minimumSize: const Size(52, 52),
            ),
            icon: Icon(handRaised ? Icons.pan_tool_alt_rounded : Icons.back_hand_outlined),
            tooltip: handRaised ? 'Lower hand' : 'Raise hand',
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
  State<_BroadcastParticipantsSheet> createState() => _BroadcastParticipantsSheetState();
}

class _BroadcastParticipantsSheetState extends State<_BroadcastParticipantsSheet> {
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(width: 42, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(99))),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Row(
            children: [
              Expanded(child: Text('Broadcast participants', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900))),
              Icon(Icons.groups_rounded, color: _BroadcastRoomScreenState._accentSoft),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final filter in const [('all', 'All'), ('speakers', 'Stage'), ('listeners', 'Audience'), ('hands', 'Raised hands')])
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
              ? const Center(child: Text('Nobody here yet.', style: TextStyle(color: _BroadcastRoomScreenState._muted)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 22),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(color: Color(0xFF3B171E), height: 1),
                  itemBuilder: (context, index) {
                    final person = items[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF792032),
                        backgroundImage: person.photoUrl == null ? null : NetworkImage(person.photoUrl!),
                        child: person.photoUrl == null ? Text(person.displayName.isEmpty ? 'Y' : person.displayName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)) : null,
                      ),
                      title: Text(person.displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      subtitle: Text(
                        person.isHost
                            ? 'Host'
                            : person.isSpeaker
                            ? 'Speaker${person.isMuted ? ' • muted' : ''}'
                            : person.isHandRaised
                            ? 'Listener • hand raised'
                            : 'Listener',
                        style: TextStyle(color: person.isHandRaised ? _BroadcastRoomScreenState._accentSoft : _BroadcastRoomScreenState._muted),
                      ),
                      trailing: !widget.isHost || person.isHost
                          ? Icon(person.isHandRaised ? Icons.back_hand_rounded : person.isSpeaker ? Icons.mic_rounded : Icons.headphones_rounded, color: person.isHandRaised ? _BroadcastRoomScreenState._accentSoft : _BroadcastRoomScreenState._muted)
                          : PopupMenuButton<String>(
                              color: const Color(0xFF261016),
                              iconColor: Colors.white,
                              onSelected: (value) {
                                switch (value) {
                                  case 'stage':
                                    _action(() => widget.service.setParticipantSpeakerStatus(roomId: widget.roomId, participantId: person.userId, isSpeaker: true));
                                    break;
                                  case 'audience':
                                    _action(() => widget.service.setParticipantSpeakerStatus(roomId: widget.roomId, participantId: person.userId, isSpeaker: false));
                                    break;
                                  case 'mute':
                                    _action(() => widget.service.moderateParticipantMute(roomId: widget.roomId, participantId: person.userId, isMuted: true));
                                    break;
                                  case 'remove':
                                    _action(() => widget.service.removeParticipant(roomId: widget.roomId, participantId: person.userId));
                                    break;
                                }
                              },
                              itemBuilder: (_) => [
                                if (!person.isSpeaker) const PopupMenuItem(value: 'stage', child: Text('Invite to stage', style: TextStyle(color: Colors.white))),
                                if (person.isSpeaker) const PopupMenuItem(value: 'audience', child: Text('Move to audience', style: TextStyle(color: Colors.white))),
                                if (person.isSpeaker && !person.isMuted) const PopupMenuItem(value: 'mute', child: Text('Mute participant', style: TextStyle(color: Colors.white))),
                                const PopupMenuItem(value: 'remove', child: Text('Remove from room', style: TextStyle(color: Color(0xFFFF6A76)))),
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
