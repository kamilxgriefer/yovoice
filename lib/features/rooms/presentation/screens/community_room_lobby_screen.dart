import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/community_voice_room_screen.dart';

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
  bool _closing = false;

  bool get _isHost =>
      FirebaseAuth.instance.currentUser?.uid == widget.room.hostId;

  Future<void> _joinVoice() async {
    if (_joining) return;
    setState(() => _joining = true);

    try {
      await _rooms.joinRoom(widget.room.id);
      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CommunityVoiceRoomScreen(room: widget.room),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _shareRoom() async {
    final uri = Uri.https('yovoice.app', '/', {'room': widget.room.id});
    await SharePlus.instance.share(
      ShareParams(
        title: 'Join ${widget.room.name} on YO Voice',
        subject: 'YO Voice room invitation',
        text: 'Join "${widget.room.name}" on YO Voice.\n\n$uri',
      ),
    );
  }

  Future<void> _closeRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _surface,
          title: const Text(
            'Close this room?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'The live session will end for everyone and the room will disappear from Home and Discover.',
            style: TextStyle(color: _muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Color(0xFFFF416C)),
              child: const Text('Close room'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || _closing) return;

    setState(() => _closing = true);
    try {
      await _rooms.setRoomStatus(widget.room.id, RoomStatus.closed);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  void _showPeople(List<RoomParticipant> people) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _PeopleSheet(people: people),
    );
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
                  _TopBar(
                    roomName: widget.room.name,
                    isHost: _isHost,
                    closing: _closing,
                    onShare: _shareRoom,
                    onClose: _closeRoom,
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                      children: [
                        _LivingCommunityCard(room: widget.room, people: people),
                        const SizedBox(height: 20),
                        _PeoplePanel(
                          people: people,
                          onViewAll: () => _showPeople(people),
                        ),
                        const SizedBox(height: 16),
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
  const _TopBar({
    required this.roomName,
    required this.isHost,
    required this.closing,
    required this.onShare,
    required this.onClose,
  });

  final String roomName;
  final bool isHost;
  final bool closing;
  final VoidCallback onShare;
  final VoidCallback onClose;

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
          IconButton.filled(
            onPressed: onShare,
            style: IconButton.styleFrom(
              backgroundColor: _CommunityRoomLobbyScreenState._primary,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Share room',
          ),
          if (isHost) ...[
            const SizedBox(width: 6),
            IconButton.filled(
              onPressed: closing ? null : onClose,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFFF416C),
                foregroundColor: Colors.white,
              ),
              icon: closing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.stop_circle_rounded),
              tooltip: 'Close room',
            ),
          ],
        ],
      ),
    );
  }
}

class _LivingCommunityCard extends StatefulWidget {
  const _LivingCommunityCard({required this.room, required this.people});

  final VoiceRoom room;
  final List<RoomParticipant> people;

  @override
  State<_LivingCommunityCard> createState() => _LivingCommunityCardState();
}

