import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/calls/presentation/screens/voice_call_screen.dart';
import 'package:yovoice/features/rooms/data/models/room_message.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_experience_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

class PodcastRoomScreen extends StatefulWidget {
  const PodcastRoomScreen({required this.room, super.key});
  final VoiceRoom room;

  @override
  State<PodcastRoomScreen> createState() => _PodcastRoomScreenState();
}

class _PodcastRoomScreenState extends State<PodcastRoomScreen> {
  static const _background = Color(0xFF080711);
  static const _surface = Color(0xFF171121);
  static const _border = Color(0xFF3A2C49);
  static const _accent = Color(0xFFFF3F8E);
  static const _muted = Color(0xFFA69CAF);

  final _rooms = RoomService();
  final _experience = RoomExperienceService();
  final _message = TextEditingController();

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _isHost => widget.room.hostId == _uid;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _joinVoice() async {
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
    }
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    _message.clear();
    await _rooms.sendRoomMessage(roomId: widget.room.id, text: text);
  }

  void _openChat() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _surface,
      builder: (_) => FractionallySizedBox(
        heightFactor: .82,
        child: _PodcastChat(
          roomId: widget.room.id,
          service: _rooms,
          controller: _message,
          onSend: _send,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        title: Column(
          children: [
            Text(widget.room.name, style: const TextStyle(fontWeight: FontWeight.w900)),
            const Text(
              'PODCAST ROOM',
              style: TextStyle(color: _accent, fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(onPressed: _openChat, icon: const Icon(Icons.chat_bubble_rounded)),
        ],
      ),
      body: StreamBuilder<List<RoomParticipant>>(
        stream: _rooms.watchParticipants(widget.room.id),
        builder: (context, snapshot) {
          final people = snapshot.data ?? const <RoomParticipant>[];
          final stage = people.where((person) => person.isSpeaker).toList();
          final audience = people.where((person) => !person.isSpeaker).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 130),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF331025), Color(0xFF171121)],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFF64304A)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.podcasts_rounded, color: _accent, size: 42),
                    const SizedBox(height: 12),
                    Text(
                      widget.room.description.isEmpty
                          ? 'Live hosted conversation'
                          : widget.room.description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${stage.length} on stage • ${audience.length} listening',
                      style: const TextStyle(color: _muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _Title('On stage', stage.length),
              const SizedBox(height: 12),
              _People(people: stage, accent: _accent),
              const SizedBox(height: 24),
              if (_isHost) ...[
                _Title('Raised hands', 0),
                const SizedBox(height: 12),
                StreamBuilder<List<PodcastHandRequest>>(
                  stream: _experience.watchRaisedHands(widget.room.id),
                  builder: (context, handsSnapshot) {
                    final hands = handsSnapshot.data ?? const <PodcastHandRequest>[];
                    if (hands.isEmpty) {
                      return const _Empty(text: 'No one is waiting to speak.');
                    }
                    return Column(
                      children: hands
                          .map(
                            (request) => ListTile(
                              tileColor: _surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: const BorderSide(color: _border),
                              ),
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFF70204A),
                                child: Text(request.displayName.substring(0, 1).toUpperCase()),
                              ),
                              title: Text(request.displayName, style: const TextStyle(color: Colors.white)),
                              trailing: FilledButton(
                                onPressed: () => _experience.inviteToStage(
                                  roomId: widget.room.id,
                                  request: request,
                                ),
                                style: FilledButton.styleFrom(backgroundColor: _accent),
                                child: const Text('Invite'),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],
              _Title('Audience', audience.length),
              const SizedBox(height: 12),
              audience.isEmpty
                  ? const _Empty(text: 'The audience is waiting.')
                  : _People(people: audience, accent: const Color(0xFFA226FF)),
            ],
          );
        },
      ),
      bottomNavigationBar: StreamBuilder<bool>(
        stream: _experience.watchMyHandRaised(widget.room.id),
        initialData: false,
        builder: (context, snapshot) {
          final raised = snapshot.data ?? false;
          return Container(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.paddingOf(context).bottom),
            decoration: const BoxDecoration(
              color: Color(0xFF100B18),
              border: Border(top: BorderSide(color: _border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _joinVoice,
                    icon: const Icon(Icons.headphones_rounded),
                    label: const Text('Join audience'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      minimumSize: const Size.fromHeight(54),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (!_isHost)
                  IconButton.filledTonal(
                    tooltip: raised ? 'Lower hand' : 'Raise hand',
                    onPressed: () => _experience.setHandRaised(
                      roomId: widget.room.id,
                      raised: !raised,
                    ),
                    icon: Icon(
                      raised ? Icons.pan_tool_rounded : Icons.pan_tool_outlined,
                    ),
                  ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: 'Chat',
                  onPressed: _openChat,
                  icon: const Icon(Icons.chat_bubble_rounded),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text, this.count);
  final String text;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(width: 8),
        CircleAvatar(
          radius: 13,
          backgroundColor: const Color(0xFF51204A),
          child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11)),
        ),
      ],
    );
  }
}

class _People extends StatelessWidget {
  const _People({required this.people, required this.accent});
  final List<RoomParticipant> people;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const _Empty(text: 'Nobody here yet.');
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: people
          .map(
            (person) => SizedBox(
              width: 104,
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: accent.withValues(alpha: .25),
                    backgroundImage: person.photoUrl?.isNotEmpty == true
                        ? NetworkImage(person.photoUrl!)
                        : null,
                    child: person.photoUrl?.isNotEmpty == true
                        ? null
                        : Text(
                            person.displayName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                          ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    person.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    person.isHost ? 'HOST' : person.isSpeaker ? 'SPEAKER' : 'LISTENER',
                    style: TextStyle(color: person.isHost ? _PodcastRoomScreenState._accent : _PodcastRoomScreenState._muted, fontSize: 9),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF171121),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF3A2C49)),
        ),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFA69CAF))),
      );
}

class _PodcastChat extends StatelessWidget {
  const _PodcastChat({
    required this.roomId,
    required this.service,
    required this.controller,
    required this.onSend,
  });
  final String roomId;
  final RoomService service;
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(18),
          child: Text('Live chat', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
        ),
        Expanded(
          child: StreamBuilder<List<RoomMessage>>(
            stream: service.watchRoomMessages(roomId),
            builder: (context, snapshot) {
              final messages = snapshot.data ?? const <RoomMessage>[];
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  return ListTile(
                    title: Text(message.senderName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    subtitle: Text(message.text, style: const TextStyle(color: Color(0xFFD5CEDC))),
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(14, 10, 14, 10 + MediaQuery.paddingOf(context).bottom),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Message the room...',
                    filled: true,
                    fillColor: Color(0xFF21172D),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              IconButton(onPressed: onSend, icon: const Icon(Icons.send_rounded, color: Color(0xFFFF3F8E))),
            ],
          ),
        ),
      ],
    );
  }
}
