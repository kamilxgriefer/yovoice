import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/data/models/room_message.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_settings_screen.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({required this.room, super.key});

  final VoiceRoom room;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

const _background = Color(0xFF080711);
const _surface = Color(0xFF151020);
const _border = Color(0xFF392B47);
const _muted = Color(0xFF9D95AD);
const _primary = Color(0xFFA226FF);
const _danger = Color(0xFFFF416C);

class _RoomScreenState extends State<RoomScreen> {

  final _service = RoomService();
  final _message = TextEditingController();

  bool _isMuted = false;
  bool _handRaised = false;
  bool _isLeaving = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send(String roomId) async {
    final text = _message.text.trim();
    if (text.isEmpty) return;

    _message.clear();
    await _service.sendRoomMessage(roomId: roomId, text: text);
  }

  Future<void> _leave(VoiceRoom room) async {
    if (_isLeaving) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: _surface,
            title: Text(
              room.isPersistent ? 'Leave voice chat?' : 'Leave room?',
              style: const TextStyle(color: Colors.white),
            ),
            content: Text(
              room.isPersistent
                  ? 'The community and chat history will stay available.'
                  : 'The temporary room will end if you are the host.',
              style: const TextStyle(color: _muted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    setState(() => _isLeaving = true);

    try {
      await _service.leaveRoom(room.id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLeaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VoiceRoom>(
      stream: _service.watchRoom(widget.room.id),
      initialData: widget.room,
      builder: (context, snapshot) {
        final room = snapshot.data ?? widget.room;

        return Scaffold(
          backgroundColor: _background,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;

                if (wide) {
                  return Row(
                    children: [
                      Expanded(
                        child: _RoomMain(
                          room: room,
                          service: _service,
                          uid: _uid,
                          isMuted: _isMuted,
                          handRaised: _handRaised,
                          onMute: () async {
                            final value = !_isMuted;
                            setState(() => _isMuted = value);
                            await _service.setMuted(
                              roomId: room.id,
                              isMuted: value,
                            );
                          },
                          onRaiseHand: () async {
                            final value = !_handRaised;
                            setState(() => _handRaised = value);
                            await _service.setHandRaised(
                              roomId: room.id,
                              isRaised: value,
                            );
                          },
                          onLeave: () => _leave(room),
                        ),
                      ),
                      SizedBox(
                        width: 430,
                        child: _ChatPanel(
                          room: room,
                          service: _service,
                          controller: _message,
                          onSend: () => _send(room.id),
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    Expanded(
                      child: _RoomMain(
                        room: room,
                        service: _service,
                        uid: _uid,
                        isMuted: _isMuted,
                        handRaised: _handRaised,
                        onMute: () async {
                          final value = !_isMuted;
                          setState(() => _isMuted = value);
                          await _service.setMuted(
                            roomId: room.id,
                            isMuted: value,
                          );
                        },
                        onRaiseHand: () async {
                          final value = !_handRaised;
                          setState(() => _handRaised = value);
                          await _service.setHandRaised(
                            roomId: room.id,
                            isRaised: value,
                          );
                        },
                        onLeave: () => _leave(room),
                        onOpenChat: () {
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            backgroundColor: _surface,
                            builder: (_) => FractionallySizedBox(
                              heightFactor: .88,
                              child: _ChatPanel(
                                room: room,
                                service: _service,
                                controller: _message,
                                onSend: () => _send(room.id),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _RoomMain extends StatelessWidget {
  const _RoomMain({
    required this.room,
    required this.service,
    required this.uid,
    required this.isMuted,
    required this.handRaised,
    required this.onMute,
    required this.onRaiseHand,
    required this.onLeave,
    this.onOpenChat,
  });

  final VoiceRoom room;
  final RoomService service;
  final String uid;
  final bool isMuted;
  final bool handRaised;
  final VoidCallback onMute;
  final VoidCallback onRaiseHand;
  final VoidCallback onLeave;
  final VoidCallback? onOpenChat;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TopBar(room: room, isOwner: room.hostId == uid),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
            children: [
              _Hero(room: room),
              const SizedBox(height: 22),
              StreamBuilder<List<RoomParticipant>>(
                stream: service.watchParticipants(room.id),
                builder: (context, snapshot) {
                  final participants =
                      snapshot.data ?? const <RoomParticipant>[];
                  final speakers =
                      participants.where((item) => item.isSpeaker).toList();
                  final listeners =
                      participants.where((item) => !item.isSpeaker).toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionTitle(
                        title: 'On stage',
                        count: speakers.length,
                      ),
                      const SizedBox(height: 12),
                      _PeopleGrid(people: speakers),
                      const SizedBox(height: 24),
                      _SectionTitle(
                        title: 'Listeners',
                        count: listeners.length,
                      ),
                      const SizedBox(height: 12),
                      listeners.isEmpty
                          ? const _EmptyPeople()
                          : _PeopleGrid(people: listeners),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        StreamBuilder<bool>(
          stream: service.watchIsParticipant(room.id),
          initialData: false,
          builder: (context, snapshot) {
            final isParticipant = snapshot.data ?? false;

            if (!room.isActive) {
              return _RoomUnavailableFooter(status: room.status);
            }

            if (!room.isLive) {
              return _OfflineVoiceFooter(
                isOwner: room.hostId == uid,
                onStart: () async {
                  try {
                    await service.startCommunityVoice(room.id);
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(error.toString())),
                    );
                  }
                },
                onChat: onOpenChat,
              );
            }

            if (!isParticipant) {
              return _JoinVoiceFooter(
                onJoin: () async {
                  try {
                    await service.joinRoom(room.id);
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(error.toString())),
                    );
                  }
                },
                onChat: onOpenChat,
              );
            }

            return _Controls(
              isMuted: isMuted,
              handRaised: handRaised,
              onMute: onMute,
              onRaiseHand: onRaiseHand,
              onChat: onOpenChat,
              onLeave: onLeave,
            );
          },
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.room, required this.isOwner});

  final VoiceRoom room;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF090612),
        border: Border(bottom: BorderSide(color: Color(0xFF21182D))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Minimize room',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          Expanded(
            child: Text(
              room.isPersistent ? 'Community Room' : 'Voice Room',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 19,
              ),
            ),
          ),
          if (isOwner)
            IconButton(
              tooltip: 'Room settings',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RoomSettingsScreen(room: room),
                  ),
                );
              },
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.room});

  final VoiceRoom room;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2C0F44),
            Color(0xFF171020),
            Color(0xFF0D0A14),
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF47295A)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;

          final image = _RoomImage(room: room, size: compact ? 108 : 128);
          final details = _RoomDetails(room: room);

          if (compact) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                image,
                const SizedBox(width: 16),
                Expanded(child: details),
              ],
            );
          }

          return Row(
            children: [
              image,
              const SizedBox(width: 22),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }
}

class _RoomImage extends StatelessWidget {
  const _RoomImage({required this.room, required this.size});

  final VoiceRoom room;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = room.imageUrl?.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFF7724B5),
        child: url != null && url.isNotEmpty
            ? Image.network(url, fit: BoxFit.cover)
            : Center(
                child: Text(
                  room.name.isEmpty ? '?' : room.name[0].toUpperCase(),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: size * .44,
                  ),
                ),
              ),
      ),
    );
  }
}

class _RoomDetails extends StatelessWidget {
  const _RoomDetails({required this.room});

  final VoiceRoom room;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          room.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 28,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Badge(
              label: room.isLive ? 'LIVE' : 'OFFLINE',
              icon: Icons.circle,
              accent: room.isLive
                  ? _danger
                  : const Color(0xFF8E849A),
            ),
            _Badge(
              label: room.isPersistent ? 'COMMUNITY' : 'TEMPORARY',
              icon: room.isPersistent
                  ? Icons.hub_rounded
                  : Icons.bolt_rounded,
            ),
            _Badge(
              label: room.language,
              icon: Icons.language_rounded,
            ),
          ],
        ),
        if (room.description.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            room.description,
            style: const TextStyle(
              color: Color(0xFFAAA1B6),
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          room.isPersistent
              ? '${room.memberCount} members • ${room.participantCount} in voice'
              : '${room.participantCount}/${room.maxParticipants ?? '∞'} joined',
          style: const TextStyle(
            color: Color(0xFFD0C7DA),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.icon,
    this.accent = const Color(0xFFA226FF),
  });

  final String label;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1527),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF483655)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 10),
        CircleAvatar(
          radius: 14,
          backgroundColor: const Color(0xFF54206F),
          child: Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _PeopleGrid extends StatelessWidget {
  const _PeopleGrid({required this.people});

  final List<RoomParticipant> people;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const _EmptyPeople();

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: people
          .map(
            (person) => Container(
              width: 180,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFF151020),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: person.isHost
                      ? const Color(0xFFA226FF)
                      : const Color(0xFF392B47),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: const Color(0xFF7526B4),
                    backgroundImage: person.photoUrl?.trim().isNotEmpty == true
                        ? NetworkImage(person.photoUrl!)
                        : null,
                    child: person.photoUrl?.trim().isNotEmpty == true
                        ? null
                        : Text(
                            person.displayName.isEmpty
                                ? '?'
                                : person.displayName[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          person.isHost
                              ? 'HOST'
                              : person.isSpeaker
                                  ? 'SPEAKER'
                                  : 'LISTENER',
                          style: TextStyle(
                            color: person.isHost
                                ? _danger
                                : const Color(0xFF9D95AD),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    person.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    color: person.isMuted
                        ? const Color(0xFF887E93)
                        : const Color(0xFFC65BFF),
                    size: 18,
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _EmptyPeople extends StatelessWidget {
  const _EmptyPeople();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF12101B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: const Text(
        'Nobody here yet.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF9D95AD)),
      ),
    );
  }
}

class _OfflineVoiceFooter extends StatelessWidget {
  const _OfflineVoiceFooter({
    required this.isOwner,
    required this.onStart,
    required this.onChat,
  });

  final bool isOwner;
  final VoidCallback onStart;
  final VoidCallback? onChat;

  @override
  Widget build(BuildContext context) {
    return _FooterShell(
      child: Row(
        children: [
          Expanded(
            child: Text(
              isOwner
                  ? 'Your community is online. Start voice whenever you are ready.'
                  : 'This community is available, but voice is currently offline.',
              style: const TextStyle(color: _muted, height: 1.35),
            ),
          ),
          if (onChat != null) ...[
            const SizedBox(width: 10),
            IconButton.filledTonal(
              onPressed: onChat,
              icon: const Icon(Icons.chat_bubble_rounded),
            ),
          ],
          if (isOwner) ...[
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.mic_rounded),
              label: const Text('Start voice'),
              style: FilledButton.styleFrom(backgroundColor: _primary),
            ),
          ],
        ],
      ),
    );
  }
}

class _JoinVoiceFooter extends StatelessWidget {
  const _JoinVoiceFooter({required this.onJoin, required this.onChat});

  final VoidCallback onJoin;
  final VoidCallback? onChat;

  @override
  Widget build(BuildContext context) {
    return _FooterShell(
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'A voice session is live now.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
          if (onChat != null)
            IconButton.filledTonal(
              onPressed: onChat,
              icon: const Icon(Icons.chat_bubble_rounded),
            ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: onJoin,
            icon: const Icon(Icons.login_rounded),
            label: const Text('Join voice'),
            style: FilledButton.styleFrom(backgroundColor: _primary),
          ),
        ],
      ),
    );
  }
}

