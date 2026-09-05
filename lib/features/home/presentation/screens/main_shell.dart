import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/navigation/mobile_destination_history.dart';
import 'package:yovoice/core/theme/app_palette.dart';

import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/screens/verify_email_screen.dart';
import 'package:yovoice/features/auth/presentation/widgets/email_verification_banner.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_overview_screen.dart';
import 'package:yovoice/features/discover/presentation/screens/discover_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/followed_creators_card.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/presentation/screens/follow_list_screen.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/features/home/presentation/screens/home_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/premium_desktop_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/sponsored_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/voice_trending_card.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_preserving_tab_transition.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/presentation/widgets/yo_top_notification_host.dart';
import 'package:yovoice/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:yovoice/features/onboarding/data/guided_onboarding_progress.dart';
import 'package:yovoice/features/onboarding/presentation/guided_onboarding_tour.dart';
import 'package:yovoice/features/permissions/data/permission_readiness_service.dart';
import 'package:yovoice/features/permissions/presentation/permission_setup_sheet.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/premium_gates.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_screen.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/active_conversation_registry.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';
import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/moments/data/models/moment_chain.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_sheet.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_viewer.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_type_selector_screen.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_mini_bar.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/navigation/yo_edge_back_gesture.dart';

@visibleForTesting
bool shouldPresentIncomingMessageOverlay({
  required int selectedIndex,
  required String conversationId,
  required ActiveConversationRegistry activeConversations,
}) => selectedIndex != 1 && !activeConversations.contains(conversationId);

/// Sequences the automatic guide after startup-owned native modal surfaces.
/// Readiness failures are intentionally fail-open: a broken optional prompt
/// must not strand a new account or make guide eligibility network-dependent.
@visibleForTesting
Future<bool> evaluateGuidedOnboardingAfterReadiness({
  Future<void>? readiness,
  required Future<bool> Function() evaluate,
}) async {
  try {
    await (readiness ?? Future<void>.value());
  } catch (error) {
    debugPrint('Guided onboarding readiness failed open: $error');
  }
  return evaluate();
}

@visibleForTesting
bool isSafeInitialRoomLinkId(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value);

/// Serializes presentation of the More menu without blocking the destination
/// subsequently opened from it.
///
/// Public only so the navigation regression suite can deterministically pin
/// the same-frame double-tap contract without booting Firebase-backed
/// [MainShell].
final class MoreMenuTransitionGuard {
  bool _active = false;

  @visibleForTesting
  bool get isActive => _active;

  Future<T?> run<T>(Future<T?> Function() present) async {
    if (_active) return null;
    _active = true;
    try {
      return await present();
    } finally {
      _active = false;
    }
  }
}

/// Keeps automatic onboarding and rapid Settings replays on one modal flight.
/// The flag is acquired before the first await and released only after the
/// dialog route's reverse transition completes.
final class GuidedOnboardingPresentationGuard {
  bool _active = false;

  @visibleForTesting
  bool get isActive => _active;

  Future<T?> run<T>(Future<T?> Function() present) async {
    if (_active) return null;
    _active = true;
    try {
      return await present();
    } finally {
      _active = false;
    }
  }
}

class MainShell extends StatefulWidget {
  const MainShell({
    this.onboardingProgress,
    this.onboardingUserId,
    this.onboardingCreationTime,
    this.onboardingLastSignInTime,
    this.onboardingReadiness,
    this.permissionReadiness,
    super.key,
  });

  /// Optional seams keep the account gate deterministic without making the
  /// rest of this Firebase-backed shell test-only or globally stateful.
  @visibleForTesting
  final GuidedOnboardingProgress? onboardingProgress;

  @visibleForTesting
  final String? onboardingUserId;

  @visibleForTesting
  final DateTime? onboardingCreationTime;

  @visibleForTesting
  final DateTime? onboardingLastSignInTime;

  /// Resolves after non-interactive notification startup and any cold-start
  /// notification route have settled. The shell and manual replay remain
  /// immediate.
  @visibleForTesting
  final Future<void>? onboardingReadiness;

  @visibleForTesting
  final PermissionReadinessService? permissionReadiness;

  static const double desktopBreakpoint = 1100;

  /// Stable content identities are independent of the mobile dock's visual
  /// order: Home, Rooms, Chats, Moments. Friends remains a retained hidden
  /// slot reached from Home and More; desktop-only destinations return Home
  /// when a viewport switches to the mobile shell.
  @visibleForTesting
  static int mobileIndexFor(int index) =>
      const {0, 1, 2, 3, 5}.contains(index) ? index : 0;

  @visibleForTesting
  static int mobileNavigationOrder(int index) => switch (index) {
    0 => 0,
    3 => 1,
    1 => 2,
    5 => 3,
    _ => 4,
  };

  /// One layout predicate for rendering AND navigation. A wide viewport can
  /// still need the mobile shell when browser zoom leaves too little logical
  /// height for the fixed rail; menu presentation and content-slot routing
  /// must follow that same decision.
  @visibleForTesting
  static bool usesDesktopLayout(Size viewport) =>
      viewport.width >= desktopBreakpoint &&
      viewport.height >= DesktopSidebar.minimumSupportedHeight;

