import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/data/models/room_message.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({required this.room, super.key});

  final VoiceRoom room;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  static const Color background = Color(0xFF080711);
  static const Color surface = Color(0xFF12101C);
  static const Color surface2 = Color(0xFF1B1627);
  static const Color border = Color(0xFF332943);
  static const Color muted = Color(0xFF9991A8);
  static const Color purple = Color(0xFF9D2BDE);
  static const Color pink = Color(0xFFFF416C);

  final RoomService _service = RoomService();

  bool _joining = true;
  bool _leaving = false;
  bool _speakerEnabled = true;
  bool _desktopChatVisible = true;

  String get _currentUserId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _ensureJoined();
  }

  Future<void> _ensureJoined() async {
    try {
      await _service.joinRoom(widget.room.id);
    } catch (error) {
      if (mounted) {
        _showError(_readableError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _joining = false);
      }
    }
  }

  Future<void> _leaveRoom(VoiceRoom room) async {
    if (_leaving) return;

    final isHost = room.hostId == _currentUserId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: surface,
        title: Text(
          isHost ? 'End room?' : 'Leave room?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          isHost
              ? 'The room will end for everyone.'
              : 'You can return while the room is still live.',
          style: const TextStyle(color: muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: pink),
            child: Text(isHost ? 'End room' : 'Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _leaving = true);

    try {
      if (isHost) {
        await _service.closeRoom(room.id);
      } else {
        await _service.leaveRoom(room.id);
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _leaving = false);
        _showError(_readableError(error));
      }
    }
  }

  Future<void> _toggleMute(RoomParticipant participant) async {
    if (!participant.isSpeaker) {
      _showError(
        'Raise your hand and wait for the host to invite you to speak.',
      );
      return;
    }

    try {
      await _service.setMuted(
        roomId: widget.room.id,
        isMuted: !participant.isMuted,
      );
    } catch (error) {
      _showError(_readableError(error));
    }
  }

  Future<void> _toggleHand(RoomParticipant participant) async {
    try {
      await _service.setHandRaised(
        roomId: widget.room.id,
        isRaised: !participant.isHandRaised,
      );
    } catch (error) {
      _showError(_readableError(error));
    }
  }

  Future<void> _showParticipantActions(
    VoiceRoom room,
    RoomParticipant participant,
  ) async {
    if (room.hostId != _currentUserId || participant.isHost) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: surface,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(
                participant.isSpeaker ? Icons.headphones : Icons.mic,
                color: Colors.white,
              ),
              title: Text(
                participant.isSpeaker
                    ? 'Move to listeners'
                    : 'Invite to speak',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(context, 'speaker'),
            ),
            if (participant.isSpeaker)
              ListTile(
                leading: Icon(
                  participant.isMuted ? Icons.mic : Icons.mic_off,
                  color: Colors.white,
                ),
                title: Text(
                  participant.isMuted
                      ? 'Allow microphone'
                      : 'Mute participant',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(context, 'mute'),
              ),
            ListTile(
              leading: const Icon(
                Icons.person_remove,
                color: Color(0xFFFF6B81),
              ),
              title: const Text(
                'Remove from room',
                style: TextStyle(color: Color(0xFFFF6B81)),
              ),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );

    try {
      if (action == 'speaker') {
        await _service.setSpeaker(
          roomId: room.id,
          participantId: participant.userId,
          isSpeaker: !participant.isSpeaker,
        );
      } else if (action == 'mute') {
        await _service.hostSetMuted(
          roomId: room.id,
          participantId: participant.userId,
          isMuted: !participant.isMuted,
        );
      } else if (action == 'remove') {
        await _service.removeParticipant(
          roomId: room.id,
          participantId: participant.userId,
        );
      }
    } catch (error) {
      _showError(_readableError(error));
    }
  }

  void _openMobileChat() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: .88,
        child: _RoomChatPanel(
          roomId: widget.room.id,
          service: _service,
          showCloseButton: true,
        ),
      ),
    );
  }

  String _readableError(Object error) {
    final text = error.toString();

    if (text.contains('permission-denied')) {
      return 'Firestore blocked this action. Check the room message rules.';
    }
    if (text.toLowerCase().contains('full')) {
      return 'This room is full.';
    }
    if (text.toLowerCase().contains('no longer live')) {
      return 'This room has ended.';
    }

    return text
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Invalid argument(s): ', '');
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF481C30),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VoiceRoom>(
      stream: _service.watchRoom(widget.room.id),
      initialData: widget.room,
      builder: (context, roomSnapshot) {
        final room = roomSnapshot.data ?? widget.room;

        if (!room.isLive && !_leaving) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          });
        }

        return StreamBuilder<List<RoomParticipant>>(
          stream: _service.watchParticipants(room.id),
          builder: (context, participantsSnapshot) {
            final participants =
                participantsSnapshot.data ?? const <RoomParticipant>[];
            final me = participants
                .where((participant) =>
                    participant.userId == _currentUserId)
                .firstOrNull;
            final speakers =
                participants.where((participant) => participant.isSpeaker).toList();
            final listeners =
                participants.where((participant) => !participant.isSpeaker).toList();

            return LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth >= 980;
                final showDesktopChat = desktop && _desktopChatVisible;

                return PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, result) {
                    if (!didPop) {
                      _leaveRoom(room);
                    }
                  },
                  child: Scaffold(
                    backgroundColor: background,
                    appBar: AppBar(
                      backgroundColor: const Color(0xFF080711),
                      surfaceTintColor: Colors.transparent,
                      leading: IconButton(
                        onPressed:
                            _leaving ? null : () => _leaveRoom(room),
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      title: const Text(
                        'Voice Room',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      centerTitle: true,
                      actions: [
                        if (desktop)
                          IconButton(
                            tooltip: showDesktopChat
                                ? 'Hide chat'
                                : 'Show chat',
                            onPressed: () {
                              setState(() {
                                _desktopChatVisible = !_desktopChatVisible;
                              });
                            },
                            icon: Icon(
                              showDesktopChat
                                  ? Icons.chat_bubble
                                  : Icons.chat_bubble_outline,
                              color: Colors.white,
                            ),
                          ),
                        const SizedBox(width: 8),
                      ],
                    ),
                    body: Container(
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(-.82, -.88),
                          radius: 1.35,
                          colors: [
                            Color(0xFF2E1145),
                            Color(0xFF120B1B),
                            background,
                          ],
                        ),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  flex: showDesktopChat ? 11 : 1,
                                  child: _RoomOverview(
                                    room: room,
                                    speakers: speakers,
                                    listeners: listeners,
                                    currentUserId: _currentUserId,
                                    onParticipantTap: (participant) =>
                                        _showParticipantActions(
                                      room,
                                      participant,
                                    ),
                                  ),
                                ),
                                if (showDesktopChat)
                                  SizedBox(
                                    width: constraints.maxWidth.clamp(400, 620) *
                                        .72,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        0,
                                        12,
                                        16,
                                        12,
                                      ),
                                      child: _RoomChatPanel(
                                        roomId: room.id,
                                        service: _service,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (_joining)
                            const LinearProgressIndicator(
                              minHeight: 2,
                              color: purple,
                            ),
                          _RoomControls(
                            participant: me,
                            speakerEnabled: _speakerEnabled,
                            leaving: _leaving,
                            desktop: desktop,
                            onMute:
                                me == null ? null : () => _toggleMute(me),
                            onHand:
                                me == null ? null : () => _toggleHand(me),
                            onAudio: () {
                              setState(() {
                                _speakerEnabled = !_speakerEnabled;
                              });
                            },
                            onChat: desktop
                                ? () {
                                    setState(() {
                                      _desktopChatVisible =
                                          !_desktopChatVisible;
                                    });
                                  }
                                : _openMobileChat,
                            onLeave: () => _leaveRoom(room),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _RoomOverview extends StatelessWidget {
  const _RoomOverview({
    required this.room,
    required this.speakers,
    required this.listeners,
    required this.currentUserId,
    required this.onParticipantTap,
  });

  final VoiceRoom room;
  final List<RoomParticipant> speakers;
  final List<RoomParticipant> listeners;
  final String currentUserId;
  final ValueChanged<RoomParticipant> onParticipantTap;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width;
    final contentWidth = maxWidth >= 980 ? 760.0 : double.infinity;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RoomHero(room: room),
              const SizedBox(height: 18),
              _RoomStats(
                stageCount: speakers.length,
                listenersCount: listeners.length,
                participantCount: speakers.length + listeners.length,
                maxParticipants: room.maxParticipants,
              ),
              const SizedBox(height: 22),
              _ParticipantSection(
                title: 'On stage',
                count: speakers.length,
                participants: speakers,
                emptyText: 'Nobody is on stage yet.',
                room: room,
                currentUserId: currentUserId,
                onTap: onParticipantTap,
              ),
              const SizedBox(height: 22),
              _ParticipantSection(
                title: 'Listeners',
                count: listeners.length,
                participants: listeners,
                emptyText: 'No listeners yet.',
                room: room,
                currentUserId: currentUserId,
                onTap: onParticipantTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomHero extends StatelessWidget {
  const _RoomHero({required this.room});

  final VoiceRoom room;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 112,
          height: 112,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF8735D6),
                Color(0xFF4D177B),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Text(
            room.name.isEmpty ? '?' : room.name[0].toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                room.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  const _InfoPill(
                    icon: Icons.circle,
                    label: 'LIVE',
                    accent: _RoomScreenState.pink,
                  ),
                  _InfoPill(
                    icon: Icons.people,
                    label:
                        '${room.participantCount}/${room.maxParticipants ?? '∞'}',
                    accent: _RoomScreenState.purple,
                  ),
                  _InfoPill(
                    icon: Icons.category_rounded,
                    label: room.category,
                  ),
                  _InfoPill(
                    icon: Icons.language_rounded,
                    label: room.language,
                  ),
                ],
              ),
              if (room.description.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  room.description,
                  style: const TextStyle(
                    color: _RoomScreenState.muted,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    this.accent = _RoomScreenState.muted,
  });

  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: _RoomScreenState.surface2,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _RoomScreenState.border),
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
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomStats extends StatelessWidget {
  const _RoomStats({
    required this.stageCount,
    required this.listenersCount,
    required this.participantCount,
    required this.maxParticipants,
  });

  final int stageCount;
  final int listenersCount;
  final int participantCount;
  final int? maxParticipants;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: _RoomScreenState.surface.withValues(alpha: .84),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _RoomScreenState.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatItem(
              icon: Icons.record_voice_over_rounded,
              value: '$stageCount',
              label: 'On stage',
              color: _RoomScreenState.pink,
            ),
          ),
          const _StatDivider(),
          Expanded(
            child: _StatItem(
              icon: Icons.groups_rounded,
              value: '$listenersCount',
              label: 'Listeners',
              color: _RoomScreenState.purple,
            ),
          ),
          const _StatDivider(),
          Expanded(
            child: _StatItem(
              icon: Icons.equalizer_rounded,
              value: '$participantCount/${maxParticipants ?? '∞'}',
              label: 'Capacity',
              color: Color(0xFF667BFF),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 44,
      color: _RoomScreenState.border,
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(width: 7),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: _RoomScreenState.muted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _ParticipantSection extends StatelessWidget {
  const _ParticipantSection({
    required this.title,
    required this.count,
    required this.participants,
    required this.emptyText,
    required this.room,
    required this.currentUserId,
    required this.onTap,
  });

  final String title;
  final int count;
  final List<RoomParticipant> participants;
  final String emptyText;
  final VoiceRoom room;
  final String currentUserId;
  final ValueChanged<RoomParticipant> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF411B5D),
                borderRadius: BorderRadius.circular(20),
              ),
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
        ),
        const SizedBox(height: 11),
        if (participants.isEmpty)
          Container(
            width: double.infinity,
            height: 108,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _RoomScreenState.surface.withValues(alpha: .8),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _RoomScreenState.border),
            ),
            child: Text(
              emptyText,
              style: const TextStyle(color: _RoomScreenState.muted),
            ),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: participants
                .map(
                  (participant) => SizedBox(
                    width: 230,
                    child: _ParticipantCard(
                      participant: participant,
                      canManage:
                          room.hostId == currentUserId && !participant.isHost,
                      onTap: () => onTap(participant),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}

class _ParticipantCard extends StatelessWidget {
  const _ParticipantCard({
    required this.participant,
    required this.canManage,
    required this.onTap,
  });

  final RoomParticipant participant;
  final bool canManage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canManage ? onTap : null,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: _RoomScreenState.surface.withValues(alpha: .88),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: participant.isHandRaised
                  ? const Color(0xFFFFB020)
                  : participant.isSpeaker && !participant.isMuted
                      ? _RoomScreenState.purple
                      : _RoomScreenState.border,
            ),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 27,
                    backgroundColor: const Color(0xFF662092),
                    backgroundImage:
                        participant.photoUrl?.trim().isNotEmpty == true
                            ? NetworkImage(participant.photoUrl!)
                            : null,
                    child: participant.photoUrl?.trim().isNotEmpty == true
                        ? null
                        : Text(
                            participant.displayName.isEmpty
                                ? '?'
                                : participant.displayName[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: _RoomScreenState.surface2,
                      child: Icon(
                        participant.isHandRaised
                            ? Icons.back_hand
                            : participant.isSpeaker
                                ? (participant.isMuted
                                    ? Icons.mic_off
                                    : Icons.mic)
                                : Icons.headphones,
                        size: 13,
                        color: participant.isHandRaised
                            ? const Color(0xFFFFB020)
                            : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      participant.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      participant.isHost
                          ? 'HOST'
                          : participant.isSpeaker
                              ? 'SPEAKER'
                              : participant.isHandRaised
                                  ? 'HAND RAISED'
                                  : 'LISTENER',
                      style: TextStyle(
                        color: participant.isHandRaised
                            ? const Color(0xFFFFB020)
                            : _RoomScreenState.pink,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (canManage)
                const Icon(
                  Icons.more_vert,
                  color: _RoomScreenState.muted,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomChatPanel extends StatefulWidget {
  const _RoomChatPanel({
    required this.roomId,
    required this.service,
    this.showCloseButton = false,
  });

  final String roomId;
  final RoomService service;
  final bool showCloseButton;

  @override
  State<_RoomChatPanel> createState() => _RoomChatPanelState();
}

class _RoomChatPanelState extends State<_RoomChatPanel> {
  static const List<String> reactions = ['❤️', '🔥', '😂', '👏', '🎉', '💜'];

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _sending = false;

  String get _currentUserId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);

    try {
      await widget.service.sendRoomMessage(
        roomId: widget.roomId,
        text: text,
      );
      _controller.clear();
      _focusNode.requestFocus();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _toggleReaction(
    RoomMessage message,
    String emoji,
  ) async {
    try {
      await widget.service.toggleMessageReaction(
        roomId: widget.roomId,
        messageId: message.id,
        emoji: emoji,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Future<void> _showReactionPicker(RoomMessage message) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _RoomScreenState.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: reactions
                .map(
                  (emoji) => InkWell(
                    onTap: () => Navigator.pop(context, emoji),
                    borderRadius: BorderRadius.circular(30),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 27),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );

    if (selected != null) {
      await _toggleReaction(message, selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _RoomScreenState.surface.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _RoomScreenState.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 10, 13),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Chat',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (widget.showCloseButton)
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: _RoomScreenState.border),
          Expanded(
            child: StreamBuilder<List<RoomMessage>>(
              stream: widget.service.watchRoomMessages(widget.roomId),
              builder: (context, snapshot) {
                final messages =
                    snapshot.data ?? const <RoomMessage>[];

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFFF8CA4)),
                      ),
                    ),
                  );
                }

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Start the conversation.',
                      style: TextStyle(color: _RoomScreenState.muted),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];

                    return _ChatMessage(
                      message: message,
                      currentUserId: _currentUserId,
                      onReaction: (emoji) =>
                          _toggleReaction(message, emoji),
                      onAddReaction: () =>
                          _showReactionPicker(message),
                    );
                  },
                );
              },
            ),
          ),
          _ChatComposer(
            controller: _controller,
            focusNode: _focusNode,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _ChatMessage extends StatelessWidget {
  const _ChatMessage({
    required this.message,
    required this.currentUserId,
    required this.onReaction,
    required this.onAddReaction,
  });

  final RoomMessage message;
  final String currentUserId;
  final ValueChanged<String> onReaction;
  final VoidCallback onAddReaction;

  @override
  Widget build(BuildContext context) {
    final time = message.createdAt;
    final timeLabel = time == null
        ? ''
        : '${time.hour.toString().padLeft(2, '0')}:'
            '${time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: const Color(0xFF6C27A1),
            backgroundImage: message.senderPhotoUrl?.trim().isNotEmpty == true
                ? NetworkImage(message.senderPhotoUrl!)
                : null,
            child: message.senderPhotoUrl?.trim().isNotEmpty == true
                ? null
                : Text(
                    message.senderName.isEmpty
                        ? '?'
                        : message.senderName[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        message.senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      timeLabel,
                      style: const TextStyle(
                        color: _RoomScreenState.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  message.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final entry in message.reactions.entries)
                      if (entry.value.isNotEmpty)
                        _ReactionChip(
                          emoji: entry.key,
                          count: entry.value.length,
                          selected: entry.value.contains(currentUserId),
                          onTap: () => onReaction(entry.key),
                        ),
                    _AddReactionButton(onTap: onAddReaction),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF3D1B55)
              : _RoomScreenState.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? _RoomScreenState.purple
                : _RoomScreenState.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddReactionButton extends StatelessWidget {
  const _AddReactionButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 31,
        height: 29,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _RoomScreenState.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _RoomScreenState.border),
        ),
        child: const Icon(
          Icons.add_reaction_outlined,
          size: 16,
          color: _RoomScreenState.muted,
        ),
      ),
    );
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: _RoomScreenState.border),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 4,
              maxLength: 500,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Type a message...',
                hintStyle: const TextStyle(
                  color: _RoomScreenState.muted,
                ),
                filled: true,
                fillColor: _RoomScreenState.surface2,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          IconButton.filled(
            onPressed: sending ? null : onSend,
            style: IconButton.styleFrom(
              backgroundColor: _RoomScreenState.purple,
              foregroundColor: Colors.white,
              minimumSize: const Size(48, 48),
            ),
            icon: sending
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}

class _RoomControls extends StatelessWidget {
  const _RoomControls({
    required this.participant,
    required this.speakerEnabled,
    required this.leaving,
    required this.desktop,
    required this.onMute,
    required this.onHand,
    required this.onAudio,
    required this.onChat,
    required this.onLeave,
  });

  final RoomParticipant? participant;
  final bool speakerEnabled;
  final bool leaving;
  final bool desktop;
  final VoidCallback? onMute;
  final VoidCallback? onHand;
  final VoidCallback onAudio;
  final VoidCallback onChat;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final muted = participant?.isMuted ?? true;
    final handRaised = participant?.isHandRaised ?? false;

    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xF8080711),
        border: Border(
          top: BorderSide(color: _RoomScreenState.border),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Row(
            children: [
              _ControlButton(
                icon: muted ? Icons.mic_off : Icons.mic,
                label: muted ? 'Unmute' : 'Mute',
                active: !muted,
                onTap: onMute,
              ),
              _ControlButton(
                icon: handRaised
                    ? Icons.back_hand
                    : Icons.back_hand_outlined,
                label: handRaised ? 'Lower' : 'Raise hand',
                active: handRaised,
                onTap: onHand,
              ),
              _ControlButton(
                icon: speakerEnabled
                    ? Icons.volume_up
                    : Icons.volume_off,
                label: 'Audio',
                active: speakerEnabled,
                onTap: onAudio,
              ),
              _ControlButton(
                icon: Icons.chat_bubble_rounded,
                label: 'Chat',
                onTap: onChat,
              ),
              _ControlButton(
                icon: Icons.call_end,
                label: 'Leave',
                danger: true,
                loading: leaving,
                onTap: leaving ? null : onLeave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.danger = false,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final bool danger;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: danger
                    ? _RoomScreenState.pink
                    : active
                        ? _RoomScreenState.purple
                        : _RoomScreenState.surface2,
                child: loading
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(icon, color: Colors.white, size: 21),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: danger
                      ? const Color(0xFFFF8CA4)
                      : Colors.white70,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
