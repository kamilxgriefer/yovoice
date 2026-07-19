import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({required this.room, super.key});

  final VoiceRoom room;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen>
    with SingleTickerProviderStateMixin {
  static const Color _background = Color(0xFF080711);
  static const Color _surface = Color(0xFF151020);
  static const Color _surfaceLight = Color(0xFF21172D);
  static const Color _border = Color(0xFF392B47);
  static const Color _secondaryText = Color(0xFF9D95AD);
  static const Color _danger = Color(0xFFFF416C);

  final RoomService _roomService = RoomService();

  late final AnimationController _speakingAnimationController;
  late final Animation<double> _speakingAnimation;

  bool _isMuted = false;
  bool _isSpeakerEnabled = true;
  bool _isLeaving = false;

  User? get _currentUser => FirebaseAuth.instance.currentUser;

  bool get _isCurrentUserHost {
    return _currentUser?.uid == widget.room.hostId;
  }

  @override
  void initState() {
    super.initState();

    _speakingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _speakingAnimation = Tween<double>(begin: 1, end: 1.08).animate(
      CurvedAnimation(
        parent: _speakingAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _speakingAnimationController.dispose();
    super.dispose();
  }

  Future<bool> _confirmLeaveRoom(VoiceRoom room) async {
    final isHost = _currentUser?.uid == room.hostId;

    final result = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) {
        return _LeaveRoomSheet(isHost: isHost);
      },
    );

    return result ?? false;
  }

  Future<void> _leaveRoom(VoiceRoom room) async {
    if (_isLeaving) {
      return;
    }

    final shouldLeave = await _confirmLeaveRoom(room);

    if (!shouldLeave || !mounted) {
      return;
    }

    setState(() {
      _isLeaving = true;
    });

    try {
      final isHost = _currentUser?.uid == room.hostId;

      if (isHost) {
        await _roomService.closeRoom(room.id);
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLeaving = false;
      });

      _showErrorMessage(_getReadableErrorMessage(error));
    }
  }

  void _showInviteMessage() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Inviting people will be added in the next step.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2A1939),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showChatMessage() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Live room chat will be added soon.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2A1939),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) {
        return _RoomOptionsSheet(isHost: _isCurrentUserHost);
      },
    );
  }

  String _getReadableErrorMessage(Object error) {
    final errorMessage = error.toString();

    if (errorMessage.contains('permission-denied')) {
      return 'Firestore permission denied. Check your Firebase rules.';
    }

    if (errorMessage.contains('unavailable')) {
      return 'Firebase is unavailable. Check your internet connection.';
    }

    if (errorMessage.contains('Only the room host')) {
      return 'Only the room host can close this room.';
    }

    return 'Could not leave the room. Please try again.';
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF481C30),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }

        _leaveRoom(widget.room);
      },
      child: StreamBuilder<VoiceRoom>(
        stream: _roomService.watchRoom(widget.room.id),
        initialData: widget.room,
        builder: (context, snapshot) {
          final room = snapshot.data ?? widget.room;

          return Scaffold(
            backgroundColor: _background,
            body: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.8, -0.9),
                  radius: 1.25,
                  colors: [Color(0xFF33134D), Color(0xFF130C1D), _background],
                  stops: [0, 0.42, 1],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    _RoomTopBar(
                      isLeaving: _isLeaving,
                      onClosePressed: () {
                        _leaveRoom(room);
                      },
                      onMorePressed: _showMoreOptions,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                        child: Column(
                          children: [
                            _RoomHeader(room: room),
                            const SizedBox(height: 32),
                            _HostStage(
                              room: room,
                              animation: _speakingAnimation,
                              isMuted: _isMuted,
                            ),
                            const SizedBox(height: 30),
                            _RoomStats(
                              participantCount: room.participantCount,
                              language: room.language,
                              visibility: room.visibility,
                            ),
                            const SizedBox(height: 18),
                            _InviteCard(onPressed: _showInviteMessage),
                            const SizedBox(height: 18),
                            _ParticipantsSection(room: room),
                          ],
                        ),
                      ),
                    ),
                    _RoomControls(
                      isMuted: _isMuted,
                      isSpeakerEnabled: _isSpeakerEnabled,
                      isLeaving: _isLeaving,
                      onMicrophonePressed: () {
                        setState(() {
                          _isMuted = !_isMuted;
                        });
                      },
                      onSpeakerPressed: () {
                        setState(() {
                          _isSpeakerEnabled = !_isSpeakerEnabled;
                        });
                      },
                      onChatPressed: _showChatMessage,
                      onLeavePressed: () {
                        _leaveRoom(room);
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RoomTopBar extends StatelessWidget {
  const _RoomTopBar({
    required this.isLeaving,
    required this.onClosePressed,
    required this.onMorePressed,
  });

  final bool isLeaving;
  final VoidCallback onClosePressed;
  final VoidCallback onMorePressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Row(
        children: [
          _TopBarButton(
            icon: Icons.keyboard_arrow_down_rounded,
            onPressed: isLeaving ? null : onClosePressed,
          ),
          const Expanded(
            child: Text(
              'Voice Room',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
          _TopBarButton(
            icon: Icons.more_horiz_rounded,
            onPressed: onMorePressed,
          ),
        ],
      ),
    );
  }
}

class _TopBarButton extends StatelessWidget {
  const _TopBarButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1B1425),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            color: onPressed == null ? const Color(0xFF665D70) : Colors.white,
            size: 27,
          ),
        ),
      ),
    );
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({required this.room});

  final VoiceRoom room;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LiveBadge(isLive: room.isLive),
            const SizedBox(width: 9),
            _CategoryBadge(category: room.category),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          room.name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 27,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
            height: 1.15,
          ),
        ),
        if (room.description.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 350),
            child: Text(
              room.description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _RoomScreenState._secondaryText,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.isLive});

  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final color = isLive ? const Color(0xFFFF3C70) : const Color(0xFF7D7488);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: isLive
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.7),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            isLive ? 'LIVE' : 'ENDED',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category});

  final String category;

  String get _label {
    if (category.trim().isEmpty) {
      return 'Talk';
    }

    return '${category[0].toUpperCase()}${category.substring(1)}';
  }

  IconData get _icon {
    switch (category.toLowerCase()) {
      case 'music':
        return Icons.music_note_rounded;
      case 'gaming':
        return Icons.sports_esports_rounded;
      case 'chill':
        return Icons.nightlife_rounded;
      case 'study':
        return Icons.school_outlined;
      case 'business':
        return Icons.work_outline_rounded;
      case 'talk':
      default:
        return Icons.forum_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF24172F),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF4A335B)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, color: const Color(0xFFC260FF), size: 15),
          const SizedBox(width: 6),
          Text(
            _label,
            style: const TextStyle(
              color: Color(0xFFD5CCDE),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HostStage extends StatelessWidget {
  const _HostStage({
    required this.room,
    required this.animation,
    required this.isMuted,
  });

  final VoiceRoom room;
  final Animation<double> animation;
  final bool isMuted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ScaleTransition(
          scale: isMuted ? const AlwaysStoppedAnimation<double>(1) : animation,
          child: Container(
            width: 154,
            height: 154,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isMuted
                    ? const [Color(0xFF554A60), Color(0xFF2C2533)]
                    : const [
                        Color(0xFFFF4CA5),
                        Color(0xFFB727FF),
                        Color(0xFF6A00FF),
                      ],
              ),
              boxShadow: [
                BoxShadow(
                  color: isMuted
                      ? Colors.black.withValues(alpha: 0.25)
                      : const Color(0x669D20FF),
                  blurRadius: isMuted ? 18 : 34,
                  spreadRadius: isMuted ? 0 : 5,
                ),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(
                color: _RoomScreenState._background,
                shape: BoxShape.circle,
              ),
              child: _HostAvatar(
                photoUrl: room.hostPhotoUrl,
                hostName: room.hostName,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                room.hostName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 7),
            const _HostBadge(),
          ],
        ),
        const SizedBox(height: 9),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: isMuted ? const Color(0xFF2C2633) : const Color(0xFF251339),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: isMuted
                  ? const Color(0xFF51485B)
                  : const Color(0xFF7A2FA7),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isMuted ? Icons.mic_off_rounded : Icons.graphic_eq_rounded,
                color: isMuted
                    ? const Color(0xFFA098A8)
                    : const Color(0xFFD66FFF),
                size: 17,
              ),
              const SizedBox(width: 7),
              Text(
                isMuted ? 'MICROPHONE MUTED' : 'YOU ARE SPEAKING',
                style: TextStyle(
                  color: isMuted
                      ? const Color(0xFFA098A8)
                      : const Color(0xFFE3A2FF),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HostAvatar extends StatelessWidget {
  const _HostAvatar({required this.photoUrl, required this.hostName});

  final String? photoUrl;
  final String hostName;

  String get _initial {
    final normalizedName = hostName.trim();

    if (normalizedName.isEmpty) {
      return 'Y';
    }

    return normalizedName[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedPhotoUrl = photoUrl?.trim();

    if (normalizedPhotoUrl != null && normalizedPhotoUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          normalizedPhotoUrl,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _AvatarFallback(initial: _initial);
          },
        ),
      );
    }

    return _AvatarFallback(initial: _initial);
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6F1CA1), Color(0xFF311148)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 47,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _HostBadge extends StatelessWidget {
  const _HostBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8B20FF), Color(0xFFC12EFF)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'HOST',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _RoomStats extends StatelessWidget {
  const _RoomStats({
    required this.participantCount,
    required this.language,
    required this.visibility,
  });

  final int participantCount;
  final String language;
  final String visibility;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
      decoration: BoxDecoration(
        color: _RoomScreenState._surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: _RoomScreenState._border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatItem(
              icon: Icons.people_alt_rounded,
              value: '$participantCount',
              label: participantCount == 1 ? 'person' : 'people',
            ),
          ),
          const _StatDivider(),
          Expanded(
            child: _StatItem(
              icon: Icons.language_rounded,
              value: language,
              label: 'language',
            ),
          ),
          const _StatDivider(),
          Expanded(
            child: _StatItem(
              icon: visibility == 'private'
                  ? Icons.lock_outline_rounded
                  : Icons.public_rounded,
              value: visibility == 'private' ? 'Private' : 'Public',
              label: 'access',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFFC05CFF), size: 20),
        const SizedBox(height: 7),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            color: _RoomScreenState._secondaryText,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 40, color: _RoomScreenState._border);
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(21),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(21),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFF2B123E), Color(0xFF1D1429)],
            ),
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: const Color(0xFF62307E)),
          ),
          child: const Row(
            children: [
              _InviteIcon(),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Invite people',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Bring friends into the conversation',
                      style: TextStyle(
                        color: _RoomScreenState._secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Color(0xFF9D83AB)),
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteIcon extends StatelessWidget {
  const _InviteIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 47,
      height: 47,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFB02FFF), Color(0xFF6C00F9)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(
        Icons.person_add_alt_1_rounded,
        color: Colors.white,
        size: 24,
      ),
    );
  }
}