class _RoomUnavailableFooter extends StatelessWidget {
  const _RoomUnavailableFooter({required this.status});

  final RoomStatus status;

  @override
  Widget build(BuildContext context) {
    return _FooterShell(
      child: Row(
        children: [
          const Icon(Icons.lock_rounded, color: _danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              status == RoomStatus.archived
                  ? 'This room is archived.'
                  : 'This room is currently closed.',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterShell extends StatelessWidget {
  const _FooterShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        14 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF090612),
        border: Border(top: BorderSide(color: _border)),
      ),
      child: child,
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.isMuted,
    required this.handRaised,
    required this.onMute,
    required this.onRaiseHand,
    required this.onChat,
    required this.onLeave,
  });

  final bool isMuted;
  final bool handRaised;
  final VoidCallback onMute;
  final VoidCallback onRaiseHand;
  final VoidCallback? onChat;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF090612),
        border: Border(top: BorderSide(color: Color(0xFF392B47))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Control(
            icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: isMuted ? 'Unmute' : 'Mute',
            active: !isMuted,
            onTap: onMute,
          ),
          _Control(
            icon: handRaised
                ? Icons.pan_tool_rounded
                : Icons.pan_tool_outlined,
            label: handRaised ? 'Lower hand' : 'Raise hand',
            active: handRaised,
            onTap: onRaiseHand,
          ),
          if (onChat != null)
            _Control(
              icon: Icons.chat_bubble_rounded,
              label: 'Chat',
              active: false,
              onTap: onChat!,
            ),
          _Control(
            icon: Icons.call_end_rounded,
            label: 'Leave',
            active: true,
            danger: true,
            onTap: onLeave,
          ),
        ],
      ),
    );
  }
}

