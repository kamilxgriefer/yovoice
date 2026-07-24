import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/features/calls/presentation/screens/podcast_voice_call_screen.dart';
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

class _PodcastRoomScreenState extends State<PodcastRoomScreen>
    with SingleTickerProviderStateMixin {
  static const _background = Color(0xFF080711);
  static const _surface = Color(0xFF171121);
  static const _border = Color(0xFF3A2C49);
  static const _accent = Color(0xFFFF3F8E);
  static const _muted = Color(0xFFA69CAF);

  final RoomService _rooms = RoomService();
  final RoomExperienceService _experience = RoomExperienceService();
  final TextEditingController _message = TextEditingController();

  late final AnimationController _handPulse;
  bool _joining = false;
  bool _closing = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _isHost => widget.room.hostId == _uid;

  @override
  void initState() {
    super.initState();
    _handPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _handPulse.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _joinVoice() async {
    if (_joining) {
      return;
    }
    setState(() => _joining = true);

    try {
      await _rooms.joinRoom(widget.room.id);
      if (!mounted) {
        return;
      }
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
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _joining = false);
      }
    }
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty) {
      return;
    }
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
        heightFactor: .90,
        child: _PodcastChat(
          roomId: widget.room.id,
          service: _rooms,
          controller: _message,
          onSend: _send,
        ),
      ),
    );
  }

  Future<void> _shareRoom() async {
    final uri = Uri.https('yovoice.app', '/', {'room': widget.room.id});
    await SharePlus.instance.share(
      ShareParams(
        title: 'Join ${widget.room.name} on YoVoice',
        subject: 'YoVoice podcast invitation',
        text: 'Join the podcast "${widget.room.name}" on YoVoice.\n\n$uri',
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
            'End this podcast?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'The live podcast will end for everyone and disappear from Home and Discover.',
            style: TextStyle(color: _muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: _accent),
              child: const Text('End podcast'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || _closing) {
      return;
    }

    setState(() => _closing = true);
    try {
      await _rooms.setRoomStatus(widget.room.id, RoomStatus.closed);
      if (!mounted) {
        return;
      }
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _closing = false);
      }
    }
  }

  void _openHostTools() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: _surface,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Host controls',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded, color: _accent),
              title: const Text(
                'Share podcast',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: const Text(
                'Invite people with a direct YoVoice link.',
                style: TextStyle(color: _muted),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _shareRoom();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.person_add_alt_1_rounded,
                color: _accent,
              ),
              title: const Text(
                'Invite a speaker',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: const Text(
                'Choose someone from raised hands.',
                style: TextStyle(color: _muted),
              ),
              onTap: () => Navigator.of(context).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.pan_tool_rounded, color: _accent),
              title: const Text(
                'Manage raised hands',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: const Text(
                'Requests are shown directly in the room.',
                style: TextStyle(color: _muted),
              ),
              onTap: () => Navigator.of(context).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.settings_voice_rounded, color: _accent),
              title: const Text(
                'Stage management',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: const Text(
                'Move speakers back to the audience.',
                style: TextStyle(color: _muted),
              ),
              onTap: () => Navigator.of(context).pop(),
            ),
            const Divider(color: _border),
            ListTile(
              leading: const Icon(
                Icons.stop_circle_rounded,
                color: Color(0xFFFF416C),
              ),
              title: const Text(
                'End podcast',
                style: TextStyle(
                  color: Color(0xFFFF7895),
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: const Text(
                'Close the live room for everyone.',
                style: TextStyle(color: _muted),
              ),
              onTap: _closing
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      _closeRoom();
                    },
            ),
          ],
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
            Text(
              widget.room.name,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const Text(
              'PODCAST ROOM',
              style: TextStyle(
                color: _accent,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          if (_isHost)
            IconButton(
              onPressed: _openHostTools,
              tooltip: 'Host controls',
              icon: const Icon(Icons.tune_rounded),
            ),
        ],
      ),
      body: StreamBuilder<List<RoomParticipant>>(
        stream: _rooms.watchParticipants(widget.room.id),
        builder: (context, snapshot) {
          final people = snapshot.data ?? const <RoomParticipant>[];
          final stage = people.where((person) => person.isSpeaker).toList();
          final audience = people.where((person) => !person.isSpeaker).toList();
          final host = stage
              .where((person) => person.userId == widget.room.hostId)
              .firstOrNull;
          final speakers = stage
              .where((person) => person.userId != widget.room.hostId)
              .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 130),
            children: [
              _PodcastHero(
                room: widget.room,
                host: host,
                onStageCount: stage.length,
                audienceCount: audience.length,
              ),
              const SizedBox(height: 24),
              _Title('Speakers on stage', speakers.length),
              const SizedBox(height: 12),
              speakers.isEmpty
                  ? const _Empty(
                      text:
                          'The host is ready. Invited speakers will appear here.',
                    )
                  : _People(people: speakers, accent: _accent),
              const SizedBox(height: 24),
              if (_isHost) ...[
                StreamBuilder<List<PodcastHandRequest>>(
                  stream: _experience.watchRaisedHands(widget.room.id),
                  builder: (context, handsSnapshot) {
                    final hands =
                        handsSnapshot.data ?? const <PodcastHandRequest>[];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Title('Raised hands', hands.length),
                        const SizedBox(height: 12),
                        if (hands.isEmpty)
                          const _Empty(text: 'No one is waiting to speak.')
                        else
                          ...hands.map(
                            (request) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _RaisedHandTile(
                                request: request,
                                pulse: _handPulse,
                                onInvite: () => _experience.inviteToStage(
                                  roomId: widget.room.id,
                                  request: request,
                                ),
                              ),
                            ),
                          ),
                      ],
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
            padding: EdgeInsets.fromLTRB(
              12,
              12,
              12,
              12 + MediaQuery.paddingOf(context).bottom,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF100B18),
              border: Border(top: BorderSide(color: _border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _joining ? null : _joinVoice,
                    icon: _joining
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _isHost
                                ? Icons.podcasts_rounded
                                : Icons.headphones_rounded,
                          ),
                    label: Text(
                      _joining
                          ? 'Joining…'
                          : _isHost
                          ? 'Start hosting'
                          : 'Join audience',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      minimumSize: const Size.fromHeight(54),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (!_isHost)
                  _PulsingHandButton(
                    raised: raised,
                    pulse: _handPulse,
                    onPressed: () => _experience.setHandRaised(
                      roomId: widget.room.id,
                      raised: !raised,
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Chat',
                  onPressed: _openChat,
                  style: IconButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                  ),
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

class _PodcastHero extends StatelessWidget {
  const _PodcastHero({
    required this.room,
    required this.host,
    required this.onStageCount,
    required this.audienceCount,
  });

  final VoiceRoom room;
  final RoomParticipant? host;
  final int onStageCount;
  final int audienceCount;

  @override
  Widget build(BuildContext context) {
    final hostName = host?.displayName ?? room.hostName;
    final initial = hostName.trim().isEmpty
        ? 'H'
        : hostName.trim()[0].toUpperCase();

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF351225), Color(0xFF171121)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF6B304D)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.podcasts_rounded,
            color: _PodcastRoomScreenState._accent,
            size: 38,
          ),
          const SizedBox(height: 12),
          Container(
            width: 112,
            height: 112,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Color(0xFFFF5AA3),
                  Color(0xFF701944),
                  Color(0xFF280B1C),
                ],
              ),
              boxShadow: [BoxShadow(color: Color(0x66FF3F8E), blurRadius: 28)],
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 44,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hostName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Text(
            'HOST',
            style: TextStyle(
              color: _PodcastRoomScreenState._accent,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 15),
          Text(
            room.description.isEmpty
                ? 'Live hosted conversation'
                : room.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$onStageCount on stage • $audienceCount listening',
            style: const TextStyle(color: _PodcastRoomScreenState._muted),
          ),
        ],
      ),
    );
  }
}

class _RaisedHandTile extends StatelessWidget {
  const _RaisedHandTile({
    required this.request,
    required this.pulse,
    required this.onInvite,
  });

  final PodcastHandRequest request;
  final Animation<double> pulse;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _PodcastRoomScreenState._surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _PodcastRoomScreenState._accent.withValues(
                alpha: .45 + pulse.value * .5,
              ),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _PodcastRoomScreenState._accent.withValues(
                  alpha: .08 + pulse.value * .18,
                ),
                blurRadius: 20,
                spreadRadius: pulse.value * 3,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF70204A),
            child: Text(
              request.displayName.trim().isEmpty
                  ? '?'
                  : request.displayName.trim()[0].toUpperCase(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              request.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const Icon(
            Icons.pan_tool_rounded,
            color: _PodcastRoomScreenState._accent,
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onInvite,
            style: FilledButton.styleFrom(
              backgroundColor: _PodcastRoomScreenState._accent,
            ),
            child: const Text('Invite'),
          ),
        ],
      ),
    );
  }
}

