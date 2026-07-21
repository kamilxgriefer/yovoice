import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/room_reaction.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({required this.room, super.key});
  final VoiceRoom room;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  static const _background = Color(0xFF080711);
  static const _surface = Color(0xFF151020);
  static const _surface2 = Color(0xFF21172D);
  static const _border = Color(0xFF392B47);
  static const _muted = Color(0xFF9D95AD);
  static const _purple = Color(0xFFAE35FF);

  final _service = RoomService();
  bool _joining = true;
  bool _leaving = false;
  bool _speakerEnabled = true;

  String get _me => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _ensureJoined();
  }

  Future<void> _ensureJoined() async {
    try {
      await _service.joinRoom(widget.room.id);
    } catch (error) {
      if (mounted) _showError(_readable(error));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _leave(VoiceRoom room) async {
    if (_leaving) return;
    final host = room.hostId == _me;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        title: Text(host ? 'End room?' : 'Leave room?',
            style: const TextStyle(color: Colors.white)),
        content: Text(
          host
              ? 'The room will end for everyone.'
              : 'You can come back while the room is live.',
          style: const TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF416C)),
            child: Text(host ? 'End room' : 'Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _leaving = true);
    try {
      if (host) {
        await _service.closeRoom(room.id);
      } else {
        await _service.leaveRoom(room.id);
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() => _leaving = false);
        _showError(_readable(error));
      }
    }
  }

  Future<void> _toggleMute(RoomParticipant me) async {
    if (!me.isSpeaker) {
      _showError('Raise your hand and wait for the host to invite you to speak.');
      return;
    }
    try {
      await _service.setMuted(roomId: widget.room.id, isMuted: !me.isMuted);
    } catch (error) {
      _showError(_readable(error));
    }
  }

  Future<void> _toggleHand(RoomParticipant me) async {
    try {
      await _service.setHandRaised(
        roomId: widget.room.id,
        isRaised: !me.isHandRaised,
      );
    } catch (error) {
      _showError(_readable(error));
    }
  }

  Future<void> _participantActions(
    VoiceRoom room,
    RoomParticipant participant,
  ) async {
    if (room.hostId != _me || participant.isHost) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _surface,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: Icon(
              participant.isSpeaker ? Icons.headphones : Icons.mic,
              color: Colors.white,
            ),
            title: Text(
              participant.isSpeaker ? 'Move to listeners' : 'Invite to speak',
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
                participant.isMuted ? 'Allow microphone' : 'Mute participant',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(context, 'mute'),
            ),
          ListTile(
            leading: const Icon(Icons.person_remove, color: Color(0xFFFF6B81)),
            title: const Text('Remove from room',
                style: TextStyle(color: Color(0xFFFF6B81))),
            onTap: () => Navigator.pop(context, 'remove'),
          ),
        ]),
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
      _showError(_readable(error));
    }
  }

  void _showReactions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['👏', '❤️', '😂', '🔥', '🎉', '💜']
                .map((emoji) => InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _service.sendReaction(
                          roomId: widget.room.id,
                          emoji: emoji,
                        );
                      },
                      borderRadius: BorderRadius.circular(30),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(emoji,
                            style: const TextStyle(fontSize: 29)),
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  String _readable(Object error) {
    final text = error.toString();
    if (text.contains('permission-denied')) {
      return 'Firestore blocked this action. The final rules still need to be deployed.';
    }
    if (text.contains('full')) return 'This room is full.';
    if (text.contains('no longer live')) return 'This room has ended.';
    return text.replaceFirst('Bad state: ', '').replaceFirst('Invalid argument(s): ', '');
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF481C30),
      ));
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
            if (mounted && Navigator.canPop(context)) Navigator.pop(context);
          });
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _leave(room);
          },
          child: Scaffold(
            backgroundColor: _background,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                onPressed: _leaving ? null : () => _leave(room),
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Colors.white, size: 30),
              ),
              title: const Text('Voice Room',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
              centerTitle: true,
            ),
            body: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.8, -0.9),
                  radius: 1.3,
                  colors: [Color(0xFF33134D), Color(0xFF130C1D), _background],
                ),
              ),
              child: StreamBuilder<List<RoomParticipant>>(
                stream: _service.watchParticipants(room.id),
                builder: (context, participantSnapshot) {
                  final participants = participantSnapshot.data ?? const [];
                  final me = participants.where((p) => p.userId == _me).firstOrNull;

                  return Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _Pill(
                                  icon: Icons.circle,
                                  label: room.isLive ? 'LIVE' : 'ENDED',
                                  danger: room.isLive,
                                ),
                                const SizedBox(width: 8),
                                _Pill(
                                  icon: Icons.people,
                                  label: '${participants.length}/${room.maxParticipants ?? '∞'}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              room.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 27,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (room.description.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(room.description,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: _muted, height: 1.4)),
                            ],
                            const SizedBox(height: 22),
                            _ReactionStrip(
                              stream: _service.watchRecentReactions(room.id),
                            ),
                            const SizedBox(height: 20),
                            _SectionTitle(
                              title: 'On stage',
                              count: participants.where((p) => p.isSpeaker).length,
                            ),
                            const SizedBox(height: 12),
                            _ParticipantGrid(
                              room: room,
                              participants:
                                  participants.where((p) => p.isSpeaker).toList(),
                              currentUserId: _me,
                              onTap: (p) => _participantActions(room, p),
                            ),
                            const SizedBox(height: 26),
                            _SectionTitle(
                              title: 'Listeners',
                              count: participants.where((p) => !p.isSpeaker).length,
                            ),
                            const SizedBox(height: 12),
                            _ParticipantGrid(
                              room: room,
                              participants:
                                  participants.where((p) => !p.isSpeaker).toList(),
                              currentUserId: _me,
                              onTap: (p) => _participantActions(room, p),
                            ),
                          ],
                        ),
                      ),
                      if (_joining)
                        const LinearProgressIndicator(color: _purple, minHeight: 2),
                      _Controls(
                        participant: me,
                        speakerEnabled: _speakerEnabled,
                        leaving: _leaving,
                        onMute: me == null ? null : () => _toggleMute(me),
                        onHand: me == null ? null : () => _toggleHand(me),
                        onSpeaker: () =>
                            setState(() => _speakerEnabled = !_speakerEnabled),
                        onReaction: _showReactions,
                        onLeave: () => _leave(room),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, this.danger = false});
  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: danger ? const Color(0xFF441426) : _RoomScreenState._surface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
              color: danger ? const Color(0xFFFF416C) : _RoomScreenState._border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 11,
              color: danger ? const Color(0xFFFF416C) : _RoomScreenState._purple),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900)),
        ]),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(title,
            style: const TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
        const Spacer(),
        Text('$count', style: const TextStyle(color: _RoomScreenState._muted)),
      ]);
}