class _LivingCommunityCardState extends State<_LivingCommunityCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final speakers = widget.people.where((person) => person.isSpeaker).length;
    final initial = widget.room.name.trim().isEmpty
        ? 'Y'
        : widget.room.name.trim().substring(0, 1).toUpperCase();

    return Container(
      height: 430,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFF633587)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 32,
            offset: Offset(0, 18),
          ),
          BoxShadow(color: Color(0x339D20FF), blurRadius: 36),
        ],
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, .05),
                    radius: .95,
                    colors: [
                      Color(0xFF33104C),
                      Color(0xFF160C22),
                      Color(0xFF09060F),
                    ],
                    stops: [0, .48, 1],
                  ),
                ),
              ),
              CustomPaint(
                painter: _LobbySpacePainter(progress: _controller.value),
              ),
              _OrbitPeople(
                people: widget.people.take(6).toList(growable: false),
                progress: _controller.value,
              ),
              Center(
                child: Transform.scale(
                  scale: 1 + math.sin(_controller.value * math.pi * 2) * .025,
                  child: Container(
                    width: 142,
                    height: 142,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [
                          Color(0xFFFF75FF),
                          Color(0xFF9D20FF),
                          Color(0xFF361059),
                        ],
                        stops: [0, .48, 1],
                      ),
                      border: Border.all(
                        color: const Color(0xFFC86BFF),
                        width: 2.2,
                      ),
                      boxShadow: const [
                        BoxShadow(color: Color(0xAA9D20FF), blurRadius: 42),
                        BoxShadow(color: Color(0x55FF54E8), blurRadius: 70),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 43,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'COMMUNITY',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                top: 18,
                child: Row(
                  children: [
                    const _LivePill(),
                    const Spacer(),
                    _GlassPill(
                      icon: Icons.graphic_eq_rounded,
                      label: '$speakers speaking',
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 18,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(17, 14, 17, 15),
                  decoration: BoxDecoration(
                    color: const Color(0xCC100A19),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFF5B3672)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x55000000), blurRadius: 18),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        widget.room.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        widget.room.description.trim().isEmpty
                            ? 'A live conversation where everyone can speak.'
                            : widget.room.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _CommunityRoomLobbyScreenState._muted,
                          height: 1.35,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 11),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _GlassPill(
                            icon: Icons.language_rounded,
                            label: widget.room.language,
                          ),
                          _GlassPill(
                            icon: Icons.people_alt_rounded,
                            label:
                                '${widget.people.length}/${widget.room.maxParticipants ?? '∞'}',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xDD2A0D38),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFB937FF)),
        boxShadow: const [BoxShadow(color: Color(0x559D20FF), blurRadius: 14)],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: Color(0xFFFF57EA), size: 9),
          SizedBox(width: 7),
          Text(
            'LIVE NOW',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: .8,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xAA1A1025),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF503462)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFC64BFF)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbitPeople extends StatelessWidget {
  const _OrbitPeople({required this.people, required this.progress});

  final List<RoomParticipant> people;
  final double progress;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final center = Offset(
          constraints.maxWidth / 2,
          constraints.maxHeight / 2,
        );
        final orbitRadius = math.min(constraints.maxWidth * .37, 145.0);

        return Stack(
          children: [
            for (var index = 0; index < people.length; index++)
              _buildPerson(
                person: people[index],
                index: index,
                center: center,
                radius: orbitRadius,
              ),
          ],
        );
      },
    );
  }

  Widget _buildPerson({
    required RoomParticipant person,
    required int index,
    required Offset center,
    required double radius,
  }) {
    final angle =
        (math.pi * 2 / people.length) * index + progress * math.pi * .11;
    final localRadius = radius - (index.isOdd ? 16 : 0);
    final x = center.dx + math.cos(angle) * localRadius - 27;
    final y = center.dy + math.sin(angle) * localRadius - 27;

    return Positioned(
      left: x,
      top: y,
      child: _PersonAvatar(person: person, radius: 27, showName: false),
    );
  }
}

