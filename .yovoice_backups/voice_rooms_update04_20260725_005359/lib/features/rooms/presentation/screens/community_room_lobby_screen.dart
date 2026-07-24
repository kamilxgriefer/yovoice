import 'package:flutter/material.dart';

import 'package:yovoice/features/calls/presentation/screens/voice_call_screen.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

class CommunityRoomLobbyScreen extends StatefulWidget {
  const CommunityRoomLobbyScreen({required this.room, super.key});

  final VoiceRoom room;

  @override
  State<CommunityRoomLobbyScreen> createState() =>
      _CommunityRoomLobbyScreenState();
}

class _CommunityRoomLobbyScreenState extends State<CommunityRoomLobbyScreen> {
  static const _background = Color(0xFF07050D);
  static const _surface = Color(0xFF151020);
  static const _surface2 = Color(0xFF21142D);
  static const _border = Color(0xFF3A2C49);
  static const _primary = Color(0xFF9D20FF);
  static const _muted = Color(0xFFA69CAF);

  final RoomService _rooms = RoomService();
  bool _joining = false;

  Future<void> _joinVoice() async {
    if (_joining) return;
    setState(() => _joining = true);

    try {
      await _rooms.joinRoom(widget.room.id);
      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VoiceCallScreen(
            roomId: widget.room.id,
            roomName: widget.room.name,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-.75, -.85),
            radius: 1.35,
            colors: [Color(0xFF30124A), Color(0xFF120B1B), _background],
            stops: [0, .42, 1],
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<List<RoomParticipant>>(
            stream: _rooms.watchParticipants(widget.room.id),
            builder: (context, snapshot) {
              final people = snapshot.data ?? const <RoomParticipant>[];

              return Column(
                children: [
                  _TopBar(roomName: widget.room.name),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
                      children: [
                        _HeroCard(room: widget.room, people: people),
                        const SizedBox(height: 24),
                        const Text(
                          'Who is already inside',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _PeoplePreview(people: people),
                        const SizedBox(height: 24),
                        _RoomDetails(room: widget.room),
                      ],
                    ),
                  ),
                  _BottomJoinBar(
                    joining: _joining,
                    participantCount: people.length,
                    onJoin: _joinVoice,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.roomName});

  final String roomName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
            color: Colors.white,
          ),
          const SizedBox(width: 4),
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
                const Text(
                  'COMMUNITY ROOM',
                  style: TextStyle(
                    color: _CommunityRoomLobbyScreenState._primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .8,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: () {},
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Share room',
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.room, required this.people});

  final VoiceRoom room;
  final List<RoomParticipant> people;

  @override
  Widget build(BuildContext context) {
    final initial = room.name.trim().isEmpty
        ? 'Y'
        : room.name.trim().substring(0, 1).toUpperCase();

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF603780)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2C153D), Color(0xFF171020)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 28, offset: Offset(0, 16)),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 108,
            height: 108,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFB629FF), Color(0xFF6123C8)],
              ),
              boxShadow: [
                BoxShadow(color: Color(0x669D20FF), blurRadius: 28),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 46,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            room.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            room.description.trim().isEmpty
                ? 'A live conversation where everyone can speak.'
                : room.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _CommunityRoomLobbyScreenState._muted,
              height: 1.45,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 9,
            runSpacing: 9,
            children: [
              const _Badge(icon: Icons.circle, label: 'LIVE'),
              _Badge(icon: Icons.language_rounded, label: room.language),
              _Badge(
                icon: Icons.people_alt_rounded,
                label: '${people.length}/${room.maxParticipants}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1728),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4A365A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFFC64BFF)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PeoplePreview extends StatelessWidget {
  const _PeoplePreview({required this.people});

  final List<RoomParticipant> people;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _CommunityRoomLobbyScreenState._surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _CommunityRoomLobbyScreenState._border),
        ),
        child: const Column(
          children: [
            Icon(Icons.graphic_eq_rounded, color: Color(0xFFC64BFF), size: 36),
            SizedBox(height: 10),
            Text(
              'Be the first voice in the room.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: people.take(8).map((person) {
        final name = person.displayName.trim().isEmpty
            ? 'Y'
            : person.displayName.trim().substring(0, 1).toUpperCase();
        return Container(
          width: 92,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _CommunityRoomLobbyScreenState._surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _CommunityRoomLobbyScreenState._border),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: const Color(0xFF7223B4),
                child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(height: 8),
              Text(
                person.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        );
      }).toList(growable: false),
    );
  }
}

class _RoomDetails extends StatelessWidget {
  const _RoomDetails({required this.room});

  final VoiceRoom room;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _CommunityRoomLobbyScreenState._surface2,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _CommunityRoomLobbyScreenState._border),
      ),
      child: Column(
        children: [
          _DetailRow(icon: Icons.mic_rounded, label: 'Everyone can speak'),
          const Divider(color: Color(0xFF3A2C49), height: 24),
          _DetailRow(icon: Icons.translate_rounded, label: room.language),
          const Divider(color: Color(0xFF3A2C49), height: 24),
          _DetailRow(
            icon: Icons.lock_open_rounded,
            label: room.visibility.name.toUpperCase(),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFC64BFF), size: 21),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _BottomJoinBar extends StatelessWidget {
  const _BottomJoinBar({
    required this.joining,
    required this.participantCount,
    required this.onJoin,
  });

  final bool joining;
  final int participantCount;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 13, 16, 13 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF100B18),
        border: Border(top: BorderSide(color: Color(0xFF34243F))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Ready to join?',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                ),
                Text(
                  '$participantCount voices inside',
                  style: const TextStyle(color: Color(0xFFA69CAF), fontSize: 12),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: joining ? null : onJoin,
            icon: joining
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login_rounded),
            label: Text(joining ? 'Joining…' : 'Join voice'),
            style: FilledButton.styleFrom(
              backgroundColor: _CommunityRoomLobbyScreenState._primary,
              minimumSize: const Size(150, 52),
            ),
          ),
        ],
      ),
    );
  }
}