class _ParticipantsSection extends StatelessWidget {
  const _ParticipantsSection({required this.room});

  final VoiceRoom room;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: _RoomScreenState._surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _RoomScreenState._border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.groups_2_rounded, color: Color(0xFFC05CFF), size: 21),
              SizedBox(width: 9),
              Text(
                'People in the room',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          _ParticipantTile(
            name: room.hostName,
            photoUrl: room.hostPhotoUrl,
            role: 'Host',
            isMuted: false,
          ),
        ],
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.name,
    required this.photoUrl,
    required this.role,
    required this.isMuted,
  });

  final String name;
  final String? photoUrl;
  final String role;
  final bool isMuted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: _HostAvatar(photoUrl: photoUrl, hostName: name),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                role,
                style: const TextStyle(
                  color: _RoomScreenState._secondaryText,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 37,
          height: 37,
          decoration: BoxDecoration(
            color: const Color(0xFF261833),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF55316B)),
          ),
          child: Icon(
            isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            color: isMuted ? const Color(0xFF958B9F) : const Color(0xFFD36BFF),
            size: 18,
          ),
        ),
      ],
    );
  }
}

class _RoomControls extends StatelessWidget {
  const _RoomControls({
    required this.isMuted,
    required this.isSpeakerEnabled,
    required this.isLeaving,
    required this.onMicrophonePressed,
    required this.onSpeakerPressed,
    required this.onChatPressed,
    required this.onLeavePressed,
  });

