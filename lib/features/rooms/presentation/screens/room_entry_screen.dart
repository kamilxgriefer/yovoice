import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/core/theme/space_identity.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/permissions/data/permission_readiness_service.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/rooms/data/models/room_voice_access.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_voice_entry_coordinator.dart';
import 'package:yovoice/features/rooms/data/services/room_mute_coordinator.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/community_voice_room_screen.dart';
import 'package:yovoice/features/rooms/presentation/voice_room_identity.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_ended_state.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

/// The one, explicit door into a room, whichever surface opened it.
///
/// This screen is intentionally a passive preview until the person presses
/// the join CTA. Building it does not resolve voice authority, write a roster
/// row or request LiveKit credentials. After consent, the coordinator remains
/// the single source of truth for the security-sensitive order:
/// server liveness -> roster -> audio token in the destination screen.
class RoomEntryScreen extends StatefulWidget {
  const RoomEntryScreen({
    required this.room,
    this.coordinator,
    this.roomService,
    this.voiceService,
    this.muteCoordinator,
    this.clubService,
    this.playInitialJoinSound = true,
    this.startMuted = true,
    super.key,
  });

  final VoiceRoom room;

  /// False only when room creation already played its richer confirmation.
  /// Connecting LiveKit immediately afterwards must not turn one successful
  /// action into a two-cue jingle.
  final bool playInitialJoinSound;

  /// Every prejoin entry is mic-safe by default. A caller may opt out only
  /// for a deliberate, trusted flow; ordinary navigation never needs to.
  final bool startMuted;

  /// Test seam. Creating a coordinator is side-effect free; [enter] is never
  /// called before the explicit CTA.
  final RoomVoiceEntryCoordinator? coordinator;

  /// Shared room dependencies passed into the destination. Keeping them
  /// injectable makes the complete prejoin -> joined contract testable and
  /// prevents a second, unrelated service instance from being created.
  final RoomService? roomService;

  /// Test seam and shared audio instance handed to the destination screen.
  final VoiceCallService? voiceService;
  final RoomMuteCoordinator? muteCoordinator;
  final ClubService? clubService;

  @override
  State<RoomEntryScreen> createState() => _RoomEntryScreenState();
}

class _RoomEntryScreenState extends State<RoomEntryScreen> {
  late final RoomVoiceEntryCoordinator _coordinator =
      widget.coordinator ??
      RoomVoiceEntryCoordinator.production(rooms: widget.roomService);
  late final VoiceCallService _voice =
      widget.voiceService ?? VoiceCallService.instance;
  late VoiceRoom _previewRoom = widget.room;
  RoomVoiceEntry? _entry;
  bool _joining = false;
  String? _failureMessage;