class _ParticipantGrid extends StatelessWidget {
  const _ParticipantGrid({
    required this.room,
    required this.participants,
    required this.currentUserId,
    required this.onTap,
  });
  final VoiceRoom room;
  final List<RoomParticipant> participants;
  final String currentUserId;
  final ValueChanged<RoomParticipant> onTap;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _RoomScreenState._surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _RoomScreenState._border),
        ),
        child: const Text('Nobody here yet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _RoomScreenState._muted)),
      );
    }

    return GridView.builder(
      itemCount: participants.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: .78,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final p = participants[index];
        return InkWell(
          onTap: room.hostId == currentUserId && !p.isHost ? () => onTap(p) : null,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _RoomScreenState._surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: p.isHandRaised
                    ? const Color(0xFFFFB020)
                    : p.isSpeaker && !p.isMuted
                        ? _RoomScreenState._purple
                        : _RoomScreenState._border,
              ),
            ),
            child: Column(children: [
              Stack(children: [
                CircleAvatar(
                  radius: 31,
                  backgroundColor: const Color(0xFF662092),
                  backgroundImage:
                      p.photoUrl?.trim().isNotEmpty == true ? NetworkImage(p.photoUrl!) : null,
                  child: p.photoUrl?.trim().isNotEmpty == true
                      ? null
                      : Text(
                          p.displayName.isEmpty ? '?' : p.displayName[0].toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900),
                        ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: _RoomScreenState._surface2,
                    child: Icon(
                      p.isHandRaised
                          ? Icons.back_hand
                          : p.isSpeaker
                              ? (p.isMuted ? Icons.mic_off : Icons.mic)
                              : Icons.headphones,
                      size: 14,
                      color: p.isHandRaised
                          ? const Color(0xFFFFB020)
                          : Colors.white,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                p.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
              ),
              const SizedBox(height: 3),
              Text(
                p.isHost ? 'HOST' : p.isSpeaker ? 'SPEAKER' : p.isHandRaised ? 'HAND RAISED' : 'LISTENER',
                maxLines: 1,
                style: TextStyle(
                  color: p.isHandRaised ? const Color(0xFFFFB020) : _RoomScreenState._muted,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _ReactionStrip extends StatelessWidget {
  const _ReactionStrip({required this.stream});
  final Stream<List<RoomReaction>> stream;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<RoomReaction>>(
        stream: stream,
        builder: (context, snapshot) {
          final reactions = snapshot.data ?? const [];
          if (reactions.isEmpty) return const SizedBox.shrink();
          return SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: reactions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (context, index) {
                final r = reactions[index];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: _RoomScreenState._surface,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: _RoomScreenState._border),
                  ),
                  child: Row(children: [
                    Text(r.emoji, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Text(r.displayName,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                  ]),
                );
              },
            ),
          );
        },
      );
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.participant,
    required this.speakerEnabled,
    required this.leaving,
    required this.onMute,
    required this.onHand,
    required this.onSpeaker,
    required this.onReaction,
    required this.onLeave,
  });

  final RoomParticipant? participant;
  final bool speakerEnabled;
  final bool leaving;
  final VoidCallback? onMute;
  final VoidCallback? onHand;
  final VoidCallback onSpeaker;
  final VoidCallback onReaction;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final muted = participant?.isMuted ?? true;
    final hand = participant?.isHandRaised ?? false;

    return Container(
      padding: EdgeInsets.fromLTRB(
          10, 10, 10, 10 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: Color(0xFA151020),
        border: Border(top: BorderSide(color: _RoomScreenState._border)),
      ),
      child: Row(children: [
        _Button(
          icon: muted ? Icons.mic_off : Icons.mic,
          label: muted ? 'Unmute' : 'Mute',
          onTap: onMute,
          active: !muted,
        ),
        _Button(
          icon: hand ? Icons.back_hand : Icons.back_hand_outlined,
          label: hand ? 'Lower' : 'Raise',
          onTap: onHand,
          active: hand,
        ),
        _Button(
          icon: speakerEnabled ? Icons.volume_up : Icons.volume_off,
          label: 'Audio',
          onTap: onSpeaker,
          active: speakerEnabled,
        ),
        _Button(
          icon: Icons.emoji_emotions,
          label: 'React',
          onTap: onReaction,
        ),
        _Button(
          icon: Icons.call_end,
          label: 'Leave',
          onTap: leaving ? null : onLeave,
          danger: true,
          loading: leaving,
        ),
      ]),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
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
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: danger
                    ? const Color(0xFFFF335F)
                    : active
                        ? const Color(0xFF7921A8)
                        : _RoomScreenState._surface2,
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(icon, color: Colors.white, size: 21),
              ),
              const SizedBox(height: 5),
              Text(label,
                  style: TextStyle(
                      color: danger
                          ? const Color(0xFFFF8CA4)
                          : Colors.white70,
                      fontSize: 9,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}