class _PulsingHandButton extends StatelessWidget {
  const _PulsingHandButton({
    required this.raised,
    required this.pulse,
    required this.onPressed,
  });

  final bool raised;
  final Animation<double> pulse;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: raised
                ? [
                    BoxShadow(
                      color: _PodcastRoomScreenState._accent.withValues(
                        alpha: .2 + pulse.value * .4,
                      ),
                      blurRadius: 18 + pulse.value * 12,
                      spreadRadius: pulse.value * 3,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: IconButton.filledTonal(
        tooltip: raised ? 'Lower hand' : 'Raise hand',
        onPressed: onPressed,
        icon: Icon(
          raised ? Icons.pan_tool_rounded : Icons.pan_tool_outlined,
          color: raised ? _PodcastRoomScreenState._accent : null,
        ),
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
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 8),
        CircleAvatar(
          radius: 13,
          backgroundColor: const Color(0xFF70204A),
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

class _People extends StatelessWidget {
  const _People({required this.people, required this.accent});

  final List<RoomParticipant> people;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: people
          .map((person) {
            final initial = person.displayName.trim().isEmpty
                ? '?'
                : person.displayName.trim()[0].toUpperCase();
            return Container(
              width: 132,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _PodcastRoomScreenState._surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: accent.withValues(alpha: .55)),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 29,
                    backgroundColor: accent.withValues(alpha: .45),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    person.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    person.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    size: 16,
                    color: person.isMuted
                        ? _PodcastRoomScreenState._muted
                        : accent,
                  ),
                ],
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _PodcastRoomScreenState._surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _PodcastRoomScreenState._border),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: _PodcastRoomScreenState._muted),
      ),
    );
  }
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
          child: Row(
            children: [
              Icon(
                Icons.chat_bubble_rounded,
                color: _PodcastRoomScreenState._accent,
              ),
              SizedBox(width: 10),
              Text(
                'Podcast chat',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: _PodcastRoomScreenState._border),
        Expanded(
          child: StreamBuilder<List<RoomMessage>>(
            stream: service.watchRoomMessages(roomId),
            builder: (context, snapshot) {
              final messages = snapshot.data ?? const <RoomMessage>[];
              if (messages.isEmpty) {
                return const Center(
                  child: Text(
                    'No messages yet.',
                    style: TextStyle(color: _PodcastRoomScreenState._muted),
                  ),
                );
              }
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(14),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  return ListTile(
                    title: Text(
                      message.senderName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      message.text,
                      style: const TextStyle(color: Color(0xFFD4CBDC)),
                    ),
                  );
                },
              );
            },
          ),
        ),
        AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(
            14,
            12,
            14,
            14 +
                MediaQuery.viewInsetsOf(context).bottom +
                MediaQuery.paddingOf(context).bottom,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Write a message…',
                    filled: true,
                    fillColor: const Color(0xFF21172D),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: _border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: _accent, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: onSend,
                style: IconButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(52, 52),
                ),
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