  Future<void> _join() async {
    if (_joining || _entry != null || !_previewRoom.isActive) return;
    setState(() {
      _joining = true;
      _failureMessage = null;
    });

    try {
      if (_coordinator.requiresMicrophoneForInitialEntry(_previewRoom)) {
        final permissions = await _voice.prepareMediaPermissionsFromUserGesture(
          includeCamera: false,
        );
        if (!mounted) return;
        if (!permissions[AppPermissionKind.microphone].isUsable) {
          final copy = AppLocalizations.of(context);
          setState(() {
            _failureMessage = copy.text(
              'Microphone access is needed to join. Enable it and try again.',
              'Aby dołączyć, zezwól na dostęp do mikrofonu i spróbuj ponownie.',
            );
          });
          return;
        }
      }

      final entry = await _coordinator.enter(
        _previewRoom,
        startMuted: widget.startMuted,
      );
      if (!mounted) return;

      if (entry.outcome == RoomVoiceEntryOutcome.failed) {
        final copy = AppLocalizations.of(context);
        setState(() {
          _previewRoom = entry.room;
          _failureMessage = _localizedEntryFailure(copy, entry.message);
        });
        return;
      }

      setState(() {
        _previewRoom = entry.room;
        _entry = entry;
      });
    } catch (_) {
      if (!mounted) return;
      final copy = AppLocalizations.of(context);
      setState(() {
        _failureMessage = copy.text(
          "Couldn't join the conversation. Check your connection and try again.",
          'Nie udało się dołączyć do rozmowy. Sprawdź połączenie i spróbuj ponownie.',
        );
      });
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  String _localizedEntryFailure(AppLocalizations copy, String? message) {
    return switch (message) {
      'This room is full.' => copy.text(
        'This room is full.',
        'Ten pokój jest pełny.',
      ),
      'This room is currently unavailable.' => copy.text(
        'This room is currently unavailable.',
        'Ten pokój jest teraz niedostępny.',
      ),
      'Voice is not live in this room.' => copy.text(
        'Voice is not live in this room.',
        'Rozmowa głosowa w tym pokoju nie jest teraz aktywna.',
      ),
      'Only club members can enter the Club Lounge.' => copy.text(
        'Only club members can enter the Club Lounge.',
        'Do pokoju klubowego mogą wejść tylko członkowie klubu.',
      ),
      'This lounge is not available right now.' => copy.text(
        'This lounge is not available right now.',
        'Ten pokój klubowy jest teraz niedostępny.',
      ),
      'The room could not be opened.' => copy.text(
        'The room could not be opened.',
        'Nie udało się otworzyć pokoju.',
      ),
      'This room is not currently live.' => copy.text(
        'This room is not currently live.',
        'Rozmowa w tym pokoju nie jest teraz aktywna.',
      ),
      'This room no longer exists.' => copy.text(
        'This room no longer exists.',
        'Ten pokój już nie istnieje.',
      ),
      'You do not have access to this room right now.' => copy.text(
        'You do not have access to this room right now.',
        'Nie masz teraz dostępu do tego pokoju.',
      ),
      'You appear to be offline. Check your connection and try again.' =>
        copy.text(
          'You appear to be offline. Check your connection and try again.',
          'Wygląda na to, że nie masz połączenia. Sprawdź internet i spróbuj ponownie.',
        ),
      'Voice is busy right now. Try again shortly.' => copy.text(
        'Voice is busy right now. Try again shortly.',
        'Rozmowy głosowe są teraz przeciążone. Spróbuj ponownie za chwilę.',
      ),
      'Please sign in again to join this room.' => copy.text(
        'Please sign in again to join this room.',
        'Zaloguj się ponownie, aby dołączyć do tego pokoju.',
      ),
      'The room changed while you were joining. Try again.' => copy.text(
        'The room changed while you were joining. Try again.',
        'Stan pokoju zmienił się podczas dołączania. Spróbuj ponownie.',
      ),
      'Could not check this room. Try again.' => copy.text(
        'Could not check this room. Try again.',
        'Nie udało się sprawdzić pokoju. Spróbuj ponownie.',
      ),
      'Could not start voice. Try again.' => copy.text(
        'Could not start voice. Try again.',
        'Nie udało się rozpocząć rozmowy. Spróbuj ponownie.',
      ),
      'Could not join this room. Try again.' => copy.text(
        'Could not join this room. Try again.',
        'Nie udało się dołączyć do pokoju. Spróbuj ponownie.',
      ),
      _ => copy.text(
        "Couldn't join the conversation. Check your connection and try again.",
        'Nie udało się dołączyć do rozmowy. Sprawdź połączenie i spróbuj ponownie.',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    final content = entry == null
        ? _RoomPrejoinPreview(
            room: _previewRoom,
            joining: _joining,
            startMuted: widget.startMuted,
            failureMessage: _failureMessage,
            onJoin: _join,
          )
        : _destination(entry);
    return YoImmersiveDarkSurface(child: content);
  }

  Widget _destination(RoomVoiceEntry entry) {
    if (entry.outcome == RoomVoiceEntryOutcome.unavailable) {
      return Scaffold(
        backgroundColor: AppImmersiveColors.background,
        body: SafeArea(
          child: entry.room.isBroadcast
              ? RoomEndedState(
                  roomName: entry.room.name,
                  accent: BroadcastRoomColors.accent,
                )
              : RoomEndedState(roomName: entry.room.name),
        ),
      );
    }

    if (entry.room.roomExperience == RoomExperience.broadcast) {
      return BroadcastRoomScreen(
        room: entry.room,
        voiceEntry: entry,
        roomService: widget.roomService,
        voiceService: _voice,
        entryCoordinator: _coordinator,
        muteCoordinator: widget.muteCoordinator,
        playInitialJoinSound: widget.playInitialJoinSound,
        startMuted: widget.startMuted,
      );
    }
    return CommunityVoiceRoomScreen(
      room: entry.room,
      voiceEntry: entry,
      roomService: widget.roomService,
      voiceService: _voice,
      entryCoordinator: _coordinator,
      muteCoordinator: widget.muteCoordinator,
      clubService: widget.clubService,
      playInitialJoinSound: widget.playInitialJoinSound,
      startMuted: widget.startMuted,
    );
  }
}

class _RoomPrejoinPreview extends StatelessWidget {
  const _RoomPrejoinPreview({
    required this.room,
    required this.joining,
    required this.startMuted,
    required this.failureMessage,
    required this.onJoin,
  });

  final VoiceRoom room;
  final bool joining;
  final bool startMuted;
  final String? failureMessage;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final identity = voiceRoomIdentity(room);
    final unavailable = !room.isActive || room.deletionInProgress;
    final status = unavailable
        ? copy.text('Unavailable', 'Niedostępny')
        : room.isLive
        ? copy.text('Live now', 'Teraz na żywo')
        : copy.text(
            'Ready when the host starts',
            'Gotowy, gdy gospodarz rozpocznie',
          );
    final topic = room.topic.trim().isNotEmpty
        ? room.topic.trim()
        : room.description.trim();

    return Scaffold(
      backgroundColor: AppImmersiveColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(.15, -.95),
                  radius: 1.25,
                  colors: [
                    identity.primary.withValues(alpha: .22),
                    AppImmersiveColors.background,
                  ],
                  stops: const [0, .72],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton.filledTonal(
                          tooltip: copy.text('Back', 'Wstecz'),
                          onPressed: () => Navigator.of(context).maybePop(),
                          style: IconButton.styleFrom(
                            backgroundColor: AppImmersiveColors.surface,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        copy.text('Before you join', 'Zanim dołączysz'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 29,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.6,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        copy.text(
                          'Take a look, then join when you are ready.',
                          'Sprawdź szczegóły i dołącz, gdy będziesz gotowy.',
                        ),
                        style: const TextStyle(
                          color: AppImmersiveColors.textSecondary,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _RoomPreviewHero(
                        room: room,
                        identity: identity,
                        typeLabel: _typeLabel(copy, identity),
                        status: status,
                        topic: topic,
                      ),
                      const SizedBox(height: 14),
                      _HostCard(room: room, identity: identity),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppImmersiveColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: identity.primary.withValues(alpha: .28),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: identity.primary.withValues(alpha: .16),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                startMuted
                                    ? Icons.mic_off_rounded
                                    : Icons.mic_rounded,
                                color: identity.accent,
                                size: 21,
                              ),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    startMuted
                                        ? copy.text(
                                            'Microphone off',
                                            'Mikrofon wyłączony',
                                          )
                                        : copy.text(
                                            'Microphone on',
                                            'Mikrofon włączony',
                                          ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    startMuted
                                        ? copy.text(
                                            "You'll enter muted and can unmute when you're ready.",
                                            'Dołączysz z wyciszonym mikrofonem i włączysz go, gdy będziesz gotowy.',
                                          )
                                        : copy.text(
                                            'People in the room may hear you as soon as you join.',
                                            'Osoby w pokoju mogą Cię usłyszeć od razu po dołączeniu.',
                                          ),
                                    style: const TextStyle(
                                      color: AppImmersiveColors.textSecondary,
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (failureMessage != null) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            key: const ValueKey('room-prejoin-error'),
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: const Color(0xFF32131D),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: const Color(
                                  0xFFFF6A76,
                                ).withValues(alpha: .5),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: Color(0xFFFFA7B1),
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    failureMessage!,
                                    style: const TextStyle(
                                      color: Color(0xFFFFCDD2),
                                      fontSize: 13,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 56,
                        child: FilledButton(
                          key: const ValueKey('room-prejoin-join'),
                          onPressed: unavailable || joining ? null : onJoin,
                          style: FilledButton.styleFrom(
                            backgroundColor: identity.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                AppImmersiveColors.surfaceRaised,
                            disabledForegroundColor:
                                AppImmersiveColors.textSecondary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: joining
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 11),
                                    Text(copy.text('Joining…', 'Dołączanie…')),
                                  ],
                                )
                              : Text(
                                  unavailable
                                      ? copy.text(
                                          'Room unavailable',
                                          'Pokój niedostępny',
                                        )
                                      : copy.text(
                                          'Join conversation',
                                          'Dołącz do rozmowy',
                                        ),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _typeLabel(AppLocalizations copy, SpaceIdentity identity) {
    return switch (identity.kind) {
      SpaceKind.community => copy.text(
        'Community room',
        'Pokój społecznościowy',
      ),
      SpaceKind.podcast => copy.text('Podcast room', 'Pokój podcastowy'),
      SpaceKind.club => copy.text('Club room', 'Pokój klubowy'),
      SpaceKind.family => copy.text('Family room', 'Pokój rodzinny'),
    };
  }
}

class _RoomPreviewHero extends StatelessWidget {
  const _RoomPreviewHero({
    required this.room,
    required this.identity,
    required this.typeLabel,
    required this.status,
    required this.topic,
  });

  final VoiceRoom room;
  final SpaceIdentity identity;
  final String typeLabel;
  final String status;
  final String topic;

  @override
  Widget build(BuildContext context) {
    final image = room.imageUrl?.trim();
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.min<double>(300, constraints.maxWidth * 9 / 16);
        return SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [identity.primary, identity.surface],
                    ),
                  ),
                ),
                if (image != null && image.isNotEmpty)
                  Image.network(
                    image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: .08),
                        Colors.black.withValues(alpha: .82),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _PreviewPill(
                            icon: identity.icon,
                            label: typeLabel,
                            color: identity.accent,
                          ),
                          _PreviewPill(
                            icon: room.isLive
                                ? Icons.graphic_eq_rounded
                                : Icons.schedule_rounded,
                            label: status,
                            color: room.isLive
                                ? const Color(0xFF57D99A)
                                : Colors.white70,
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        room.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          height: 1.08,
                          letterSpacing: -.5,
                        ),
                      ),
                      if (topic.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          topic,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .78),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PreviewPill extends StatelessWidget {
  const _PreviewPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .48)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HostCard extends StatelessWidget {
  const _HostCard({required this.room, required this.identity});

  final VoiceRoom room;
  final SpaceIdentity identity;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppImmersiveColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppImmersiveColors.border),
      ),
      child: Row(
        children: [
          UserAvatar(
            radius: 24,
            userId: room.hostId,
            photoUrl: room.hostPhotoUrl,
            displayName: room.hostName,
            backgroundColor: identity.primary,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy.text('Hosted by', 'Gospodarz'),
                  style: const TextStyle(
                    color: AppImmersiveColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  room.hostName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