class _Control extends StatelessWidget {
  const _Control({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? _danger
        : active
            ? const Color(0xFFA226FF)
            : const Color(0xFF1C1627);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 27,
              backgroundColor: color,
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: danger
                    ? const Color(0xFFFF7795)
                    : const Color(0xFFB7AFC0),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.room,
    required this.service,
    required this.controller,
    required this.onSend,
  });

  final VoiceRoom room;
  final RoomService service;
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF100D18),
        border: Border(left: BorderSide(color: Color(0xFF392B47))),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Chat',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFF392B47)),
          Expanded(
            child: StreamBuilder<List<RoomMessage>>(
              stream: service.watchRoomMessages(room.id),
              builder: (context, snapshot) {
                final messages =
                    snapshot.data ?? const <RoomMessage>[];

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Start the conversation.',
                      style: TextStyle(color: Color(0xFF9D95AD)),
                    ),
                  );
                }

                return ListView.separated(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final message = messages[index];

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: const Color(0xFF7526B4),
                          child: Text(
                            message.senderName.isEmpty
                                ? '?'
                                : message.senderName[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message.senderName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                message.text,
                                style: const TextStyle(
                                  color: Color(0xFFD4CDD9),
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              14,
              12,
              14,
              12 + MediaQuery.paddingOf(context).bottom,
            ),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF392B47))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    maxLength: 500,
                    maxLines: 4,
                    minLines: 1,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Type a message...',
                      hintStyle: const TextStyle(
                        color: Color(0xFF81778B),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF1A1424),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Color(0xFF392B47),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: onSend,
                  style: IconButton.styleFrom(
                    backgroundColor: _primary,
                  ),
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