  /// DESKTOP content slots beyond the three shared dock tabs, keyed by
  /// IndexedStack index. Every More destination EXCEPT the two below
  /// must own a slot, so selecting any of them swaps the centre of the
  /// SAME shell instead of pushing a route over it:
  ///
  ///  * `friends` is primary tab index 2, not a popover destination;
  ///  * `profile` pushes on purpose (it keeps a real Back button and is
  ///    opened from the profile card, not the rail).
  ///
  /// Staff Center's absence from this map was the desktop page-shift
  /// bug: with no slot it fell through to the pushed MoreDestinationHost,
  /// which mounts a SECOND sidebar (profile card and all) and animates
  /// the whole viewport — exactly the "page moved" symptom — while
  /// Moderation, one entry up, swapped in place. Public so the
  /// navigation regression suite can pin this contract.
  @visibleForTesting
  static const Map<int, MoreDestination> desktopSlots = {
    3: MoreDestination.discover,
    4: MoreDestination.notifications,
    5: MoreDestination.moments,
    6: MoreDestination.clubs,
    7: MoreDestination.creatorStudio,
    8: MoreDestination.achievements,
    9: MoreDestination.settings,
    10: MoreDestination.moderation,
    11: MoreDestination.staffCenter,
    12: MoreDestination.findCreators,
  };

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin, RouteAware, WidgetsBindingObserver {
  final MessageService _messageService = MessageService.live;
  final RoomService _roomService = RoomService();
  final AuthService _authService = AuthService();
  final EntitlementService _entitlementService = EntitlementService();
  final MoreMenuTransitionGuard _moreMenuTransition = MoreMenuTransitionGuard();
  final GuidedOnboardingPresentationGuard _onboardingPresentation =
      GuidedOnboardingPresentationGuard();
  bool _handledInitialRoomLink = false;

  late final GuidedOnboardingProgress _onboardingProgress;
  late final PermissionReadinessService _permissionReadiness;
  late final String _onboardingUserId;
  late final DateTime? _onboardingCreationTime;
  late final DateTime? _onboardingLastSignInTime;
  ModalRoute<void>? _observedShellRoute;
  bool _autoOnboardingChecked = false;
  bool _onboardingPending = false;
  bool get _onboardingOpen => _onboardingPresentation.isActive;
  bool _permissionSetupChecked = false;
  bool _permissionSetupPending = false;
  bool _permissionSetupOpen = false;

  final Map<GuidedOnboardingTarget, GlobalKey> _onboardingAnchors = {
    for (final target in GuidedOnboardingTarget.values)
      target: GlobalKey(debugLabel: 'guided-onboarding-${target.name}'),
  };

  Timer? _verificationCheckTimer;
  StreamSubscription<User?>? _verificationUserSubscription;
  bool _verificationCheckInFlight = false;
  bool _showVerificationBanner =
      FirebaseAuth.instance.currentUser?.emailVerified == false;

  late final Stream<List<Conversation>> _conversationsStream;
  StreamSubscription<List<Conversation>>? _conversationSubscription;

  final Map<String, int> _previousUnreadCounts = <String, int>{};

  final _messageNotificationSource = Object();
  YoTopNotificationController? _messageNotificationController;

  int _selectedIndex = 0;
  final _mobileHistory = MobileDestinationHistory();
  bool? _lastDesktopLayout;
  int _previousSelectedIndex = 0;
  int _tabDirection = 1;
  int _unreadConversationCount = 0;
  final ValueNotifier<int> _unreadConversationCountListenable =
      ValueNotifier<int>(0);
  bool _hasInitialConversationSnapshot = false;
  bool _isMoreMenuActive = false;
  int _hostedDestinationDepth = 0;

  bool get _hostedDestinationActive => _hostedDestinationDepth > 0;

  /// Desktop sidebar badge only — the same routed count the bell shows.
  int _unreadNotificationCount = 0;
  final ValueNotifier<int> _unreadNotificationCountListenable =
      ValueNotifier<int>(0);
  StreamSubscription<int>? _notificationCountSubscription;

  SubscriptionEntitlements _entitlements = SubscriptionEntitlements.free;
  StreamSubscription<SubscriptionEntitlements>? _entitlementSubscription;

  // Keep stable content identities when the mobile visual order changes.
  // Friends remains retained at slot 2, while Rooms promotes Discover's
  // existing slot 3 instead of renumbering desktop destinations.
  static const List<Widget> _screens = [
    HomeScreen(),
    MessagesScreen(),
    FriendsScreen(isRootTab: true),
  ];

  /// Moments is now a PRIMARY destination on both form factors, but it
  /// keeps the desktop slot it always had. Promoting it by inserting a
  /// new entry into `_screens` would renumber ten constants across four
  /// switch statements and break the ADR-047 contract test's contiguity
  /// assertion — to buy nothing. The dock maps its fourth slot onto this
  /// index instead, and `MainShell.desktopSlots` is untouched.
  static const int _momentsSlot = 5;
  static const int _discoverSlot = 3;
  static const int _notificationsSlot = 4;
  static const int _findCreatorsSlot = 12;

  /// DESKTOP content slots beyond the three shared dock tabs. Every
  /// desktop destination — rail items AND everything chosen from the
  /// More popover — is one of these, so selecting any of them swaps the
  /// centre of the SAME shell instead of pushing a route over it.
  static const Map<int, MoreDestination> _slotDestinations =
      MainShell.desktopSlots;

  /// The notifications FEED (the bell) is its own screen rather than a
  /// MoreDestination — Alerts (preferences) is the one in the popover.
  static const int _slotCount = 13;

  /// Slots are built on FIRST visit and then kept alive, so switching
  /// back is instant and scroll position survives — without mounting
  /// ten screens (and their Firestore listeners) at startup.
  final Map<int, Widget> _builtSlots = <int, Widget>{};

  /// The Moments slot plays audio, and `IndexedStack` keeps hidden
  /// children fully built without notifying them — so leaving the tab
  /// would otherwise keep playing from an invisible screen. The slot is
  /// built once and cached, so the flag has to be a listenable the
  /// screen subscribes to rather than a constructor argument.
  final ValueNotifier<bool> _momentsVisible = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _homeVisible = ValueNotifier<bool>(true);
  final ScrollController _roomsScrollController = ScrollController();

  Widget _buildSlot(int index) {
    if (index == _discoverSlot) {
      return Builder(
        builder: (context) {
          final mobile = !MainShell.usesDesktopLayout(
            MediaQuery.sizeOf(context),
          );
          return DiscoverScreen(
            isRootTab: true,
            asRoomsDestination: mobile,
            scrollController: _roomsScrollController,
            onCreateRoom: mobile ? () => unawaited(_openCreateRoom()) : null,
            // A cached Rooms slot also survives on desktop. Only the active
            // layout owns this key; the desktop rail owns Create there.
            createRoomKey: mobile
                ? _onboardingAnchors[GuidedOnboardingTarget.create]
                : null,
          );
        },
      );
    }
    if (index == _notificationsSlot) {
      return const NotificationsScreen(isRootTab: true);
    }
    if (index == _momentsSlot) {
      return MomentsScreen(
        isRootTab: true,
        isVisible: _momentsVisible,
        onOpenDetail: (moment) => unawaited(_openMomentDetail(moment)),
      );
    }
    final destination = _slotDestinations[index];
    if (destination == null) return const SizedBox.shrink();
    return moreDestinationScreen(
      destination,
      isRootTab: true,
      onReplayGuidedOnboarding: _replayGuidedOnboarding,
    );
  }

  List<Widget> _slotChildren({
    required bool isDesktop,
    Widget? desktopHomeTrailing,
  }) => [
    for (var index = 0; index < _slotCount; index++)
      if (index == 0)
        // Each platform gets its own Home composition; everything else
        // in the shell is shared.
        (isDesktop
            ? _desktopHome(trailingContent: desktopHomeTrailing)
            : _mobileHome)
      else if (index < _screens.length)
        _screens[index]
      else
        _builtSlots[index] ?? const SizedBox.shrink(),
  ];

  /// Mobile Home — the same hierarchy as the desktop Pulse Home at phone
  /// proportions. The hub bar, its five destinations and every callback
  /// below are the shell's existing ones; this only changes what Home
  /// renders inside slot 0.
  Widget get _mobileHome => MobileHome(
    isVisible: _homeVisible,
    unreadNotificationCount: _unreadNotificationCount,
    onOpenRoom: (room) => unawaited(_openRoom(room)),
    onOpenDiscover: () =>
        unawaited(_openMoreDestination(MoreDestination.discover)),
    onOpenFindCreators: () =>
        unawaited(_openMoreDestination(MoreDestination.findCreators)),
    onOpenFriends: () => _onDestinationSelected(2),
    onOpenNotifications: () => unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
      ),
    ),
    onOpenProfile: () => unawaited(_openProfile()),
    onCreateMoment: _openCreateMoment,
    onCreateRoom: () => unawaited(_openCreateRoom()),
    onOpenMoment: (moment) => unawaited(_openMoment(moment)),
    onOpenChain: (moments) => unawaited(_openMomentChain(moments)),
    onOpenComments: (moment) => unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => MomentCommentsScreen(moment: moment),
        ),
      ),
    ),
    onOpenConversation: (conversation) =>
        unawaited(_openConversation(conversation)),
    onSeeAllChats: () => _onDestinationSelected(1),
  );

  /// Desktop Home. Every tab-level destination below goes through
  /// [_onDestinationSelected] — the same content-slot swap the rail
  /// uses, so the sidebar and profile card never rebuild. The three that
  /// push (a room, a chat, a club) are the flows that already own a
  /// full-screen route everywhere else in the app.
  Widget _desktopHome({Widget? trailingContent}) => DesktopHome(
    isVisible: _homeVisible,
    currentUserId: _currentUserId,
    onOpenRoom: (room) => unawaited(_openRoom(room)),
    onSeeAllRooms: () => _onDestinationSelected(_discoverSlot),
    onFindCreators: () => _onDestinationSelected(_findCreatorsSlot),
    onViewAllFriends: () => _onDestinationSelected(2),
    onStartRoom: () => unawaited(_openCreateRoom()),
    onOpenMoment: (moment) => unawaited(_openMoment(moment)),
    onOpenChain: (moments) => unawaited(_openMomentChain(moments)),
    onCreateMoment: _openCreateMoment,
    onSeeAllMoments: () =>
        unawaited(_openMoreDestination(MoreDestination.moments)),
    onOpenConversation: (conversation) =>
        unawaited(_openConversation(conversation)),
    onOpenClub: (club) => unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ClubOverviewScreen(clubId: club.id),
        ),
      ),
    ),
    onSeeAllChats: () => _onDestinationSelected(1),
    onOpenClubs: () => unawaited(_openMoreDestination(MoreDestination.clubs)),
    trailingContent: trailingContent,
  );

  /// Opens an existing conversation in the existing ChatScreen — the same
  /// arguments the Chats screen passes, so read receipts, presence and
  /// permissions behave identically wherever a chat is opened from.
  Future<void> _openConversation(Conversation conversation) async {
    final otherUserId = conversation.otherUserId(_currentUserId);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          conversationId: conversation.id,
          otherUserId: otherUserId,
          otherDisplayName: conversation.displayNameFor(otherUserId),
          otherEmail: conversation.emailFor(otherUserId),
          otherPhotoUrl: conversation.photoUrlFor(otherUserId),
        ),
      ),
    );
  }

  /// Entering a room is the existing full-screen room flow (identical to
  /// every other entry point); Home's own navigation never pushes.
  Future<void> _openRoom(VoiceRoom room) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => RoomEntryScreen(room: room)),
    );
  }

  /// Maps a More destination to its desktop slot, or null when it has
  /// none (Profile stays a pushed route: it has a real Back button and
  /// is opened from the profile card, not the rail).
  static int? _slotForDestination(MoreDestination destination) {
    for (final entry in _slotDestinations.entries) {
      if (entry.value == destination) return entry.key;
    }
    return null;
  }

  /// Mobile selects the stable Home/Rooms/Chats/Moments content identities.
  /// Other desktop-only slots fall back to Home on responsive resize.
  ///
  /// Friends (tab 2) is deliberately still reachable here even though it
  /// no longer owns a dock slot — mobile Home's "Your circle" selects it,
  /// and its state, scroll position and listeners stay alive in the
  /// IndexedStack. The dock renders no capsule while it is showing,
  /// rather than lighting a slot that is not where you are.
  static int _mobileIndexFor(int index) => MainShell.mobileIndexFor(index);

  int get _mobileIndex => _mobileIndexFor(_selectedIndex);

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  /// A hosted destination finishes its reverse transition asynchronously.
  /// Do not let a callback captured by the previous authenticated shell
  /// present private UI after logout or a principal switch has replaced the
  /// Navigator stack.
  bool _hostNavigationEpochIsCurrent() {
    return mounted && _currentUserId == _onboardingUserId;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final currentUser = FirebaseAuth.instance.currentUser;
    _onboardingProgress =
        widget.onboardingProgress ?? GuidedOnboardingProgress();
    _permissionReadiness =
        widget.permissionReadiness ?? PermissionReadinessService.instance;
    _onboardingUserId = widget.onboardingUserId ?? currentUser?.uid ?? '';
    _onboardingCreationTime =
        widget.onboardingCreationTime ?? currentUser?.metadata.creationTime;
    _onboardingLastSignInTime =
        widget.onboardingLastSignInTime ?? currentUser?.metadata.lastSignInTime;

    _conversationsStream = _messageService.watchConversations(
      includeArchived: true,
    );
    unawaited(_messageService.resumeOutbox());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prepareGuidedOnboarding());
    });

    _conversationSubscription = _conversationsStream.listen(
      _handleConversations,
      onError: (_) {
        // The Chats screen displays Firestore errors directly.
      },
    );

    _notificationCountSubscription = NotificationService()
        .watchUnreadCount()
        .listen(
          (count) {
            if (mounted && count != _unreadNotificationCount) {
              setState(() => _unreadNotificationCount = count);
              _unreadNotificationCountListenable.value = count;
            }
          },
          onError: (_) {
            // A badge is not worth surfacing an error for.
          },
        );

    try {
      _entitlementSubscription = _entitlementService
          .watchCurrentEntitlements()
          .listen(
            (entitlements) {
              if (mounted) setState(() => _entitlements = entitlements);
            },
            onError: (_) {
              if (mounted) {
                setState(() {
                  _entitlements = SubscriptionEntitlements.free;
                });
              }
            },
          );
    } catch (_) {
      // No verified subscription state means Premium destinations stay locked.
    }

    unawaited(_resolveStaffAccess());
    _verificationUserSubscription = FirebaseAuth.instance.userChanges().listen(
      _handleVerificationUser,
      onError: (_) {
        // The cached initial state and periodic reload remain available when
        // Firebase's user stream is temporarily unavailable.
      },
    );
    _setVerificationReminder(currentUser != null && !currentUser.emailVerified);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (identical(route, _observedShellRoute)) return;
    if (_observedShellRoute != null) {
      appRouteObserver.unsubscribe(this);
    }
    _observedShellRoute = route;
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  @override
  void didPopNext() {
    unawaited(_showPendingGuidedOnboarding());
    unawaited(_showPendingPermissionSetup());
    unawaited(_checkVerification());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The verification link is commonly opened in Mail or a browser. Check
      // immediately when YO Voice returns instead of waiting for the timer.
      unawaited(_checkVerification());
    }
  }

  Future<void> _prepareGuidedOnboarding() async {
    // A valid cold-start room link owns the first route. Await its full visit
    // so the tutorial never obscures room controls or starts underneath it.
    await _openInitialRoomLink();
    if (!mounted) return;

    // Cold-start notification routing owns the first destination. Permission
    // inspection is non-interactive, and token/network registration never
    // becomes part of this startup barrier.
    final eligible = await evaluateGuidedOnboardingAfterReadiness(
      readiness: widget.onboardingReadiness,
      evaluate: () => _onboardingProgress.shouldAutoStart(
        userId: _onboardingUserId,
        creationTime: _onboardingCreationTime,
        lastSignInTime: _onboardingLastSignInTime,
      ),
    );
    if (!mounted || _autoOnboardingChecked) return;
    _autoOnboardingChecked = true;
    if (eligible) {
      _onboardingPending = true;
      await _showPendingGuidedOnboarding();
      return;
    }
    await _preparePermissionSetup();
  }

  Future<void> _showPendingGuidedOnboarding() async {
    if (!_onboardingPending || _onboardingOpen || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final outcome = await _presentGuidedOnboarding();
    if (!mounted || outcome == null) return;
    _onboardingPending = false;
    try {
      await _onboardingProgress.markDismissed(
        _onboardingUserId,
        outcome: outcome,
      );
    } catch (error) {
      // The tour must never trap someone because local preferences cannot be
      // written. A future launch may offer it again, while this session stays
      // uninterrupted.
      debugPrint('Guided onboarding progress could not be saved: $error');
    }
    await _preparePermissionSetup();
  }

  Future<void> _preparePermissionSetup() async {
    if (_permissionSetupChecked || !mounted) return;
    final shouldOffer = await _permissionReadiness.shouldOfferAutomatically(
      _onboardingUserId,
    );
    if (!mounted || _permissionSetupChecked) return;
    _permissionSetupChecked = true;
    if (!shouldOffer) return;
    _permissionSetupPending = true;
    await _showPendingPermissionSetup();
  }

  Future<void> _showPendingPermissionSetup() async {
    if (!_permissionSetupPending ||
        _permissionSetupOpen ||
        _onboardingPending ||
        _onboardingOpen ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final stillPending = await _permissionReadiness.shouldOfferAutomatically(
      _onboardingUserId,
    );
    if (!mounted ||
        !stillPending ||
        !_permissionSetupPending ||
        _permissionSetupOpen ||
        _onboardingPending ||
        _onboardingOpen ||
        ModalRoute.of(context)?.isCurrent != true) {
      if (!stillPending) _permissionSetupPending = false;
      return;
    }
    _permissionSetupOpen = true;
    try {
      final outcome = await showPermissionSetupSheet(
        context,
        userId: _onboardingUserId,
        service: _permissionReadiness,
      );
      if (mounted && outcome != null) _permissionSetupPending = false;
    } finally {
      _permissionSetupOpen = false;
    }
  }

  Future<GuidedOnboardingOutcome?> _presentGuidedOnboarding() async {
    if (!mounted) return null;
    return _onboardingPresentation.run(() async {
      if (ModalRoute.of(context)?.isCurrent != true) return null;
      await _waitForShellTransition();
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return null;

      await _prepareGuidedOnboardingLayout(
        MainShell.usesDesktopLayout(MediaQuery.sizeOf(context)),
      );
      _removeMessageOverlay();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return null;

      return showGuidedOnboardingTour(
        context,
        anchors: _onboardingAnchors,
        desktop: MainShell.usesDesktopLayout(MediaQuery.sizeOf(context)),
        desktopLayoutFor: MainShell.usesDesktopLayout,
        onLayoutChanged: (desktop) =>
            unawaited(_prepareGuidedOnboardingLayout(desktop)),
      );
    });
  }

  Future<void> _prepareGuidedOnboardingLayout(bool desktop) async {
    if (!mounted || !_onboardingOpen) return;
    // The mobile Create spotlight follows the real Rooms CTA, not the
    // removed centre-logo action. Desktop introduces its rail from Home.
    // Preparing either layout invokes no creation, entry or media permission.
    final tourIndex = desktop ? 0 : _discoverSlot;
    if (_selectedIndex != tourIndex) {
      _mobileHistory.resetTo(tourIndex);
      _onDestinationSelected(tourIndex, recordHistory: false);
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        !_onboardingOpen ||
        desktop != MainShell.usesDesktopLayout(MediaQuery.sizeOf(context))) {
      return;
    }
    if (!desktop && _roomsScrollController.hasClients) {
      // The Rooms slot is retained, including its scroll. Replay must reveal
      // the real CTA even after the user has browsed far down the live list.
      _roomsScrollController.jumpTo(0);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _waitForShellTransition() async {
    final animation = _observedShellRoute?.secondaryAnimation;
    if (animation == null || animation.status == AnimationStatus.dismissed) {
      return;
    }
    final settled = Completer<void>();
    late AnimationStatusListener listener;
    listener = (status) {
      if (status != AnimationStatus.dismissed || settled.isCompleted) return;
      animation.removeStatusListener(listener);
      settled.complete();
    };
    animation.addStatusListener(listener);
    if (animation.status == AnimationStatus.dismissed) {
      listener(animation.status);
    }
    await settled.future;
  }

  Future<void> _replayGuidedOnboarding() async {
    await _presentGuidedOnboarding();
  }

  Future<void> _replayGuidedOnboardingAfter(
    MaterialPageRoute<void> route,
  ) async {
    if (_onboardingOpen) return;
    if (route.isCurrent) Navigator.of(context).pop();
    await route.completed;
    if (mounted) await _replayGuidedOnboarding();
  }

  void _handleVerificationUser(User? user) {
    _setVerificationReminder(user != null && !user.emailVerified);
  }

  void _setVerificationReminder(bool visible) {
    if (!mounted) return;
    if (_showVerificationBanner != visible) {
      setState(() => _showVerificationBanner = visible);
    }
    if (!visible) {
      _verificationCheckTimer?.cancel();
      _verificationCheckTimer = null;
      return;
    }
    _verificationCheckTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_checkVerification()),
    );
  }

  Future<void> _checkVerification() async {
    if (_verificationCheckInFlight || !_showVerificationBanner) return;
    _verificationCheckInFlight = true;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _setVerificationReminder(false);
        return;
      }
      final verified = await _authService.reloadCurrentUser();
      if (mounted) _setVerificationReminder(!verified);
    } catch (_) {
      // Offline or throttled reloads must not hide the reminder. The next app
      // resume/user event/timer tick safely tries again.
    } finally {
      _verificationCheckInFlight = false;
    }
  }

  Future<void> _openVerifyEmail() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const VerifyEmailScreen()),
    );
    if (mounted) unawaited(_checkVerification());
  }

  Future<void> _openInitialRoomLink() async {
    if (_handledInitialRoomLink) {
      return;
    }
    _handledInitialRoomLink = true;

    final roomId = Uri.base.queryParameters['room']?.trim();
    if (roomId == null || !isSafeInitialRoomLinkId(roomId)) {
      return;
    }

    try {
      final room = await _roomService.getRoom(roomId);
      if (!mounted || !room.isActive) {
        return;
      }

      // RoomEntryScreen is the one consent boundary for every route. Deep
      // links may resolve metadata for their passive preview, but do not
      // write a roster row or touch LiveKit before its explicit CTA.
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => RoomEntryScreen(room: room, startMuted: true),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(intentionalOrFriendly(error))));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _homeVisible.dispose();
    _momentsVisible.dispose();
    _roomsScrollController.dispose();
    _tabTransition.dispose();
    _conversationSubscription?.cancel();
    _notificationCountSubscription?.cancel();
    _entitlementSubscription?.cancel();
    _unreadConversationCountListenable.dispose();
    _unreadNotificationCountListenable.dispose();
    _verificationCheckTimer?.cancel();
    _verificationUserSubscription?.cancel();
    _removeMessageOverlay();
    super.dispose();
  }

  void _handleConversations(List<Conversation> conversations) {
    final currentUserId = _currentUserId;

    if (currentUserId.isEmpty) {
      return;
    }

    final unreadConversations = conversations.where(
      (conversation) => conversation.unreadCountFor(currentUserId) > 0,
    );

    final newUnreadConversationCount = unreadConversations.length;

    Conversation? newestIncomingConversation;
    int largestIncrease = 0;

    for (final conversation in conversations) {
      final currentUnread = conversation.unreadCountFor(currentUserId);
      final previousUnread = _previousUnreadCounts[conversation.id] ?? 0;
      final increase = currentUnread - previousUnread;

      if (_hasInitialConversationSnapshot &&
          increase > 0 &&
          conversation.lastMessageSenderId != currentUserId &&
          increase > largestIncrease) {
        newestIncomingConversation = conversation;
        largestIncrease = increase;
      }

      _previousUnreadCounts[conversation.id] = currentUnread;
    }

    final activeConversationIds = conversations
        .map((conversation) => conversation.id)
        .toSet();

    _previousUnreadCounts.removeWhere(
      (conversationId, _) => !activeConversationIds.contains(conversationId),
    );

    if (mounted && newUnreadConversationCount != _unreadConversationCount) {
      setState(() {
        _unreadConversationCount = newUnreadConversationCount;
      });
      _unreadConversationCountListenable.value = newUnreadConversationCount;
    }

    if (_hasInitialConversationSnapshot &&
        !_onboardingOpen &&
        newestIncomingConversation != null &&
        shouldPresentIncomingMessageOverlay(
          selectedIndex: _selectedIndex,
          conversationId: newestIncomingConversation.id,
          activeConversations: ActiveConversationRegistry.instance,
        )) {
      _showIncomingMessageOverlay(newestIncomingConversation, currentUserId);
    }

    _hasInitialConversationSnapshot = true;
  }

  void _showIncomingMessageOverlay(
    Conversation conversation,
    String currentUserId,
  ) {
    final otherUserId = conversation.otherUserId(currentUserId);
    final senderName = conversation.displayNameFor(otherUserId);
    final photoUrl = conversation.photoUrlFor(otherUserId);
    final preview = conversation.previewFor(currentUserId);
    _removeMessageOverlay();
    final controller = YoTopNotificationHost.maybeOf(context);
    // Tests/embedded shells without the app host retain the existing unread
    // badge/inbox as fallback; never create a second overlay or bottom toast.
    if (controller == null) return;
    final accepted = controller.show(
      YoTopNotification(
        title: senderName,
        body: preview,
        type: NotificationType.directMessage,
        source: _messageNotificationSource,
        leading: _IncomingMessageAvatar(
          senderName: senderName,
          photoUrl: photoUrl,
        ),
        onOpen: () {
          if (mounted) _onDestinationSelected(1);
        },
      ),
    );
    if (accepted) _messageNotificationController = controller;
  }

  void _removeMessageOverlay() {
    _messageNotificationController?.clear(source: _messageNotificationSource);
    _messageNotificationController = null;
  }

  // Drives a paint-only directional fade-through. The retained tab layers
  // below remain mounted, so scroll/form/listener state is unaffected.
  late final AnimationController _tabTransition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    value: 1,
  );

  void _onDestinationSelected(int index, {bool recordHistory = true}) {
    if (_selectedIndex == index) {
      return;
    }

    if (index >= _screens.length) {
      _builtSlots.putIfAbsent(index, () => _buildSlot(index));
    }

    _removeMessageOverlay();

    final desktop = MainShell.usesDesktopLayout(MediaQuery.sizeOf(context));
    if (!desktop && recordHistory) _mobileHistory.select(index);
    setState(() {
      _previousSelectedIndex = _selectedIndex;
      _tabDirection = desktop
          ? (index > _selectedIndex ? 1 : -1)
          : (MainShell.mobileNavigationOrder(index) >
                    MainShell.mobileNavigationOrder(_selectedIndex)
                ? 1
                : -1);
      if (!desktop && Directionality.of(context) == TextDirection.rtl) {
        _tabDirection *= -1;
      }
      _selectedIndex = index;
    });
    _momentsVisible.value = index == _momentsSlot;
    _homeVisible.value = index == 0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _tabTransition.value = 1;
    } else {
      _tabTransition.forward(from: 0);
    }
  }

  bool get _canReturnThroughMobileHistory =>
      _mobileHistory.canGoBack &&
      !_isMoreMenuActive &&
      !_onboardingOpen &&
      !_permissionSetupOpen &&
      !_hostedDestinationActive;

  void _returnThroughMobileHistory() {
    if (!_canReturnThroughMobileHistory ||
        ModalRoute.of(context)?.isCurrent == false ||
        _tabTransition.isAnimating) {
      return;
    }
    final previous = _mobileHistory.back();
    if (previous != null) {
      FocusManager.instance.primaryFocus?.unfocus();
      _onDestinationSelected(previous, recordHistory: false);
    }
  }

  Future<void> _openVoiceAction() async {
    final palette = context.appPalette;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 560,
      ),
      barrierColor: palette.scrim.withValues(alpha: 0.7),
      builder: (sheetContext) {
        return const _VoiceActionSheet();
      },
    );
  }

  final GlobalKey _moreItemKey = GlobalKey();

  /// Whether the signed-in account is staff by BOTH measures the server
  /// requires (signed role claim AND the server-written users/{uid}.role
  /// mirror AND an unrestricted account). Only decides whether the
  /// desktop More popover LISTS Moderation — the destination itself,
  /// firestore.rules and the moderateReport callable each re-check.
  bool _isStaff = false;

  /// Whether the More menu lists the Staff Center. Derived from the
  /// getMyStaffCapabilities callable (manageRoles == the confirmed
  /// owner); the screen re-verifies on mount, so this only decides
  /// visibility.
  bool _isOwner = false;

  Future<void> _resolveStaffAccess() async {
    try {
      final staff = await ModerationService().isActiveStaff();
      if (mounted && staff != _isStaff) setState(() => _isStaff = staff);
    } catch (_) {
      // No session or no Firebase: not staff, which is the safe default.
    }
    try {
      final capabilities = await StaffCapabilityService().load();
      if (mounted && capabilities.manageRoles != _isOwner) {
        setState(() => _isOwner = capabilities.manageRoles);
      }
    } catch (_) {
      // Not the owner, which is the safe default.
    }
  }

  /// Mobile keeps its bottom sheet; desktop gets an anchored popover
  /// beside the rail item — no dimmed page, no drag handle.
  Future<void> _openMoreMenu() async {
    final destination = await _moreMenuTransition.run<MoreDestination>(() {
      return () async {
        if (mounted) setState(() => _isMoreMenuActive = true);
        try {
          if (MainShell.usesDesktopLayout(MediaQuery.sizeOf(context))) {
            final box =
                _moreItemKey.currentContext?.findRenderObject() as RenderBox?;
            final anchor = box == null
                ? const Offset(16, 320)
                : box.localToGlobal(Offset(box.size.width - 8, 0));
            return showDesktopMoreMenu(
              context,
              anchor: anchor,
              isStaff: _isStaff,
              isOwner: _isOwner,
              entitlements: _entitlements,
            );
          }
          return showMoreSheet(context, entitlements: _entitlements);
        } finally {
          if (mounted) setState(() => _isMoreMenuActive = false);
        }
      }();
    });
    if (!mounted || destination == null) {
      return;
    }

    await _openMoreDestination(destination);
  }

  // Pushes the destination's own screen directly -- every destination
  // already owns a complete, purpose-built Scaffold with its own header
  // and back button (see each screen's own header widget). Wrapping it in
  // another Scaffold+AppBar here used to double up chrome on every single
  // "More" destination: two stacked titles at best (Settings), a second
  // full Material AppBar at worst (Awards) -- see ADR-019.
  Future<void> _openMoreDestination(MoreDestination destination) async {
    final premiumFeature = premiumFeatureForMoreDestination(destination);
    if (premiumFeature != null &&
        !await PremiumGates.ensureFeatureAccess(
          context,
          feature: premiumFeature,
          entitlementService: _entitlementService,
        )) {
      return;
    }
    if (!mounted) return;

    // Friends owns primary tab index 2 on BOTH form factors. Selecting
    // it keeps the one live FriendsScreen — its scroll position and its
    // listeners — instead of pushing a second copy over the shell.
    if (destination == MoreDestination.friends) {
      _onDestinationSelected(2);
      return;
    }

    // Rooms and Moments are true mobile roots, not duplicated pushed
    // destinations. More and Home links select the same retained content as
    // the dock, preserving search, scroll and audio-visibility ownership.
    if (destination == MoreDestination.discover ||
        destination == MoreDestination.moments) {
      _onDestinationSelected(_slotForDestination(destination)!);
      return;
    }

    // DESKTOP: every destination that owns a content slot swaps the
    // centre of the existing shell — same mechanism as Chats/Friends —
    // so the rail, the profile card and the layout never move. Only
    // Profile (no slot: it keeps a real Back button) still pushes.
    if (MainShell.usesDesktopLayout(MediaQuery.sizeOf(context))) {
      final slot = _slotForDestination(destination);
      if (slot != null) {
        _onDestinationSelected(slot);
        return;
      }
    }

    late final MaterialPageRoute<void> route;
    final screen = moreDestinationScreen(
      destination,
      onReplayGuidedOnboarding: () => _replayGuidedOnboardingAfter(route),
    );

    route = MaterialPageRoute<void>(
      builder: (_) => MoreDestinationHost(
        body: screen,
        selectedIndex: _mobileIndex,
        // The More capsule belongs to the real sheet/popover only. Once a
        // destination is pushed, the panel has closed and the underlying
        // accepted destination remains the navigation truth.
        moreSelected: false,
        unreadConversationCount: _unreadConversationCount,
        unreadConversationCountListenable: _unreadConversationCountListenable,
        unreadNotificationCount: _unreadNotificationCount,
        unreadNotificationCountListenable: _unreadNotificationCountListenable,
        activeDesktopItem: _desktopItemFor(destination),
        onDestinationSelected: _onDestinationSelected,
        onVoicePressed: _openVoiceAction,
        onMorePressed: _openMoreMenu,
        onDesktopNavSelected: (item) => unawaited(_onDesktopNavSelected(item)),
        onCreateRoom: () => unawaited(_openCreateRoom()),
        onCreateMoment: _openCreateMoment,
        onOpenProfile: () => unawaited(_openProfile()),
        onOpenProfileSettings: () => unawaited(_openProfileSettings()),
        canForwardNavigation: _hostNavigationEpochIsCurrent,
      ),
    );
    await _pushHostedDestination(route);
  }

  /// A hosted destination paints its own copy of the persistent chrome.
  /// Suspend the covered shell copy until the pushed route has finished its
  /// reverse transition, so only one room listener and one chat subscription
  /// exist at a time.
  Future<void> _pushHostedDestination(MaterialPageRoute<void> route) async {
    if (!mounted) return;
    setState(() => _hostedDestinationDepth++);
    try {
      await Navigator.of(context).push<void>(route);
      await route.completed;
    } finally {
      if (mounted) {
        setState(() {
          if (_hostedDestinationDepth > 0) _hostedDestinationDepth--;
        });
      }
    }
  }

  /// Which rail item should read as active while a pushed destination is
  /// open, so the desktop shell never looks "nowhere".
  static DesktopNavItem? _desktopItemFor(MoreDestination destination) {
    return switch (destination) {
      MoreDestination.discover => DesktopNavItem.discover,
      MoreDestination.findCreators => DesktopNavItem.findCreators,
      MoreDestination.friends => DesktopNavItem.friends,
      MoreDestination.moments ||
      MoreDestination.reels => DesktopNavItem.moments,
      // Everything reached THROUGH the More popover keeps More lit.
      MoreDestination.clubs ||
      MoreDestination.creatorStudio ||
      MoreDestination.achievements ||
      MoreDestination.notifications ||
      MoreDestination.settings ||
      MoreDestination.moderation ||
      MoreDestination.staffCenter => DesktopNavItem.more,
      MoreDestination.profile => null,
    };
  }

  // --- Desktop-only wiring (the shared MainShell layout predicate) -----
  //
  // The desktop rail is a PRESENTATION shell over the same destinations,
  // state and routes the dock uses; nothing below this line changes the
  // phone layout, which keeps the dock exactly as it was.

  DesktopNavItem get _activeDesktopItem => switch (_selectedIndex) {
    1 => DesktopNavItem.chats,
    2 => DesktopNavItem.friends,
    _discoverSlot => DesktopNavItem.discover,
    _findCreatorsSlot => DesktopNavItem.findCreators,
    _notificationsSlot => DesktopNavItem.notifications,
    // Before the `>= 5` arm: switch-expression arms are ordered, and
    // `>= 5` would otherwise swallow the Moments slot.
    _momentsSlot => DesktopNavItem.moments,
    // Slots reached through the popover keep More lit.
    >= 5 => DesktopNavItem.more,
    _ => DesktopNavItem.home,
  };

  Future<void> _onDesktopNavSelected(DesktopNavItem item) async {
    switch (item) {
      case DesktopNavItem.home:
        _onDestinationSelected(0);
      case DesktopNavItem.chats:
        _onDestinationSelected(1);
      case DesktopNavItem.friends:
        _onDestinationSelected(2);
      case DesktopNavItem.moments:
        _onDestinationSelected(_momentsSlot);
      case DesktopNavItem.discover:
        _onDestinationSelected(_discoverSlot);
      case DesktopNavItem.findCreators:
        _onDestinationSelected(_findCreatorsSlot);
      case DesktopNavItem.notifications:
        _onDestinationSelected(_notificationsSlot);
      case DesktopNavItem.more:
        await _openMoreMenu();
    }
  }

  Future<void> _openProfile() async {
    await _openMoreDestination(MoreDestination.profile);
  }

  /// The sidebar gear: the signed-in user's profile & account settings —
  /// the existing Settings screen, not a desktop-only duplicate.
  Future<void> _openProfileSettings() async {
    await _openMoreDestination(MoreDestination.settings);
  }

  Future<void> _openCreateRoom() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const RoomTypeSelectorScreen()),
    );
  }

  /// The ONE Voice Moment recorder entry point. The desktop rail's
  /// "Create Voice Moment" button, Home's "Your Moment" tile and mobile
  /// Home all call this, so there is a single recording screen, a single
  /// permission prompt, a single upload path and one navigation
  /// behaviour — not a desktop copy of any of them.
  void _openCreateMoment() {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const RecordVoiceMomentScreen(),
        ),
      ),
    );
  }

  /// The ONE way Home opens a Voice Moment, on every form factor.
  ///
  /// Both Home rails used to push [MomentCommentsScreen] for this, which
  /// lists replies and owns no player: tapping a face — including your
  /// own "Your Moment" tile — could not play the Moment it belonged to.
  /// The sheet carries the existing MomentCard, so playback, like,
  /// comment, report and offline download are the same code everywhere.
  Future<void> _openMoment(VoiceMoment moment) async {
    final uid = _currentUserId;
    await showMomentSheet(
      context,
      moment: moment,
      isOwn: uid.isNotEmpty && moment.authorId == uid,
      canReport: uid.isNotEmpty && moment.authorId != uid,
    );
  }

  /// Opens one author's ACTIVE chain in the story viewer, oldest first.
  /// Falls back to the single-Moment sheet if a malformed mixed-author
  /// list somehow arrives without a usable chain.
  Future<void> _openMomentChain(List<VoiceMoment> moments) async {
    final chains = buildMomentChains(moments);
    if (chains.isEmpty) {
      if (moments.isNotEmpty) await _openMoment(moments.first);
      return;
    }
    await showMomentStoryViewer(
      context,
      chain: chains.first,
      onOpenDetail: (moment) => unawaited(_openMomentDetail(moment)),
    );
  }

  /// The ONE way a Moment's full detail page opens from the shell: hosted
  /// over the persistent navigation chrome, so on mobile the bottom dock
  /// stays visible with Moments active while reading a Moment — the same
  /// re-hosting contract every More destination already uses. The detail
  /// screen draws its own Back control, which pops this route straight
  /// back to wherever it was opened from.
  Future<void> _openMomentDetail(VoiceMoment moment) async {
    final route = MaterialPageRoute<void>(
      builder: (_) => MoreDestinationHost(
        body: MomentDetailScreen(moment: moment),
        selectedIndex: _momentsSlot,
        unreadConversationCount: _unreadConversationCount,
        unreadConversationCountListenable: _unreadConversationCountListenable,
        unreadNotificationCount: _unreadNotificationCount,
        unreadNotificationCountListenable: _unreadNotificationCountListenable,
        activeDesktopItem: DesktopNavItem.moments,
        onDestinationSelected: _onDestinationSelected,
        onVoicePressed: _openVoiceAction,
        onMorePressed: _openMoreMenu,
        onDesktopNavSelected: (item) => unawaited(_onDesktopNavSelected(item)),
        onCreateRoom: () => unawaited(_openCreateRoom()),
        onCreateMoment: _openCreateMoment,
        onOpenProfile: () => unawaited(_openProfile()),
        onOpenProfileSettings: () => unawaited(_openProfileSettings()),
        canForwardNavigation: _hostNavigationEpochIsCurrent,
      ),
    );
    await _pushHostedDestination(route);
  }

  Widget _tabContent({
    required int index,
    required int previousIndex,
    required bool isDesktop,
    Widget? desktopHomeTrailing,
  }) {
    return YoPreservingTabTransition(
      selectedIndex: index,
      previousIndex: previousIndex,
      direction: _tabDirection,
      animation: _tabTransition,
      children: _slotChildren(
        isDesktop: isDesktop,
        desktopHomeTrailing: desktopHomeTrailing,
      ),
    );
  }

  Widget _buildDesktopHomeExtras() {
    return _DesktopHomeExtras(
      isVisible: _homeVisible,
      currentUserId: _currentUserId,
      onOpenRoom: (room) => unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => RoomEntryScreen(room: room)),
        ),
      ),
      // "View all" on the Voice Trending card goes to Moments. It used to
      // go to Discover, under a section heading that said "Trending
      // Moments" while listing live ROOMS — the label was renamed to
      // "Live rooms" (which keeps its own link to Discover) and the card
      // gained a real Moments section, so this button now matches what it
      // sits under.
      onSeeAll: () => _onDestinationSelected(_momentsSlot),
      onSeeAllRooms: () =>
          unawaited(_openMoreDestination(MoreDestination.discover)),
      onCheckPlans: () => unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const PremiumScreen()),
        ),
      ),
      onOpenCreator: (creator) => unawaited(
        showProfilePreview(
          context,
          userId: creator.uid,
          displayName: creator.displayName,
          photoUrl: creator.photoUrl,
        ),
      ),
      onViewAllCreators: () => unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => FollowListScreen(
              userId: _currentUserId,
              type: FollowListType.following,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final isDesktop = MainShell.usesDesktopLayout(viewport);
    if (_lastDesktopLayout != isDesktop) {
      _mobileHistory.resetTo(isDesktop ? 0 : _mobileIndex);
      _lastDesktopLayout = isDesktop;
    }

    HomeScreen.openDiscoverTab = () => _onDestinationSelected(_discoverSlot);

    if (isDesktop) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Row(
          key: const ValueKey('desktop-shell-row'),
          children: [
            // The rail owns the full viewport height. Content-only chrome
            // (verification and the live-room dock) must not squeeze primary
            // navigation into a shorter, scrollable lane.
            DesktopSidebar(
              moreItemKey: _moreItemKey,
              tourItemKeys: {
                DesktopNavItem.moments:
                    _onboardingAnchors[GuidedOnboardingTarget.moments]!,
                DesktopNavItem.chats:
                    _onboardingAnchors[GuidedOnboardingTarget.chats]!,
                DesktopNavItem.more:
                    _onboardingAnchors[GuidedOnboardingTarget.more]!,
              },
              tourCreateKey: _onboardingAnchors[GuidedOnboardingTarget.create],
              active: _activeDesktopItem,
              unreadConversationCount: _unreadConversationCount,
              unreadNotificationCount: _unreadNotificationCount,
              onSelect: (item) => unawaited(_onDesktopNavSelected(item)),
              onCreateRoom: () => unawaited(_openCreateRoom()),
              onCreateMoment: _openCreateMoment,
              onOpenProfile: () => unawaited(_openProfile()),
              onOpenProfileSettings: () => unawaited(_openProfileSettings()),
            ),
            Expanded(
              child: Column(
                key: const ValueKey('desktop-content-column'),
                children: [
                  if (_showVerificationBanner)
                    EmailVerificationBanner(onTap: _openVerifyEmail),
                  Expanded(
                    child: ResponsiveContentFrame(
                      width: ResponsiveContentWidth.workbench,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isHome = _selectedIndex == 0;
                          final useRightRail =
                              isHome && constraints.maxWidth >= 1100;
                          final extras = isHome
                              ? _buildDesktopHomeExtras()
                              : null;

                          return Row(
                            children: [
                              Expanded(
                                child: _tabContent(
                                  index: _selectedIndex,
                                  previousIndex: _previousSelectedIndex,
                                  isDesktop: true,
                                  desktopHomeTrailing: useRightRail
                                      ? null
                                      : extras,
                                ),
                              ),
                              // The supplementary Home modules become part
                              // of the main scroll when a fixed 344 px rail
                              // would squeeze the feed below a useful width.
                              if (useRightRail)
                                _DesktopRightColumn(child: extras!),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  // The dock now belongs to the content column, so appearing
                  // or expanding it cannot change the rail's height.
                  if (!_hostedDestinationActive)
                    const SafeArea(top: false, child: RoomMiniBar()),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return PopScope<Object?>(
      canPop: !_mobileHistory.canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _returnThroughMobileHistory();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: YoEdgeBackGesture(
          enabled: _canReturnThroughMobileHistory,
          navigationIdentity: _mobileIndex,
          onBack: _returnThroughMobileHistory,
          child: Column(
            children: [
              if (_showVerificationBanner)
                EmailVerificationBanner(onTap: _openVerifyEmail),
              Expanded(
                child: _tabContent(
                  index: _mobileIndex,
                  previousIndex: _mobileIndexFor(_previousSelectedIndex),
                  isDesktop: false,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A hosted destination owns the visible persistent chrome while
            // this covered shell is suspended, preserving one room listener.
            if (!_hostedDestinationActive) const RoomMiniBar(),
            YoFloatingNavigationDock(
              tourDestinationKeys: {
                2: _onboardingAnchors[GuidedOnboardingTarget.chats]!,
                3: _onboardingAnchors[GuidedOnboardingTarget.moments]!,
                4: _onboardingAnchors[GuidedOnboardingTarget.more]!,
              },
              selectedTabIndex: _mobileIndex,
              roomsTabIndex: _discoverSlot,
              momentsTabIndex: _momentsSlot,
              unreadConversationCount: _unreadConversationCount,
              onDestinationSelected: _onDestinationSelected,
              onVoicePressed: _openVoiceAction,
              onMorePressed: _openMoreMenu,
              moreSelected: _isMoreMenuActive,
            ),
          ],
        ),
      ),
    );
  }
}

/// Home's desktop right column: Voice Trending, the Premium card, then
/// the creators this account already follows — all scrolling together so
/// a short window never clips the bottom of the rail.
///
/// The order is deliberate: what is loud right now (Trending), the offer
/// (Premium, unchanged), then who this person specifically follows. The
/// last two are different questions and are kept as separate modules.
class _DesktopHomeExtras extends StatelessWidget {
  const _DesktopHomeExtras({
    required this.isVisible,
    required this.currentUserId,
    required this.onOpenRoom,
    required this.onSeeAll,
    required this.onSeeAllRooms,
    required this.onCheckPlans,
    required this.onOpenCreator,
    required this.onViewAllCreators,
  });

  final ValueListenable<bool> isVisible;
  final String currentUserId;
  final ValueChanged<VoiceRoom> onOpenRoom;

  /// The card's "View all" — Moments.
  final VoidCallback onSeeAll;

  /// The live-rooms section's own link — Discover. Rooms and Moments are
  /// separate products and the card must not blur them.
  final VoidCallback onSeeAllRooms;
  final VoidCallback onCheckPlans;
  final ValueChanged<FollowUser> onOpenCreator;
  final VoidCallback onViewAllCreators;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // People first, Premium last: the supplementary modules support
        // the primary feed rather than selling over it.
        FollowedCreatorsCard(
          isVisible: isVisible,
          currentUserId: currentUserId,
          onOpenCreator: onOpenCreator,
          onViewAll: onViewAllCreators,
        ),
        const SizedBox(height: 16),
        VoiceTrendingCard(
          isVisible: isVisible,
          onOpenRoom: onOpenRoom,
          onSeeAll: onSeeAll,
          onSeeAllRooms: onSeeAllRooms,
        ),
        const SizedBox(height: 16),
        const SponsoredCard(),
        const SizedBox(height: 16),
        PremiumDesktopCard(onCheckPlans: onCheckPlans),
      ],
    );
  }
}

class _DesktopRightColumn extends StatelessWidget {
  const _DesktopRightColumn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 344,
      child: ListView(
        // Third claimant on the ambient primary controller, alongside the
        // rail and the Home feed — same reasoning as
        // desktop_home.dart's feed: it owns its position explicitly.
        primary: false,
        padding: const EdgeInsets.fromLTRB(6, 20, 20, 20),
        children: [child],
      ),
    );
  }
}

/// NAVIGATION POLICY (deliberate, not incidental): main destinations
/// reached from "More" are shell-level surfaces, so they keep the
/// persistent bottom navigation — this host re-hosts the SAME
/// [YoFloatingNavigationDock] widget wired back to the shell's state (one source
/// of truth for the bar; nothing is reimplemented per screen). Deep
/// detail flows pushed from WITHIN those screens (a friend's profile, a
/// club's detail, a settings subpage, a chat, a room) continue to push
/// plain full-screen routes and intentionally cover the bar. Bar taps
/// here pop back to the shell FIRST, then act, so a tab switch always
/// lands on the real shell.
///
/// Public (unlike the rest of this file's internals) so the navigation
/// regression test can pump the production wrapper directly.
class MoreDestinationHost extends StatefulWidget {
  const MoreDestinationHost({
    required this.body,
    required this.selectedIndex,
    required this.unreadConversationCount,
    required this.onDestinationSelected,
    required this.onVoicePressed,
    required this.onMorePressed,
    this.moreSelected = false,
    this.unreadConversationCountListenable,
    this.unreadNotificationCount = 0,
    this.unreadNotificationCountListenable,
    this.activeDesktopItem,
    this.onDesktopNavSelected,
    this.onCreateRoom,
    this.onCreateMoment,
    this.onOpenProfile,
    this.onOpenProfileSettings,
    this.canForwardNavigation,
    super.key,
  });

  final Widget body;
  final int selectedIndex;
  final int unreadConversationCount;
  final ValueListenable<int>? unreadConversationCountListenable;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onVoicePressed;
  final VoidCallback onMorePressed;
  final bool moreSelected;

  // Desktop-only wiring. When present (and the window is wide) the
  // destination renders INSIDE the persistent desktop shell — the mobile
  // dock/HUD never appears at desktop widths.
  final int unreadNotificationCount;
  final ValueListenable<int>? unreadNotificationCountListenable;
  final DesktopNavItem? activeDesktopItem;
  final ValueChanged<DesktopNavItem>? onDesktopNavSelected;
  final VoidCallback? onCreateRoom;
  final VoidCallback? onCreateMoment;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenProfileSettings;
  final bool Function()? canForwardNavigation;

  @override
  State<MoreDestinationHost> createState() => _MoreDestinationHostState();
}

class _MoreDestinationHostState extends State<MoreDestinationHost> {
  bool _navigationCommitted = false;

  /// Commits exactly one dock/rail action, removes this host completely, and
  /// only then lets the shell present the next route. This prevents a second
  /// tap on the still-animating host from popping the newly opened sheet (or
  /// the shell itself).
  void _popThen(VoidCallback action) {
    if (_navigationCommitted) return;
    _navigationCommitted = true;

    void forwardIfCurrent() {
      if (widget.canForwardNavigation?.call() ?? true) action();
    }

    final navigator = Navigator.of(context);
    if (!navigator.canPop()) {
      // MoreDestinationHost is normally pushed above MainShell, but keeping
      // its public/test harness contract safe at a root route costs nothing:
      // there is no transition to wait for in that shape.
      forwardIfCurrent();
      return;
    }
    final route = ModalRoute.of(context);
    navigator.pop();
    if (route == null) {
      forwardIfCurrent();
      return;
    }
    unawaited(route.completed.then<void>((_) => forwardIfCurrent()));
  }

  @override
  Widget build(BuildContext context) {
    final liveCounts = Listenable.merge(<Listenable>[
      ?widget.unreadConversationCountListenable,
      ?widget.unreadNotificationCountListenable,
    ]);
    return ListenableBuilder(
      listenable: liveCounts,
      builder: (context, _) => _buildHost(
        context,
        unreadConversationCount:
            widget.unreadConversationCountListenable?.value ??
            widget.unreadConversationCount,
        unreadNotificationCount:
            widget.unreadNotificationCountListenable?.value ??
            widget.unreadNotificationCount,
      ),
    );
  }

  Widget _buildHost(
    BuildContext context, {
    required int unreadConversationCount,
    required int unreadNotificationCount,
  }) {
    final viewport = MediaQuery.sizeOf(context);
    final isDesktop = MainShell.usesDesktopLayout(viewport);

    if (isDesktop && widget.onDesktopNavSelected != null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Row(
          key: const ValueKey('desktop-shell-row'),
          children: [
            DesktopSidebar(
              active: widget.activeDesktopItem,
              unreadConversationCount: unreadConversationCount,
              unreadNotificationCount: unreadNotificationCount,
              onSelect: (item) =>
                  _popThen(() => widget.onDesktopNavSelected!(item)),
              onCreateRoom: () => _popThen(widget.onCreateRoom ?? () {}),
              onCreateMoment: () => _popThen(widget.onCreateMoment ?? () {}),
              onOpenProfile: () => _popThen(widget.onOpenProfile ?? () {}),
              onOpenProfileSettings: () =>
                  _popThen(widget.onOpenProfileSettings ?? () {}),
            ),
            Expanded(
              child: Column(
                key: const ValueKey('desktop-content-column'),
                children: [
                  Expanded(
                    child: ResponsiveContentFrame(
                      width: ResponsiveContentWidth.workbench,
                      child: widget.body,
                    ),
                  ),
                  // Same full-height-rail contract as the primary shell.
                  const SafeArea(top: false, child: RoomMiniBar()),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: widget.body,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const RoomMiniBar(),
          YoFloatingNavigationDock(
            selectedTabIndex: widget.selectedIndex,
            roomsTabIndex: _MainShellState._discoverSlot,
            momentsTabIndex: _MainShellState._momentsSlot,
            unreadConversationCount: unreadConversationCount,
            onDestinationSelected: (index) =>
                _popThen(() => widget.onDestinationSelected(index)),
            onVoicePressed: () => _popThen(widget.onVoicePressed),
            onMorePressed: () => _popThen(widget.onMorePressed),
            moreSelected: widget.moreSelected,
          ),
        ],
      ),
    );
  }
}

class _IncomingMessageAvatar extends StatelessWidget {
  const _IncomingMessageAvatar({
    required this.senderName,
    required this.photoUrl,
  });
  final String senderName;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final initial = senderName.trim().isEmpty
        ? '?'
        : senderName.trim().characters.first.toUpperCase();
    final fallback = ColoredBox(
      color: colors.primary,
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: colors.onPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
    return ClipOval(
      child: photoUrl.trim().isEmpty
          ? fallback
          : Image.network(
              photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class _VoiceActionSheet extends StatelessWidget {
  const _VoiceActionSheet();

  Future<void> _openCreateRoom(BuildContext context) async {
    final navigator = Navigator.of(context);

    navigator.pop();

    await Future<void>.delayed(const Duration(milliseconds: 180));

    if (!navigator.mounted) {
      return;
    }

    await navigator.push<void>(
      MaterialPageRoute<void>(builder: (_) => const RoomTypeSelectorScreen()),
    );
  }

  Future<void> _openVoiceMoment(BuildContext context) async {
    final navigator = Navigator.of(context);

    navigator.pop();

    await Future<void>.delayed(const Duration(milliseconds: 180));

    if (!navigator.mounted) {
      return;
    }

    await navigator.push<void>(
      MaterialPageRoute<void>(builder: (_) => const RecordVoiceMomentScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Container(
      key: const ValueKey('voice-action-sheet'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          YoModalSheetChrome(
            sheetLabel: copy.text('voice actions', 'opcje głosowe'),
            surfaceColor: palette.surfaceRaised,
          ),
          const SizedBox(height: 4),
          Text(
            copy.text('Use your voice', 'Użyj swojego głosu'),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 23,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            copy.text(
              'Choose what you want to create.',
              'Wybierz, co chcesz utworzyć.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
          _VoiceOption(
            icon: Icons.mic_rounded,
            title: copy.text('Create Voice Moment', 'Nagraj Voice Moment'),
            subtitle: copy.text(
              'Record and share a short voice update',
              'Nagraj i udostępnij krótką wiadomość głosową',
            ),
            colors: const [Color(0xFF9F22FF), Color(0xFF6A00FF)],
            onPressed: () {
              _openVoiceMoment(context);
            },
          ),
          const SizedBox(height: 13),
          _VoiceOption(
            icon: Icons.groups_2_rounded,
            title: copy.text('Start Voice Room', 'Utwórz pokój głosowy'),
            subtitle: copy.text(
              'Open a live room and invite people',
              'Otwórz pokój na żywo i zaproś innych',
            ),
            colors: const [Color(0xFFFF3E81), Color(0xFF9C1DFF)],
            onPressed: () {
              _openCreateRoom(context);
            },
          ),
        ],
      ),
    );
  }
}

class _VoiceOption extends StatelessWidget {
  const _VoiceOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: ValueKey('voice-option-$title'),
      color: palette.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(icon, color: scheme.onPrimary, size: 27),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