class _LobbySpacePainter extends CustomPainter {
  const _LobbySpacePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x557A2BA5);

    for (final factor in <double>[.27, .39, .52]) {
      final radius = math.min(size.width, size.height) * factor;
      canvas.drawCircle(center, radius, orbitPaint);
    }

    final starPaint = Paint();
    for (var i = 0; i < 56; i++) {
      final seed = i * 91.7;
      final x = (math.sin(seed) * .5 + .5) * size.width;
      final baseY = (math.cos(seed * 1.31) * .5 + .5) * size.height;
      final y = (baseY + progress * (4 + i % 5)) % size.height;
      final glow = .35 + .65 * (math.sin(progress * math.pi * 2 + i) * .5 + .5);
      starPaint.color = i % 7 == 0
          ? Color.fromRGBO(77, 184, 255, glow)
          : Color.fromRGBO(198, 75, 255, glow);
      canvas.drawCircle(Offset(x, y), i % 9 == 0 ? 1.8 : .8, starPaint);
    }

    final pulse = 155 + math.sin(progress * math.pi * 2) * 9;
    final pulsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0x339D20FF);
    canvas.drawCircle(center, pulse, pulsePaint);
  }

  @override
  bool shouldRepaint(covariant _LobbySpacePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _PeoplePanel extends StatelessWidget {
  const _PeoplePanel({required this.people, required this.onViewAll});

  final List<RoomParticipant> people;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xCC151020),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _CommunityRoomLobbyScreenState._border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'People here',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: people.isEmpty ? null : onViewAll,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                label: Text('View all ${people.length}'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFC64BFF),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (people.isEmpty)
            const _EmptyPeopleState()
          else
            SizedBox(
              height: 82,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: math.min(people.length, 8),
                separatorBuilder: (_, __) => const SizedBox(width: 13),
                itemBuilder: (context, index) {
                  final person = people[index];
                  return SizedBox(
                    width: 62,
                    child: Column(
                      children: [
                        _PersonAvatar(
                          person: person,
                          radius: 23,
                          showName: false,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          person.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
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

class _EmptyPeopleState extends StatelessWidget {
  const _EmptyPeopleState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(Icons.graphic_eq_rounded, color: Color(0xFFC64BFF), size: 30),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Be the first voice in this community.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({
    required this.person,
    required this.radius,
    required this.showName,
  });

  final RoomParticipant person;
  final double radius;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final initial = person.displayName.trim().isEmpty
        ? 'Y'
        : person.displayName.trim().substring(0, 1).toUpperCase();
    final speaking = person.isSpeaker && !person.isMuted;

    final avatar = Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: speaking ? const Color(0xFFFF66E9) : const Color(0xFF7B39B3),
          width: speaking ? 2.5 : 1.5,
        ),
        boxShadow: speaking
            ? const [
                BoxShadow(color: Color(0xAAE742FF), blurRadius: 18),
                BoxShadow(color: Color(0x668A2BE2), blurRadius: 30),
              ]
            : const [BoxShadow(color: Color(0x44000000), blurRadius: 8)],
      ),
      child: ClipOval(
        child: person.photoUrl != null && person.photoUrl!.trim().isNotEmpty
            ? Image.network(
                person.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _InitialAvatar(initial: initial),
              )
            : _InitialAvatar(initial: initial),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: radius * .48,
            height: radius * .48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: speaking
                  ? const Color(0xFF37E789)
                  : const Color(0xFF261C30),
              border: Border.all(color: const Color(0xFF0B0710), width: 2),
            ),
            child: Icon(
              speaking ? Icons.mic_rounded : Icons.mic_off_rounded,
              size: radius * .26,
              color: Colors.white,
            ),
          ),
        ),
        if (person.isHost)
          Positioned(
            top: -10,
            left: radius - 8,
            child: const Icon(
              Icons.workspace_premium_rounded,
              size: 17,
              color: Color(0xFFFFD65C),
            ),
          ),
        if (showName)
          Positioned(
            left: -18,
            right: -18,
            top: radius * 2 + 5,
            child: Text(
              person.displayName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF7223B4),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
      ),
    );
  }
}

class _PeopleSheet extends StatefulWidget {
  const _PeopleSheet({required this.people});

  final List<RoomParticipant> people;

  @override
  State<_PeopleSheet> createState() => _PeopleSheetState();
}

class _PeopleSheetState extends State<_PeopleSheet> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.people
        .where((person) {
          return person.displayName.toLowerCase().contains(
            _query.toLowerCase(),
          );
        })
        .toList(growable: false);

    return DraggableScrollableSheet(
      initialChildSize: .72,
      minChildSize: .45,
      maxChildSize: .92,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF100B18),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            border: Border(top: BorderSide(color: Color(0xFF59326F))),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF5A4D64),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'People here (${widget.people.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: TextField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search people',
                    hintStyle: const TextStyle(color: Color(0xFF8E8498)),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFFC64BFF),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1B1423),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFF3A2C49)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFF3A2C49)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFF9D20FF)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(
                    18,
                    4,
                    18,
                    18 + MediaQuery.paddingOf(context).bottom,
                  ),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Color(0xFF2C2235), height: 1),
                  itemBuilder: (context, index) {
                    final person = filtered[index];
                    final status = person.isHost
                        ? 'Host'
                        : person.isSpeaker && !person.isMuted
                        ? 'Speaking'
                        : person.isMuted
                        ? 'Muted'
                        : 'Listening';

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 5),
                      leading: _PersonAvatar(
                        person: person,
                        radius: 22,
                        showName: false,
                      ),
                      title: Text(
                        person.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        status,
                        style: TextStyle(
                          color: person.isSpeaker && !person.isMuted
                              ? const Color(0xFFFF66E9)
                              : const Color(0xFFA69CAF),
                        ),
                      ),
                      trailing: person.isHost
                          ? const Icon(
                              Icons.workspace_premium_rounded,
                              color: Color(0xFFFFD65C),
                            )
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RoomDetails extends StatelessWidget {
  const _RoomDetails({required this.room});

  final VoiceRoom room;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      decoration: BoxDecoration(
        color: _CommunityRoomLobbyScreenState._surface2,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _CommunityRoomLobbyScreenState._border),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 10,
        spacing: 10,
        children: [
          const _CompactDetail(
            icon: Icons.mic_rounded,
            label: 'Everyone can speak',
          ),
          _CompactDetail(icon: Icons.translate_rounded, label: room.language),
          _CompactDetail(
            icon: Icons.lock_open_rounded,
            label: room.visibility.toUpperCase(),
          ),
        ],
      ),
    );
  }
}

class _CompactDetail extends StatelessWidget {
  const _CompactDetail({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFFC64BFF), size: 18),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
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
    final activityText = participantCount == 0
        ? 'Be the first voice here'
        : participantCount == 1
        ? '1 person is here now'
        : '$participantCount people are here now';

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        13,
        16,
        13 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF100B18),
        border: Border(top: BorderSide(color: Color(0xFF34243F))),
        boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 20)],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Conversation is live',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  activityText,
                  style: const TextStyle(
                    color: Color(0xFFA69CAF),
                    fontSize: 12,
                  ),
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
              foregroundColor: Colors.white,
              minimumSize: const Size(150, 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              elevation: 8,
              shadowColor: const Color(0x889D20FF),
            ),
          ),
        ],
      ),
    );
  }
}
