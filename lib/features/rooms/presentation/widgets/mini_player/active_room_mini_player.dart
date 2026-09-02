import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/permissions/data/permission_readiness_service.dart';
import 'package:yovoice/features/rooms/data/models/room_message.dart';
import 'package:yovoice/features/rooms/data/services/room_mute_coordinator.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';
import 'package:yovoice/features/rooms/presentation/widgets/mini_player/active_room_controls.dart';
import 'package:yovoice/features/rooms/presentation/widgets/mini_player/active_room_info.dart';
import 'package:yovoice/features/rooms/presentation/widgets/mini_player/compact_active_room_bar.dart';
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
  final FocusNode _desktopExpandFocusNode = FocusNode(
    debugLabel: 'desktop room chat expand',
  );
  late final FocusScopeNode _desktopChatFocusScope;

  late _RoomBarProjection _projection;
  late bool _coordinatorBusy;

  String? _watchedRoomId;
  int _sessionGeneration = 0;
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
  _RoomAuthorityStatus _roomAuthority = _RoomAuthorityStatus.checking;
  int _authorityAttempt = 0;

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
  bool _preparingMicrophone = false;

  @override
  void initState() {
    super.initState();
    _desktopChatFocusScope = FocusScopeNode(
      debugLabel: 'desktop room chat modal scope',
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      directionalTraversalEdgeBehavior: TraversalEdgeBehavior.stop,
      onKeyEvent: _handleDesktopChatKeyEvent,
    );
    _projection = _readProjection();
    _coordinatorBusy = _mutes.isBusy;
    _voice.addListener(_handleVoiceChanged);
    _mutes.addListener(_handleCoordinatorChanged);
    _syncRoomSession(_projection.roomId);
  }

  @override
  void didUpdateWidget(ActiveRoomMiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final roomServiceChanged = oldWidget.roomService != widget.roomService;
    if (oldWidget.voiceService != widget.voiceService) {
      (oldWidget.voiceService ?? VoiceCallService.instance).removeListener(
        _handleVoiceChanged,
      );
      _voice.addListener(_handleVoiceChanged);
      _projection = _readProjection();
      if (roomServiceChanged) _watchedRoomId = null;
      _syncRoomSession(_projection.roomId);
    } else if (roomServiceChanged) {
      // Test seams and scoped service overrides must not leave the preview
      // subscribed to the previous repository when the room id itself stays
      // unchanged.
      _watchedRoomId = null;
      _syncRoomSession(_projection.roomId);
    }
    if (oldWidget.muteCoordinator != widget.muteCoordinator) {
      (oldWidget.muteCoordinator ?? RoomMuteCoordinator.production)
          .removeListener(_handleCoordinatorChanged);
      _mutes.addListener(_handleCoordinatorChanged);
      _coordinatorBusy = _mutes.isBusy;
    }
  }

  @override
  void dispose() {
    _voice.removeListener(_handleVoiceChanged);
    _mutes.removeListener(_handleCoordinatorChanged);
    unawaited(_latestSub?.cancel());
    _dismissChatAuxiliaryRouteIfOpen();
    _removeDesktopChatOverlay();
    _dismissMobileSheetIfOpen();
    _dismissMobileActionsIfOpen();
    _dismissEndConfirmationIfOpen();
    _desktopChatFocusScope.dispose();
    _desktopExpandFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleDesktopChatKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _collapseExpandedChat();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Captures only fields that can change this surface. VoiceCallService also
  /// notifies for its ~20 Hz audio meter; those samples intentionally do not
  /// rebuild the entire mini player.
  _RoomBarProjection _readProjection() {
    String? roomId;
    if (_voice.isRoomSession) roomId = _voice.roomId;
    if (roomId != null) {
      switch (_voice.status) {
        case VoiceCallStatus.connected:
        case VoiceCallStatus.connecting:
        case VoiceCallStatus.reconnecting:
          break;
        case VoiceCallStatus.disconnected:
        case VoiceCallStatus.failed:
          roomId = null;
      }
    }

    return _RoomBarProjection(
      roomId: roomId,
      roomName: _voice.roomName ?? 'YO Voice',
      status: _voice.status,
      participantCount: _voice.participantCount,
      micState: _voice.micState,
      voiceMuteBusy: _voice.muteChangeInProgress,
    );
  }

  void _handleVoiceChanged() {
    final next = _readProjection();
    final changed = next != _projection;
    _projection = next;
    _syncRoomSession(next.roomId);
    if (changed && mounted) setState(() {});
  }

  void _handleCoordinatorChanged() {
    final next = _mutes.isBusy;
    if (next == _coordinatorBusy) return;
    _coordinatorBusy = next;
    if (mounted) setState(() {});
  }

  /// Re-targets the preview stream and per-room state when the session's
  /// room changes (including ending: a room that ends remotely drops the
  /// subscription and the player reverses out through the continuity shell).
  void _syncRoomSession(String? roomId) {
    if (roomId == _watchedRoomId) return;
    _sessionGeneration++;
    _authorityAttempt++;
    _watchedRoomId = roomId;
    unawaited(_latestSub?.cancel());
    _latestSub = null;
    _latest = null;
    _sawFirstLatestSnapshot = false;
    _newCount = 0;
    _isHost = false;
    _hostEndsNow = false;
    _roomAuthority = _RoomAuthorityStatus.checking;
    _navigatingIntoRoom = false;
    _dismissChatAuxiliaryRouteIfOpen();
    _removeDesktopChatOverlay();
    _dismissMobileSheetIfOpen();
    _dismissMobileActionsIfOpen();
    _dismissEndConfirmationIfOpen();
    // A room that ended while the expanded chat was open must not leave
    // the "expanded" latch set, or the NEXT session's Expand would no-op.
    // (The mobile sheet also clears the latch itself when it pops.)
    _expandedOpen = false;
    if (roomId == null) return;
    final generation = _sessionGeneration;
    _latestSub = _rooms.watchLatestRoomMessage(roomId).listen((message) {
      if (_isCurrentSession(roomId, generation)) {
        _handleLatestMessage(message);
      }
    }, onError: (Object _) {});
    unawaited(_resolveHost(roomId, generation));
  }

  bool _isCurrentSession(String roomId, int generation) {
    return mounted &&
        generation == _sessionGeneration &&
        _watchedRoomId == roomId &&
        _voice.isRoomSession &&
        _voice.roomId == roomId;
  }

  Future<bool> _resolveHost(String roomId, int generation) async {
    final attempt = ++_authorityAttempt;
    try {
      final room = await _rooms.getRoom(roomId);
      if (!_isCurrentSession(roomId, generation) ||
          attempt != _authorityAttempt) {
        return false;
      }
      final uid = _rooms.currentUserId;
      setState(() {
        _isHost = uid.isNotEmpty && room.hostId == uid;
        _hostEndsNow = _isHost && room.roomType == RoomType.temporary;
        _roomAuthority = _RoomAuthorityStatus.resolved;
      });
      return true;
    } catch (_) {
      if (_isCurrentSession(roomId, generation) &&
          attempt == _authorityAttempt) {
        setState(() => _roomAuthority = _RoomAuthorityStatus.unavailable);
      }
      return false;
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
    final generation = _sessionGeneration;
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
          if (!mounted || !_isCurrentSession(roomId, generation)) return;
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => RoomEntryScreen(room: room),
            ),
          );
        } catch (_) {
          // Room doc gone (ended while minimized): drop the stale session.
          if (_isCurrentSession(roomId, generation)) {
            await _voice.disconnect();
          }
        }
      }
    } finally {
      if (_isCurrentSession(roomId, generation)) {
        // Back from the room: whatever arrived meanwhile was on screen in
        // the room itself, so the session-local count restarts at zero.
        setState(() {
          _navigatingIntoRoom = false;
          _newCount = 0;
        });
      }
    }
  }

  bool get _muteBusy =>
      _projection.voiceMuteBusy || _coordinatorBusy || _preparingMicrophone;

  /// Mute goes through the ONE coordinator the room screens use — roster
  /// with privacy-first local mute and authority-first unmute (ADR-094:
  /// self-mute is track state, never a permission).
  Future<void> _toggleMute() async {
    final roomId = _watchedRoomId;
    if (roomId == null || _muteBusy) return;
    final generation = _sessionGeneration;

    // A promoted broadcast listener can become a publisher while the room
    // screen is minimized. That turns this tile from listen-only into an
    // Unmute control, but it does not mean microphone access has been
    // granted. Preserve the browser user activation from this tap and obtain
    // access BEFORE RoomMuteCoordinator writes `isMuted: false` to the
    // roster. A refusal therefore changes neither server nor local state.
    if (_voice.isMuted) {
      _preparingMicrophone = true;
      if (mounted) setState(() {});
      PermissionReadinessSnapshot permissions;
      try {
        permissions = await _voice.prepareMediaPermissionsFromUserGesture(
          includeCamera: false,
        );
      } catch (_) {
        permissions = PermissionReadinessSnapshot(const {
          AppPermissionKind.microphone: AppPermissionAccess.unavailable,
        });
      } finally {
        _preparingMicrophone = false;
        if (mounted) setState(() {});
      }
      if (!mounted ||
          !_isCurrentSession(roomId, generation) ||
          !_voice.isMuted) {
        return;
      }
      if (!permissions[AppPermissionKind.microphone].isUsable) {
        final copy = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                copy.text(
                  'Microphone access is needed to speak. Enable it and try again.',
                  'Aby mówić, zezwól na dostęp do mikrofonu i spróbuj ponownie.',
                ),
              ),
            ),
          );
        return;
      }
    }

    final outcome = await _mutes.toggle(
      roomId: roomId,
      isOperationCurrent: () => _isCurrentSession(roomId, generation),
    );
    if (!mounted || !_isCurrentSession(roomId, generation)) return;
    final copy = AppLocalizations.of(context);
    switch (outcome) {
      case RoomMuteOutcome.applied:
      case RoomMuteOutcome.busy:
      // The player disappears on its own once the stale session disconnects.
      case RoomMuteOutcome.sessionEnded:
        break;
      case RoomMuteOutcome.mutedLocally:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                copy.text(
                  "You're muted. Room status couldn't sync; try again.",
                  'Mikrofon jest wyciszony. Nie udało się zsynchronizować statusu pokoju — spróbuj ponownie.',
                ),
              ),
            ),
          );
      case RoomMuteOutcome.failed:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                copy.text(
                  'Could not change microphone state. Try again.',
                  'Nie udało się zmienić stanu mikrofonu. Spróbuj ponownie.',
                ),
              ),
            ),
          );
    }
  }

  Future<void> _leaveOrEnd() async {
    final roomId = _watchedRoomId;
    if (roomId == null) return;
    final generation = _sessionGeneration;
    if (_roomAuthority != _RoomAuthorityStatus.resolved) {
      await _resolveHost(roomId, generation);
      if (!mounted || !_isCurrentSession(roomId, generation)) return;
    }
    final authorityUncertain = _roomAuthority != _RoomAuthorityStatus.resolved;
    if (_hostEndsNow || authorityUncertain) {
      final confirmed = await _confirmEnd(
        authorityUncertain: authorityUncertain,
      );
      // The dialog belongs to the session captured above. A remote end can
      // replace that session while it is open; a stale confirmation must
      // never disconnect the new room that now owns VoiceCallService.
      if (confirmed != true || !_isCurrentSession(roomId, generation)) return;
    }
    if (!_isCurrentSession(roomId, generation)) return;
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

  NavigatorState? _endConfirmationNavigator;
  bool _endConfirmationOpen = false;

  Future<bool?> _confirmEnd({bool authorityUncertain = false}) async {
    if (_endConfirmationOpen) return false;
    _endConfirmationOpen = true;
    _endConfirmationNavigator = Navigator.of(context, rootNavigator: true);
    try {
      return await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) {
          final palette = dialogContext.appPalette;
          final colorScheme = Theme.of(dialogContext).colorScheme;
          final copy = AppLocalizations.of(dialogContext);
          return AlertDialog(
            backgroundColor: palette.surfaceRaised,
            title: Text(
              authorityUncertain
                  ? copy.text(
                      'Leave or end room?',
                      'Opuścić czy zakończyć pokój?',
                    )
                  : copy.text('End room?', 'Zakończyć pokój?'),
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Text(
              authorityUncertain
                  ? copy.text(
                      'Room authority could not be verified. Leaving may end '
                          'this live session if you are its host.',
                      'Nie udało się potwierdzić uprawnień w pokoju. Jeśli jesteś gospodarzem, wyjście może zakończyć sesję na żywo.',
                    )
                  : copy.text(
                      'You are the host. Leaving can end this live session for '
                          'everyone still inside.',
                      'Jesteś gospodarzem. Wyjście może zakończyć sesję na żywo dla wszystkich osób w pokoju.',
                    ),
              style: TextStyle(color: palette.textSecondary, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                style: TextButton.styleFrom(foregroundColor: palette.focus),
                child: Text(copy.text('Cancel', 'Anuluj')),
              ),
              FilledButton(
                key: const ValueKey('mini-player-end-confirm'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                ),
                child: Text(
                  authorityUncertain
                      ? copy.text('Leave anyway', 'Wyjdź mimo to')
                      : copy.text('End room', 'Zakończ pokój'),
                ),
              ),
            ],
          );
        },
      );
    } finally {
      _endConfirmationOpen = false;
      _endConfirmationNavigator = null;
    }
  }

  void _dismissEndConfirmationIfOpen() {
    if (!_endConfirmationOpen) return;
    _endConfirmationNavigator?.maybePop();
  }

  // ---------------------------------------------------------- expanded chat

  Future<void> _expandChat() async {
    final roomId = _watchedRoomId;
    if (roomId == null || _expandedOpen) return;
    final generation = _sessionGeneration;
    setState(() {
      _newCount = 0;
      _expandedOpen = true;
    });
    // Chat moderation must be based on resolved room authority. Without this
    // gate, a host who expanded during the initial lookup received a frozen
    // participant-only surface until they closed and reopened it.
    if (_roomAuthority != _RoomAuthorityStatus.resolved) {
      await _resolveHost(roomId, generation);
      if (!mounted || !_isCurrentSession(roomId, generation)) return;
    }
    if (_lastLayoutIsDock) {
      _openDesktopChatOverlay(roomId, generation);
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          AppLocalizations.of(
            context,
          ).text('Room chat expanded', 'Czat pokoju rozwinięty'),
          Directionality.of(context),
        ),
      );
      return;
    }
    _mobileSheetOpen = true;
    _mobileSheetGeneration = generation;
    await showExpandedMiniChatSheet(
      context,
      roomId: roomId,
      // TRUE host status: this governs the chat surface's moderation
      // powers, not the destructive label — a persistent-room host still
      // moderates their chat even though their tap merely leaves.
      isHost: _isHost,
      service: _rooms,
      onRouteCreated: (route) {
        if (_mobileSheetGeneration == generation) {
          _mobileSheetRoute = route;
        }
      },
      onMessageActionsRouteChanged: (route) =>
          _trackChatAuxiliaryRoute(route, generation),
    );
    if (_mobileSheetGeneration == generation) {
      _mobileSheetOpen = false;
      _mobileSheetRoute = null;
      _mobileSheetGeneration = null;
    }
    if (_isCurrentSession(roomId, generation)) {
      setState(() {
        _expandedOpen = false;
        _newCount = 0;
      });
    } else if (!mounted) {
      _expandedOpen = false;
    }
  }

  ModalBottomSheetRoute<void>? _mobileSheetRoute;
  bool _mobileSheetOpen = false;
  int? _mobileSheetGeneration;
  ModalBottomSheetRoute<CompactRoomMoreAction>? _mobileActionsRoute;
  bool _mobileActionsOpen = false;
  int? _mobileActionsGeneration;
  ModalBottomSheetRoute<void>? _chatAuxiliaryRoute;
  int? _chatAuxiliaryGeneration;

  Future<void> _openMobileActions() async {
    final roomId = _watchedRoomId;
    if (roomId == null || _mobileActionsOpen) return;
    final generation = _sessionGeneration;
    _mobileActionsOpen = true;
    _mobileActionsGeneration = generation;
    CompactRoomMoreAction? action;
    try {
      if (_roomAuthority != _RoomAuthorityStatus.resolved) {
        await _resolveHost(roomId, generation);
        if (!mounted || !_isCurrentSession(roomId, generation)) return;
      }
      action = await showCompactRoomMoreSheet(
        context,
        endsRoomNow: _hostEndsNow,
        authorityResolved: _roomAuthority == _RoomAuthorityStatus.resolved,
        onRouteCreated: (route) {
          if (_mobileActionsGeneration == generation) {
            _mobileActionsRoute = route;
          }
        },
      );
    } finally {
      // Clear the route handle BEFORE running Return/Leave. Leave disconnects
      // the session synchronously; keeping the handle alive until then would
      // make the session-change cleanup pop the root route after this sheet's
      // own reverse transition had already completed.
      if (_mobileActionsGeneration == generation) {
        _mobileActionsOpen = false;
        _mobileActionsRoute = null;
        _mobileActionsGeneration = null;
      }
    }
    if (!_isCurrentSession(roomId, generation)) return;
    switch (action) {
      case CompactRoomMoreAction.returnToRoom:
        await _returnToRoom();
        break;
      case CompactRoomMoreAction.leave:
        await _leaveOrEnd();
        break;
      case null:
        break;
    }
  }

  /// Mirrors the expanded-chat teardown: a remotely ended session cannot
  /// leave a controls sheet mounted over a mini player that no longer exists.
  void _dismissMobileActionsIfOpen() {
    final route = _mobileActionsRoute;
    if (_mobileActionsOpen && route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
    _mobileActionsOpen = false;
    _mobileActionsRoute = null;
    _mobileActionsGeneration = null;
  }

  /// A remote room end while the MOBILE sheet is open: the desktop overlay
  /// is removed by session change, but a modal sheet is a real route and
  /// stayed on the navigator with a live composer for a dead room. While
  /// the sheet is open it is modal (taps elsewhere are blocked), so the
  /// top-of-stack pop below can only ever remove the sheet itself or a
  /// dialog stacked over it by the same surface — both belong to the dead
  /// session.
  void _dismissMobileSheetIfOpen() {
    final route = _mobileSheetRoute;
    if (_mobileSheetOpen && route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
    _mobileSheetOpen = false;
    _mobileSheetRoute = null;
    _mobileSheetGeneration = null;
  }

  void _trackChatAuxiliaryRoute(
    ModalBottomSheetRoute<void>? route,
    int generation,
  ) {
    if (route == null) {
      if (_chatAuxiliaryGeneration == generation) {
        _chatAuxiliaryRoute = null;
        _chatAuxiliaryGeneration = null;
      }
      return;
    }
    if (generation != _sessionGeneration) return;
    _chatAuxiliaryRoute = route;
    _chatAuxiliaryGeneration = generation;
  }

  void _dismissChatAuxiliaryRouteIfOpen() {
    final route = _chatAuxiliaryRoute;
    _chatAuxiliaryRoute = null;
    _chatAuxiliaryGeneration = null;
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
  }

  void _openDesktopChatOverlay(String roomId, int generation) {
    _removeDesktopChatOverlay();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        final copy = AppLocalizations.of(overlayContext);
        final screen = MediaQuery.sizeOf(overlayContext);
        final width = math.min(440.0, screen.width - 32);
        final height = math.min(560.0, screen.height * .68);
        return FocusScope.withExternalFocusNode(
          focusScopeNode: _desktopChatFocusScope,
          autofocus: true,
          child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: BlockSemantics(
              child: Stack(
                children: [
                  // Tap anywhere outside: collapse. The chat is a popover,
                  // not a route — RTC and shell state stay untouched.
                  Positioned.fill(
                    child: Semantics(
                      button: true,
                      label: copy.text(
                        'Close room chat',
                        'Zamknij czat pokoju',
                      ),
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
                        // Overlay entries sit outside any route's Material;
                        // the chat surface (TextField included) needs one.
                        // The outer modal FocusScope traps Tab/Shift-Tab and
                        // Escape.
                        child: Material(
                          color: Colors.transparent,
                          child: ExpandedMiniChat(
                            roomId: roomId,
                            // True host status — moderation powers, not the
                            // destructive label.
                            isHost: _isHost,
                            service: _rooms,
                            onMessageActionsRouteChanged: (route) =>
                                _trackChatAuxiliaryRoute(route, generation),
                            onCollapse: _collapseExpandedChat,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    _desktopChatOverlay = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_desktopChatOverlay, entry)) {
        _desktopChatFocusScope.requestFocus();
      }
    });
  }

  void _removeDesktopChatOverlay() {
    _desktopChatOverlay?.remove();
    _desktopChatOverlay = null;
    if (_desktopExpandFocusNode.context != null &&
        _desktopExpandFocusNode.canRequestFocus) {
      _desktopExpandFocusNode.requestFocus();
    }
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
    final projection = _projection;
    final roomId = projection.roomId;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final activePlayer = roomId == null
        ? null
        : KeyedSubtree(
            key: const ValueKey('active-room-player'),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDock = constraints.maxWidth >= _dockBreakpoint;
                _lastLayoutIsDock = isDock;

                final Widget surface;
                if (isDock) {
                  // Desktop intentionally keeps the established four-zone
                  // dock. The YO clone hand-off is mobile-only because the
                  // desktop shell has no central floating YO action.
                  surface = _DockSurface(
                    info: ActiveRoomInfo(
                      roomName: projection.roomName,
                      reconnecting: projection.reconnecting,
                      participantCount: projection.participantCount,
                      onReturnToRoom: () => unawaited(_returnToRoom()),
                    ),
                    preview: LiveChatPreview(
                      latest: _latest,
                      newCount: _newCount,
                      onExpand: () => unawaited(_expandChat()),
                      expandFocusNode: _desktopExpandFocusNode,
                    ),
                    controls: ActiveRoomControls(
                      micState: projection.micState,
                      muteBusy: _muteBusy,
                      isHost: _hostEndsNow,
                      authorityResolved:
                          _roomAuthority == _RoomAuthorityStatus.resolved,
                      onToggleMute: () => unawaited(_toggleMute()),
                      onReturnToRoom: () => unawaited(_returnToRoom()),
                      onLeave: () => unawaited(_leaveOrEnd()),
                    ),
                  );
                } else {
                  surface = CompactActiveRoomBar(
                    roomName: projection.roomName,
                    reconnecting: projection.reconnecting,
                    participantCount: projection.participantCount,
                    latest: _latest,
                    newCount: _newCount,
                    micState: projection.micState,
                    muteBusy: _muteBusy,
                    onReturnToRoom: () => unawaited(_returnToRoom()),
                    onExpandChat: () => unawaited(_expandChat()),
                    onToggleMute: () => unawaited(_toggleMute()),
                    onMore: () => unawaited(_openMobileActions()),
                  );
                }

                final player = KeyedSubtree(
                  key: const ValueKey('mini-player'),
                  child: SafeArea(top: false, bottom: false, child: surface),
                );

                // Both layouts honor the user's full system text scale. The
                // one-line identity and metadata fields ellipsize, while the
                // dock's intrinsic height is allowed to grow at 200%.
                return player;
              },
            ),
          );

    final transitioned = reduceMotion
        ? activePlayer ?? const SizedBox.shrink()
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            reverseDuration: const Duration(milliseconds: 240),
            switchInCurve: const Cubic(.22, 1, .36, 1),
            switchOutCurve: const Cubic(.22, 1, .36, 1),
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [...previousChildren, ?currentChild],
            ),
            transitionBuilder: (child, animation) {
              if (child.key != const ValueKey('active-room-player')) {
                return child;
              }
              return _ActiveRoomContinuityTransition(
                animation: animation,
                child: child,
              );
            },
            child:
                activePlayer ??
                const SizedBox.shrink(key: ValueKey('inactive-room-player')),
          );

    // The target is outside AnimatedSwitcher so an interrupted reverse can
    // briefly retain two visual surfaces without ever registering two
    // leaders for the same LayerLink.
    return CompositedTransformTarget(link: _dockLink, child: transitioned);
  }
}

enum _RoomAuthorityStatus { checking, resolved, unavailable }

@immutable
class _RoomBarProjection {
  const _RoomBarProjection({
    required this.roomId,
    required this.roomName,
    required this.status,
    required this.participantCount,
    required this.micState,
    required this.voiceMuteBusy,
  });

  final String? roomId;
  final String roomName;
  final VoiceCallStatus status;
  final int participantCount;
  final MicState micState;
  final bool voiceMuteBusy;

  bool get reconnecting => status != VoiceCallStatus.connected;

  @override
  bool operator ==(Object other) {
    return other is _RoomBarProjection &&
        other.roomId == roomId &&
        other.roomName == roomName &&
        other.status == status &&
        other.participantCount == participantCount &&
        other.micState == micState &&
        other.voiceMuteBusy == voiceMuteBusy;
  }

  @override
  int get hashCode => Object.hash(
    roomId,
    roomName,
    status,
    participantCount,
    micState,
    voiceMuteBusy,
  );
}

/// A safe visual equivalent of the reference's dock-to-room flight.
///
/// The shell owns the true YO geometry, so this view cannot measure both
/// endpoints without coupling navigation and RTC lifecycles. Instead the
/// non-interactive official mark starts just below this bar (over the central
/// dock area), rises toward the real bar's existing voice orb, gradually gains
/// the orb material/waveform, and then yields to the one production surface.
/// No controls or session data are duplicated.
class _ActiveRoomContinuityTransition extends StatelessWidget {
  const _ActiveRoomContinuityTransition({
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  static const Curve _curve = Cubic(.22, 1, .36, 1);

  static double _interval(double value, double begin, double end) {
    return ((value - begin) / (end - begin)).clamp(0, 1).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 880;
        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final raw = animation.value.clamp(0, 1).toDouble();
            final shell = _curve.transform(_interval(raw, .08, 1));
            final content = _curve.transform(_interval(raw, .30, 1));
            final orbMorph = _curve.transform(_interval(raw, .30, .78));
            final cloneFade = _curve.transform(_interval(raw, .70, .96));
            final cloneOpacity = mobile ? 1 - cloneFade : 0.0;

            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                ClipRect(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    heightFactor: .14 + (.86 * shell),
                    child: IgnorePointer(
                      ignoring: raw < .985,
                      child: Transform.scale(
                        alignment: Alignment.bottomCenter,
                        scale: .96 + (.04 * shell),
                        child: ClipRect(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            widthFactor: .14 + (.86 * shell),
                            child: Opacity(opacity: content, child: child),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (mobile && cloneOpacity > 0)
                  Positioned(
                    left: Tween<double>(
                      begin: (constraints.maxWidth / 2) - 34,
                      end: 21,
                    ).transform(shell),
                    bottom: Tween<double>(begin: -56, end: 18).transform(shell),
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: RepaintBoundary(
                          child: Opacity(
                            key: const ValueKey(
                              'mini-player-continuity-logo-clone',
                            ),
                            opacity: cloneOpacity,
                            child: _MorphingRoomOrb(
                              progress: orbMorph,
                              palette: palette,
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
      },
    );
  }
}

class _MorphingRoomOrb extends StatelessWidget {
  const _MorphingRoomOrb({required this.progress, required this.palette});

  final double progress;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final size = 68 - (30 * progress);
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(
            Colors.transparent,
            palette.surfaceRaised,
            progress,
          ),
          border: Border.all(
            color: Color.lerp(
              Colors.transparent,
              AppColors.voice.withValues(alpha: .72),
              progress,
            )!,
          ),
          boxShadow: progress <= 0
              ? const []
              : [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: .28 * progress),
                    blurRadius: 16 * progress,
                  ),
                ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: 1 - progress,
              child: Image.asset(
                'assets/images/yo-voice-favicon-512.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            Center(
              child: Opacity(
                opacity: progress,
                child: Icon(
                  Icons.graphic_eq_rounded,
                  color: Color.lerp(
                    Colors.transparent,
                    palette.textPrimary,
                    progress,
                  ),
                  size: 21,
                ),
              ),
            ),
          ],
        ),
      ),
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

class _ZoneDivider extends StatelessWidget {
  const _ZoneDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      color: AppImmersiveColors.divider,
    );
  }
}

BoxDecoration _playerDecoration({required double radius}) {
  return BoxDecoration(
    color: Color.lerp(
      AppImmersiveColors.surface,
      AppImmersiveColors.background,
      .25,
    ),
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