  final bool isMuted;
  final bool isSpeakerEnabled;
  final bool isLeaving;
  final VoidCallback onMicrophonePressed;
  final VoidCallback onSpeakerPressed;
  final VoidCallback onChatPressed;
  final VoidCallback onLeavePressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        13,
        14,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: _RoomScreenState._surface.withValues(alpha: 0.97),
        border: const Border(top: BorderSide(color: _RoomScreenState._border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlButton(
            icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: isMuted ? 'Unmute' : 'Mute',
            isActive: !isMuted,
            onPressed: onMicrophonePressed,
          ),
          _ControlButton(
            icon: isSpeakerEnabled
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
            label: 'Speaker',
            isActive: isSpeakerEnabled,
            onPressed: onSpeakerPressed,
          ),
          _ControlButton(
            icon: Icons.chat_bubble_rounded,
            label: 'Chat',
            onPressed: onChatPressed,
          ),
          _ControlButton(
            icon: Icons.call_end_rounded,
            label: 'Leave',
            isDanger: true,
            isLoading: isLeaving,
            onPressed: isLeaving ? null : onLeavePressed,
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isActive = false,
    this.isDanger = false,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isActive;
  final bool isDanger;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isDanger
        ? const Color(0xFFFF335F)
        : isActive
        ? const Color(0xFF7921A8)
        : _RoomScreenState._surfaceLight;

    final borderColor = isDanger
        ? const Color(0xFFFF6887)
        : isActive
        ? const Color(0xFFB550E6)
        : _RoomScreenState._border;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 49,
                  height: 49,
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor),
                    boxShadow: isDanger
                        ? const [
                            BoxShadow(color: Color(0x44FF335F), blurRadius: 14),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.3,
                          ),
                        )
                      : Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: isDanger
                        ? const Color(0xFFFF8CA4)
                        : const Color(0xFFB9AFBF),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LeaveRoomSheet extends StatelessWidget {
  const _LeaveRoomSheet({required this.isHost});

  final bool isHost;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: _RoomScreenState._surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: _RoomScreenState._border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFF51475E),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: Color(0xFF3A1725),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.call_end_rounded,
              color: _RoomScreenState._danger,
              size: 29,
            ),
          ),
          const SizedBox(height: 17),
          Text(
            isHost ? 'End this room?' : 'Leave this room?',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isHost
                ? 'You are the host. Leaving will end the room for everyone.'
                : 'You can join this room again while it is still live.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _RoomScreenState._secondaryText,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _RoomScreenState._danger,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(
                isHost ? 'END ROOM' : 'LEAVE ROOM',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text(
                'CANCEL',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomOptionsSheet extends StatelessWidget {
  const _RoomOptionsSheet({required this.isHost});

  final bool isHost;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
      decoration: const BoxDecoration(
        color: _RoomScreenState._surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: _RoomScreenState._border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFF51475E),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Room options',
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 20),
          _OptionTile(
            icon: Icons.share_rounded,
            title: 'Share room',
            subtitle: 'Send a link to other people',
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          if (isHost) ...[
            const SizedBox(height: 10),
            _OptionTile(
              icon: Icons.settings_rounded,
              title: 'Room settings',
              subtitle: 'Manage access and participants',
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
          const SizedBox(height: 10),
          _OptionTile(
            icon: Icons.flag_outlined,
            title: 'Report a problem',
            subtitle: 'Tell us about inappropriate activity',
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _RoomScreenState._surfaceLight,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _RoomScreenState._border),
          ),
          child: Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: const Color(0xFF301840),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFFC263FF), size: 22),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _RoomScreenState._secondaryText,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF86778F)),
            ],
          ),
        ),
      ),
    );
  }
}
