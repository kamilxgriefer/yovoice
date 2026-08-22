import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/rooms/data/models/room_message.dart';
import 'package:yovoice/features/rooms/data/services/room_mute_coordinator.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';
import 'package:yovoice/features/rooms/presentation/widgets/mini_player/active_room_controls.dart';
import 'package:yovoice/features/rooms/presentation/widgets/mini_player/active_room_info.dart';
import 'package:yovoice/features/rooms/presentation/widgets/mini_player/expanded_mini_chat.dart';
import 'package:yovoice/features/rooms/presentation/widgets/mini_player/live_chat_preview.dart';

/// The persistent live-room mini player: a VIEW over the one
/// [VoiceCallService] session. It never rebuilds or reconnects RTC —
/// expanding the chat, muting, and collapsing are UI and Firestore work
/// only; the audio session is owned elsewhere.
///
/// Renders nothing when no session is active, so the shell mounts it
/// unconditionally. Above ~[_dockBreakpoint] of available width it is the
/// desktop floating dock; below, the mobile card that sits above the
/// bottom navigation.
///
/// TAP-TARGET ISOLATION IS THE CONTRACT HERE. The previous bar wrapped
/// everything in one InkWell(onTap: return-to-room); a disabled mute
/// IconButton inside it did not compete for the tap, which therefore fell
/// through to the parent — pressing Mute mid-toggle NAVIGATED INTO THE
/// ROOM. This player has no parent-wide onTap at all: the room-info zone
/// navigates, Mute only toggles (and swallows taps while busy), Expand
/// only opens the chat, Return navigates, Leave/End only leaves.
class ActiveRoomMiniPlayer extends StatefulWidget {
  const ActiveRoomMiniPlayer({
    this.voiceService,
    this.muteCoordinator,
    this.roomService,
    this.openRoom,
    super.key,
  });

  /// Test seams; production resolves the shared singletons lazily so the
  /// shell can mount `const` instances with no Firebase app in tests.
  final VoiceCallService? voiceService;
  final RoomMuteCoordinator? muteCoordinator;
  final RoomService? roomService;

  /// How "go into the room" is performed. Production pushes
  /// [RoomEntryScreen]; tests inject a recorder so navigation isolation
  /// is an assertable fact.
  final Future<void> Function(BuildContext context, String roomId)? openRoom;

  @override
  State<ActiveRoomMiniPlayer> createState() => _ActiveRoomMiniPlayerState();
}

class _ActiveRoomMiniPlayerState extends State<ActiveRoomMiniPlayer> {
  static const double _dockBreakpoint = 880;
  static RoomService? _productionRooms;

  VoiceCallService get _voice =>
      widget.voiceService ?? VoiceCallService.instance;
  RoomMuteCoordinator get _mutes =>
      widget.muteCoordinator ?? RoomMuteCoordinator.production;
  RoomService get _rooms =>
      widget.roomService ?? (_productionRooms ??= RoomService());

  final LayerLink _dockLink = LayerLink();
  OverlayEntry? _desktopChatOverlay;

  String? _watchedRoomId;
  StreamSubscription<RoomMessage?>? _latestSub;
  RoomMessage? _latest;
  bool _sawFirstLatestSnapshot = false;

  /// SESSION-LOCAL "new since collapsed" count. There is no per-user read
  /// state for room chat in the backend, and none is faked (CLAUDE.md):
  /// this counts messages that arrived while the preview was collapsed
  /// and the user was away from the room, and resets when the expanded
  /// chat opens or the user returns to the room. Global unread is
  /// deliberately omitted — it would require backend state that does not
  /// exist.
  int _newCount = 0;
  bool _isHost = false;

  /// True only when the destructive action will genuinely END the session
  /// right now: RoomService.leaveRoom routes ONLY a temporary room's host
  /// through endCommunityVoice; a persistent-room or lounge host merely
  /// leaves, and the server ends the session once the roster proves it
  /// empty (ADR-091). Labeling that path "End room" overclaimed — the
  /// review measured the mismatch — so the label follows what the tap
  /// actually does.
  bool _hostEndsNow = false;
  bool _expandedOpen = false;
  bool _navigatingIntoRoom = false;
  bool _lastLayoutIsDock = false;

  @override
  void initState() {
    super.initState();
    _voice.addListener(_handleSessionChanged);
    _handleSessionChanged();
  }

  @override
  void didUpdateWidget(ActiveRoomMiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.voiceService != widget.voiceService) {
      (oldWidget.voiceService ?? VoiceCallService.instance).removeListener(
        _handleSessionChanged,
      );
      _voice.addListener(_handleSessionChanged);
      _handleSessionChanged();
    }
  }

  @override
  void dispose() {
    _voice.removeListener(_handleSessionChanged);
    unawaited(_latestSub?.cancel());
    _removeDesktopChatOverlay();
    super.dispose();
  }

  /// The session this player is a view over, or null when there is none.
  String? get _activeRoomId {
    final roomId = _voice.roomId;
    if (roomId == null) return null;
    switch (_voice.status) {
      case VoiceCallStatus.connected:
      case VoiceCallStatus.connecting:
      case VoiceCallStatus.reconnecting:
        return roomId;
      case VoiceCallStatus.disconnected:
      case VoiceCallStatus.failed:
        return null;
    }
  }

  /// Re-targets the preview stream and per-room state when the session's
  /// room changes (including ending: a room that ends remotely drops the
  /// subscription and the player disappears via the ListenableBuilder).
  void _handleSessionChanged() {
    final roomId = _activeRoomId;
    if (roomId == _watchedRoomId) return;
    _watchedRoomId = roomId;
    unawaited(_latestSub?.cancel());
    _latestSub = null;
    _latest = null;
    _sawFirstLatestSnapshot = false;
    _newCount = 0;
    _isHost = false;
    _hostEndsNow = false;
    _removeDesktopChatOverlay();
    _dismissMobileSheetIfOpen();
    // A room that ended while the expanded chat was open must not leave
    // the "expanded" latch set, or the NEXT session's Expand would no-op.
    // (The mobile sheet also clears the latch itself when it pops.)
    _expandedOpen = false;
    if (roomId == null) return;
    _latestSub = _rooms
        .watchLatestRoomMessage(roomId)
        .listen(_handleLatestMessage, onError: (Object _) {});
    unawaited(_resolveHost(roomId));
  }

  Future<void> _resolveHost(String roomId) async {
    try {
      final room = await _rooms.getRoom(roomId);
      if (!mounted || _watchedRoomId != roomId) return;
      final uid = _rooms.currentUserId;
      setState(() {
        _isHost = uid.isNotEmpty && room.hostId == uid;
        _hostEndsNow = _isHost && room.roomType == RoomType.temporary;
      });
    } catch (_) {
      // Unknown host (offline, room doc gone): stay in the participant
      // shape — Leave keeps working and never overclaims "End room".
    }
  }

  void _handleLatestMessage(RoomMessage? message) {
    if (!mounted) return;
    final previous = _latest;
    final firstSnapshot = !_sawFirstLatestSnapshot;
    _sawFirstLatestSnapshot = true;

    // A NEW ARRIVAL, not any change: the first snapshot only baselines,
    // a reaction keeps the same id, and a moderated/deleted latest falls
    // back to an OLDER message — none of those may increment the count.
    final arrived =
        !firstSnapshot &&
        message != null &&
        (previous == null ||
            (message.id != previous.id && _isNewer(message, previous)));

    setState(() {
      _latest = message;
      if (arrived && !_expandedOpen && !_navigatingIntoRoom) {
        _newCount++;
      }
    });
  }

  static bool _isNewer(RoomMessage message, RoomMessage previous) {
    final a = message.createdAt;
    final b = previous.createdAt;
    // A pending serverTimestamp means "just written" — genuinely new.
    if (a == null) return true;
    if (b == null) return false;
    return a.isAfter(b);
  }

  // ---------------------------------------------------------------- actions

  Future<void> _returnToRoom() async {
    final roomId = _watchedRoomId;
    if (roomId == null || _navigatingIntoRoom) return;
    _collapseExpandedChat();
    setState(() {
      _newCount = 0;
      _navigatingIntoRoom = true;
    });
    try {
      final open = widget.openRoom;
      if (open != null) {
        await open(context, roomId);
      } else {
        try {
          final room = await _rooms.getRoom(roomId);
          if (!mounted) return;
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => RoomEntryScreen(room: room),
            ),
          );
        } catch (_) {
          // Room doc gone (ended while minimized): drop the stale session.
          await _voice.disconnect();
        }
      }
    } finally {
      _navigatingIntoRoom = false;
      if (mounted) {
        // Back from the room: whatever arrived meanwhile was on screen in
        // the room itself, so the session-local count restarts at zero.
        setState(() => _newCount = 0);
      }
    }
  }

  bool get _muteBusy => _voice.muteChangeInProgress || _mutes.isBusy;

  /// Mute goes through the ONE coordinator the room screens use — roster
  /// first, LiveKit second, server-recomputed permissions (ADR-094:
  /// self-mute is track state, never a permission).
  Future<void> _toggleMute() async {
    final roomId = _watchedRoomId;
    if (roomId == null || _muteBusy) return;
    final outcome = await _mutes.toggle(roomId: roomId);
    if (!mounted) return;
    switch (outcome) {
      case RoomMuteOutcome.applied:
      case RoomMuteOutcome.busy:
      // The player disappears on its own once the stale session disconnects.
      case RoomMuteOutcome.sessionEnded:
        break;
      case RoomMuteOutcome.failed:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Could not change microphone state. Try again.'),
            ),
          );
    }
  }

  Future<void> _leaveOrEnd() async {
    final roomId = _watchedRoomId;
    if (roomId == null) return;
    if (_hostEndsNow) {
      final confirmed = await _confirmEnd();
      if (confirmed != true || !mounted) return;
    }
    _collapseExpandedChat();
    // Same order and semantics as the room screens: audio first, then the
    // idempotent RoomService.leaveRoom (ADR-091) — which routes a host's
    // temporary room to end and proves emptiness server-side on the
    // fallback. The player invents no leave semantics of its own.
    await _voice.disconnect();
    try {
      await _rooms.leaveRoom(roomId);
    } catch (_) {
      // Best effort — the audio is already gone, and the participant doc
      // is cleaned up by moderation/room-end flows if this write failed.
    }
  }

  Future<bool?> _confirmEnd() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'End room?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'You are the host. Leaving can end this live session for '
          'everyone still inside.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('mini-player-end-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('End room'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- expanded chat

  Future<void> _expandChat() async {
    final roomId = _watchedRoomId;
    if (roomId == null || _expandedOpen) return;
    setState(() {
      _newCount = 0;
      _expandedOpen = true;
    });
    if (_lastLayoutIsDock) {
      _openDesktopChatOverlay(roomId);
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Room chat expanded',
          Directionality.of(context),
        ),
      );
      return;
    }
    _mobileSheetNavigator = Navigator.of(context, rootNavigator: true);
    _mobileSheetOpen = true;
    await showExpandedMiniChatSheet(
      context,
      roomId: roomId,
      // TRUE host status: this governs the chat surface's moderation
      // powers, not the destructive label — a persistent-room host still
      // moderates their chat even though their tap merely leaves.
      isHost: _isHost,
      service: _rooms,
    );
    _mobileSheetOpen = false;
    _mobileSheetNavigator = null;
    if (mounted) {
      setState(() {
        _expandedOpen = false;
        _newCount = 0;
      });
    } else {
      _expandedOpen = false;
    }
  }

  NavigatorState? _mobileSheetNavigator;
  bool _mobileSheetOpen = false;

  /// A remote room end while the MOBILE sheet is open: the desktop overlay
  /// is removed by session change, but a modal sheet is a real route and
  /// stayed on the navigator with a live composer for a dead room. While
  /// the sheet is open it is modal (taps elsewhere are blocked), so the
  /// top-of-stack pop below can only ever remove the sheet itself or a
  /// dialog stacked over it by the same surface — both belong to the dead
  /// session.
  void _dismissMobileSheetIfOpen() {
    if (!_mobileSheetOpen) return;
    _mobileSheetOpen = false;
    final navigator = _mobileSheetNavigator;
    _mobileSheetNavigator = null;
    navigator?.maybePop();
  }

  void _openDesktopChatOverlay(String roomId) {
    _removeDesktopChatOverlay();
    final entry = OverlayEntry(
      builder: (overlayContext) {
        final screen = MediaQuery.sizeOf(overlayContext);
        final width = math.min(440.0, screen.width - 32);
        final height = math.min(560.0, screen.height * .68);
        return Stack(
          children: [
            // Tap anywhere outside: collapse. The chat is a popover, not
            // a route — the RTC session and the shell stay untouched.
            Positioned.fill(
              child: Semantics(
                button: true,
                label: 'Close room chat',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _collapseExpandedChat,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: CompositedTransformFollower(
                link: _dockLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.topCenter,
                followerAnchor: Alignment.bottomCenter,
                offset: const Offset(0, -10),
                child: SizedBox(
                  width: width,
                  height: height,
                  // Overlay entries sit outside any route's Material; the
                  // chat surface (TextField included) needs one. The
                  // FocusScope is the a11y half: a raw OverlayEntry is not
                  // a route, so without it Escape did nothing and keyboard
                  // focus never entered the popover.
                  child: FocusScope(
                    autofocus: true,
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.escape) {
                        _collapseExpandedChat();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Material(
                      color: Colors.transparent,
                      child: ExpandedMiniChat(
                        roomId: roomId,
                        // True host status — moderation powers, not the label.
                        isHost: _isHost,
                        service: _rooms,
                        onCollapse: _collapseExpandedChat,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    _desktopChatOverlay = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  void _removeDesktopChatOverlay() {
    _desktopChatOverlay?.remove();
    _desktopChatOverlay = null;
  }

  void _collapseExpandedChat() {
    if (_desktopChatOverlay != null) {
      _removeDesktopChatOverlay();
      if (mounted) {
        setState(() {
          _expandedOpen = false;
          _newCount = 0;
        });
      } else {
        _expandedOpen = false;
      }
      return;
    }
    if (_expandedOpen && mounted) {
      // Mobile sheet: pop it if it is still up (leave/return paths).
      final navigator = Navigator.maybeOf(context);
      if (navigator != null && navigator.canPop()) {
        navigator.pop();
      }
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_voice, _mutes]),
      builder: (context, _) {
        final roomId = _activeRoomId;
        if (roomId == null) return const SizedBox.shrink();

        final reconnecting = _voice.status != VoiceCallStatus.connected;
        final roomName = _voice.roomName ?? 'Live room';
        final participantCount = _voice.participants.length;

        return LayoutBuilder(
          builder: (context, constraints) {
            final isDock = constraints.maxWidth >= _dockBreakpoint;
            _lastLayoutIsDock = isDock;

            final info = ActiveRoomInfo(
              roomName: roomName,
              reconnecting: reconnecting,
              participantCount: participantCount,
              onReturnToRoom: () => unawaited(_returnToRoom()),
              compact: !isDock,
              narrow: constraints.maxWidth < 360,
            );
            final preview = LiveChatPreview(
              latest: _latest,
              newCount: _newCount,
              onExpand: () => unawaited(_expandChat()),
              compact: !isDock,
            );
            final controls = ActiveRoomControls(
              micState: _voice.micState,
              muteBusy: _muteBusy,
              isHost: _hostEndsNow,
              onToggleMute: () => unawaited(_toggleMute()),
              onReturnToRoom: () => unawaited(_returnToRoom()),
              onLeave: () => unawaited(_leaveOrEnd()),
              layout: isDock
                  ? ActiveRoomControlsLayout.dock
                  : ActiveRoomControlsLayout.grid,
            );

            final surface = isDock
                ? _DockSurface(info: info, preview: preview, controls: controls)
                : _CardSurface(
                    info: info,
                    preview: preview,
                    controls: controls,
                  );

            // Density stays usable down to 320px: text scaling inside the
            // player is honored up to 1.6x, then clamped so oversized text
            // degrades metadata (ellipsis) before it can break controls.
            return MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.6,
              child: KeyedSubtree(
                key: const ValueKey('mini-player'),
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: CompositedTransformTarget(
                    link: _dockLink,
                    child: surface,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Desktop: a wide floating rounded dock near the bottom — four zones
/// separated by thin dividers, with the subtle violet border glow.
class _DockSurface extends StatelessWidget {
  const _DockSurface({
    required this.info,
    required this.preview,
    required this.controls,
  });

  final Widget info;
  final Widget preview;
  final Widget controls;

  @override
  Widget build(BuildContext context) {
    return Align(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1120),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: _playerDecoration(radius: 22),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 5, child: info),
                    const _ZoneDivider(),
                    Expanded(flex: 6, child: preview),
                    const _ZoneDivider(),
                    controls,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mobile: the taller card that sits above the bottom navigation — room
/// info and the chat preview side by side, the control grid underneath.
class _CardSurface extends StatelessWidget {
  const _CardSurface({
    required this.info,
    required this.preview,
    required this.controls,
  });

  final Widget info;
  final Widget preview;
  final Widget controls;

  @override
  Widget build(BuildContext context) {
    return Align(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 640),
        margin: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        decoration: _playerDecoration(radius: 18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: info),
                      const SizedBox(width: 10),
                      Expanded(flex: 6, child: preview),
                    ],
                  ),
                  const SizedBox(height: 9),
                  controls,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoneDivider extends StatelessWidget {
  const _ZoneDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      color: AppColors.divider,
    );
  }
}

BoxDecoration _playerDecoration({required double radius}) {
  return BoxDecoration(
    color: Color.lerp(AppColors.surface, AppColors.background, .25),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: AppColors.voice.withValues(alpha: .45)),
    boxShadow: [
      BoxShadow(
        color: AppColors.primary.withValues(alpha: .22),
        blurRadius: 22,
        spreadRadius: 1,
      ),
      const BoxShadow(
        color: Color(0x66000000),
        blurRadius: 18,
        offset: Offset(0, 6),
      ),
    ],
  );
}
