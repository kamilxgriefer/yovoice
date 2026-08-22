import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';

import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/screens/verify_email_screen.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_overview_screen.dart';
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
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/premium_desktop_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/sponsored_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/voice_trending_card.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/premium_gates.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_screen.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';
import 'package:yovoice/features/moderation/data/services/moderation_service.dart';
import 'package:yovoice/features/moments/data/models/moment_chain.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_sheet.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_viewer.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friends_screen.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_entry_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_type_selector_screen.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_mini_bar.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

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
    with SingleTickerProviderStateMixin {
  static const Color _background = Color(0xFF080711);
  static const Color _primary = Color(0xFF9D20FF);

  final MessageService _messageService = MessageService();
  final RoomService _roomService = RoomService();
  final AuthService _authService = AuthService();
  final EntitlementService _entitlementService = EntitlementService();
  bool _handledInitialRoomLink = false;

  Timer? _verificationCheckTimer;
  bool _showVerificationBanner =
      FirebaseAuth.instance.currentUser?.emailVerified == false;

  late final Stream<List<Conversation>> _conversationsStream;
  StreamSubscription<List<Conversation>>? _conversationSubscription;

  final Map<String, int> _previousUnreadCounts = <String, int>{};

  OverlayEntry? _messageOverlay;
  Timer? _messageOverlayTimer;

  int _selectedIndex = 0;
  int _unreadConversationCount = 0;
  bool _hasInitialConversationSnapshot = false;

  /// Desktop sidebar badge only — the same routed count the bell shows.
  int _unreadNotificationCount = 0;
  StreamSubscription<int>? _notificationCountSubscription;

  SubscriptionEntitlements _entitlements = SubscriptionEntitlements.free;
  StreamSubscription<SubscriptionEntitlements>? _entitlementSubscription;

  // Friends replaced Profile as the third primary tab: it's the
  // higher-frequency social destination. Profile lives in More and
  // behind every own-avatar tap instead.
  // Indices 0-2 are the shared primary tabs the mobile dock also drives.
  // 3-4 are DESKTOP-ONLY slots: the rail selects them so Discover and
  // Notifications swap the centre content exactly like Chats/Friends,
  // instead of pushing a route over the shell. The mobile dock never
  // selects them (it only sets 0-2), and the mobile branch clamps, so
  // mobile navigation is unchanged.
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

  Widget _buildSlot(int index) {
    if (index == _notificationsSlot) {
      return const NotificationsScreen(isRootTab: true);
    }
    if (index == _momentsSlot) {
      return MomentsScreen(isRootTab: true, isVisible: _momentsVisible);
    }
    final destination = _slotDestinations[index];
    if (destination == null) return const SizedBox.shrink();
    return moreDestinationScreen(destination, isRootTab: true);
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
    onOpenOwnChain: (mine) => unawaited(_openOwnChain(mine)),
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
    currentUserId: _currentUserId,
    onOpenRoom: (room) => unawaited(_openRoom(room)),
    onSeeAllRooms: () => _onDestinationSelected(_discoverSlot),
    onFindCreators: () => _onDestinationSelected(_findCreatorsSlot),
    onViewAllFriends: () => _onDestinationSelected(2),
    onStartRoom: () => unawaited(_openCreateRoom()),
    onOpenMoment: (moment) => unawaited(_openMoment(moment)),
    onOpenOwnChain: (mine) => unawaited(_openOwnChain(mine)),
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

  /// Mobile shows the three shared tabs PLUS the Moments slot, which the
  /// dock now selects directly. Any other desktop-only slot falls back to
  /// Home rather than showing a tab the dock cannot represent.
  ///
  /// Friends (tab 2) is deliberately still reachable here even though it
  /// no longer owns a dock slot — mobile Home's "Your circle" selects it,
  /// and its state, scroll position and listeners stay alive in the
  /// IndexedStack. The dock renders no capsule while it is showing,
  /// rather than lighting a slot that is not where you are.
  int get _mobileIndex =>
      (_selectedIndex <= 2 || _selectedIndex == _momentsSlot)
      ? _selectedIndex
      : 0;

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();

    _conversationsStream = _messageService.watchConversations(
      includeArchived: true,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openInitialRoomLink();
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
            if (mounted) setState(() => _unreadNotificationCount = count);
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

    if (_showVerificationBanner) {
      // Soft reminder, not the active "waiting room" VerifyEmailScreen is —
      // a slower interval is enough here since this just needs to notice
      // "verified elsewhere" eventually, not drive a live countdown.
      _verificationCheckTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _checkVerification(),
      );
    }
  }

  Future<void> _checkVerification() async {
    final verified = await _authService.reloadCurrentUser();
    if (verified && mounted) {
      _verificationCheckTimer?.cancel();
      setState(() => _showVerificationBanner = false);
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
    if (roomId == null || roomId.isEmpty) {
      return;
    }

    try {
      final room = await _roomService.getRoom(roomId);
      if (!mounted || !room.isLive || !room.isActive) {
        return;
      }
      final joined = await _roomService.joinRoom(roomId);
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => RoomEntryScreen(room: joined)),
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
    _momentsVisible.dispose();
    _tabTransition.dispose();
    _conversationSubscription?.cancel();
    _notificationCountSubscription?.cancel();
    _entitlementSubscription?.cancel();
    _verificationCheckTimer?.cancel();
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
    }

    if (_hasInitialConversationSnapshot &&
        newestIncomingConversation != null &&
        _selectedIndex != 1) {
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

    final overlay = Overlay.of(context, rootOverlay: true);

    _messageOverlay = OverlayEntry(
      builder: (overlayContext) {
        final topPadding = MediaQuery.paddingOf(overlayContext).top;

        return Positioned(
          top: topPadding + 10,
          left: 12,
          right: 12,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: -1, end: 0),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, value * 90),
                  child: Opacity(opacity: 1 + value, child: child),
                );
              },
              child: _IncomingMessageBanner(
                senderName: senderName,
                photoUrl: photoUrl,
                preview: preview,
                onTap: () {
                  _removeMessageOverlay();

                  if (mounted) {
                    setState(() {
                      _selectedIndex = 1;
                    });
                  }
                },
                onClose: _removeMessageOverlay,
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_messageOverlay!);

    _messageOverlayTimer = Timer(
      const Duration(seconds: 4),
      _removeMessageOverlay,
    );
  }

  void _removeMessageOverlay() {
    _messageOverlayTimer?.cancel();
    _messageOverlayTimer = null;

    _messageOverlay?.remove();
    _messageOverlay = null;
  }

  // Drives the between-tab transition: IndexedStack swaps the child
  // instantly (state fully preserved), and this controller layers a fast
  // fade + tiny rise over the swap so switching feels connected rather
  // than abrupt. 220ms, subtle enough that the app still feels instant.
  late final AnimationController _tabTransition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );

  void _onDestinationSelected(int index) {
    if (_selectedIndex == index) {
      return;
    }

    if (index >= _screens.length) {
      _builtSlots.putIfAbsent(index, () => _buildSlot(index));
    }

    _removeMessageOverlay();

    setState(() {
      _selectedIndex = index;
    });
    _momentsVisible.value = index == _momentsSlot;
    _tabTransition.forward(from: 0);
  }

  Future<void> _openVoiceAction() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.7),
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
    final MoreDestination? destination;
    if (MediaQuery.sizeOf(context).width >= _desktopBreakpoint) {
      final box = _moreItemKey.currentContext?.findRenderObject() as RenderBox?;
      final anchor = box == null
          ? const Offset(16, 320)
          : box.localToGlobal(Offset(box.size.width - 8, 0));
      destination = await showDesktopMoreMenu(
        context,
        anchor: anchor,
        isStaff: _isStaff,
        isOwner: _isOwner,
        entitlements: _entitlements,
      );
    } else {
      destination = await showMoreSheet(context, entitlements: _entitlements);
    }
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

    // DESKTOP: every destination that owns a content slot swaps the
    // centre of the existing shell — same mechanism as Chats/Friends —
    // so the rail, the profile card and the layout never move. Only
    // Profile (no slot: it keeps a real Back button) still pushes.
    if (MediaQuery.sizeOf(context).width >= _desktopBreakpoint) {
      final slot = _slotForDestination(destination);
      if (slot != null) {
        _onDestinationSelected(slot);
        return;
      }
    }

    final screen = moreDestinationScreen(destination);

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MoreDestinationHost(
          body: screen,
          selectedIndex: _selectedIndex,
          unreadConversationCount: _unreadConversationCount,
          unreadNotificationCount: _unreadNotificationCount,
          activeDesktopItem: _desktopItemFor(destination),
          onDestinationSelected: _onDestinationSelected,
          onVoicePressed: _openVoiceAction,
          onMorePressed: _openMoreMenu,
          onDesktopNavSelected: (item) =>
              unawaited(_onDesktopNavSelected(item)),
          onCreateRoom: () => unawaited(_openCreateRoom()),
          onCreateMoment: _openCreateMoment,
          onOpenProfile: () => unawaited(_openProfile()),
          onOpenProfileSettings: () => unawaited(_openProfileSettings()),
        ),
      ),
    );
  }

  /// Which rail item should read as active while a pushed destination is
  /// open, so the desktop shell never looks "nowhere".
  static DesktopNavItem? _desktopItemFor(MoreDestination destination) {
    return switch (destination) {
      MoreDestination.discover => DesktopNavItem.discover,
      MoreDestination.findCreators => DesktopNavItem.findCreators,
      MoreDestination.friends => DesktopNavItem.friends,
      MoreDestination.moments => DesktopNavItem.moments,
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

  // --- Desktop-only wiring (>= _desktopBreakpoint) ---------------------
  //
  // The desktop rail is a PRESENTATION shell over the same destinations,
  // state and routes the dock uses; nothing below this line changes the
  // phone layout, which keeps the dock exactly as it was.

  static const double _desktopBreakpoint = 1100;

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

  /// Opens the signed-in user's own ACTIVE chain in the story viewer:
  /// every live Moment, oldest first — the multi-Moment surface Home's
  /// "Your Moment" tiles show a count badge for. Falls back to the
  /// single-Moment sheet when the chain somehow arrives empty.
  Future<void> _openOwnChain(List<VoiceMoment> mine) async {
    final chains = buildMomentChains(mine);
    if (chains.isEmpty) {
      if (mine.isNotEmpty) await _openMoment(mine.first);
      return;
    }
    await showMomentStoryViewer(context, chain: chains.first);
  }

  Widget _tabContent({
    required int index,
    required bool isDesktop,
    Widget? desktopHomeTrailing,
  }) {
    return AnimatedBuilder(
      animation: _tabTransition,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_tabTransition.value);
        return Opacity(
          // Never fully transparent — no flash, no white frame.
          opacity: .55 + .45 * t,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - t)),
            child: child,
          ),
        );
      },
      child: IndexedStack(
        index: index,
        children: _slotChildren(
          isDesktop: isDesktop,
          desktopHomeTrailing: desktopHomeTrailing,
        ),
      ),
    );
  }

  Widget _buildDesktopHomeExtras() {
    return _DesktopHomeExtras(
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
    HomeScreen.openDiscoverTab = () {
      if (MediaQuery.sizeOf(context).width >= _desktopBreakpoint) {
        _onDestinationSelected(_discoverSlot);
      } else {
        unawaited(_openMoreDestination(MoreDestination.discover));
      }
    };

    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Column(
          children: [
            if (_showVerificationBanner)
              _VerificationBanner(onTap: _openVerifyEmail),
            Expanded(
              child: Row(
                children: [
                  DesktopSidebar(
                    moreItemKey: _moreItemKey,
                    active: _activeDesktopItem,
                    unreadConversationCount: _unreadConversationCount,
                    unreadNotificationCount: _unreadNotificationCount,
                    onSelect: (item) => unawaited(_onDesktopNavSelected(item)),
                    onCreateRoom: () => unawaited(_openCreateRoom()),
                    onCreateMoment: _openCreateMoment,
                    onOpenProfile: () => unawaited(_openProfile()),
                    onOpenProfileSettings: () =>
                        unawaited(_openProfileSettings()),
                  ),
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
                ],
              ),
            ),
            // Desktop: the floating dock is the bottom-most element, so it
            // owns the bottom viewport inset itself (mobile Safari / iPad
            // home indicator). The mobile mounts sit above the bottom
            // navigation, which already consumes that inset.
            const SafeArea(top: false, child: RoomMiniBar()),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          if (_showVerificationBanner)
            _VerificationBanner(onTap: _openVerifyEmail),
          Expanded(child: _tabContent(index: _mobileIndex, isDesktop: false)),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Live-room mini player: renders nothing unless a room
          // connection is active, so it can sit here unconditionally.
          const RoomMiniBar(),
          _BottomNavigation(
            selectedIndex: _mobileIndex,
            unreadConversationCount: _unreadConversationCount,
            onDestinationSelected: _onDestinationSelected,
            onVoicePressed: _openVoiceAction,
            onMorePressed: _openMoreMenu,
          ),
        ],
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
    required this.currentUserId,
    required this.onOpenRoom,
    required this.onSeeAll,
    required this.onSeeAllRooms,
    required this.onCheckPlans,
    required this.onOpenCreator,
    required this.onViewAllCreators,
  });

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
          currentUserId: currentUserId,
          onOpenCreator: onOpenCreator,
          onViewAll: onViewAllCreators,
        ),
        const SizedBox(height: 16),
        VoiceTrendingCard(
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
        padding: const EdgeInsets.fromLTRB(6, 20, 20, 20),
        children: [child],
      ),
    );
  }
}

/// NAVIGATION POLICY (deliberate, not incidental): main destinations
/// reached from "More" are shell-level surfaces, so they keep the
/// persistent bottom navigation — this host re-hosts the SAME
/// [_BottomNavigation] widget wired back to the shell's state (one source
/// of truth for the bar; nothing is reimplemented per screen). Deep
/// detail flows pushed from WITHIN those screens (a friend's profile, a
/// club's detail, a settings subpage, a chat, a room) continue to push
/// plain full-screen routes and intentionally cover the bar. Bar taps
/// here pop back to the shell FIRST, then act, so a tab switch always
/// lands on the real shell.
///
/// Public (unlike the rest of this file's internals) so the navigation
/// regression test can pump the production wrapper directly.
class MoreDestinationHost extends StatelessWidget {
  const MoreDestinationHost({
    required this.body,
    required this.selectedIndex,
    required this.unreadConversationCount,
    required this.onDestinationSelected,
    required this.onVoicePressed,
    required this.onMorePressed,
    this.unreadNotificationCount = 0,
    this.activeDesktopItem,
    this.onDesktopNavSelected,
    this.onCreateRoom,
    this.onCreateMoment,
    this.onOpenProfile,
    this.onOpenProfileSettings,
    super.key,
  });

  final Widget body;
  final int selectedIndex;
  final int unreadConversationCount;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onVoicePressed;
  final VoidCallback onMorePressed;

  // Desktop-only wiring. When present (and the window is wide) the
  // destination renders INSIDE the persistent desktop shell — the mobile
  // dock/HUD never appears at desktop widths.
  final int unreadNotificationCount;
  final DesktopNavItem? activeDesktopItem;
  final ValueChanged<DesktopNavItem>? onDesktopNavSelected;
  final VoidCallback? onCreateRoom;
  final VoidCallback? onCreateMoment;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenProfileSettings;

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        MediaQuery.sizeOf(context).width >= _MainShellState._desktopBreakpoint;

    if (isDesktop && onDesktopNavSelected != null) {
      // Rail taps pop this route FIRST, then act, so the shell's own
      // state stays the single source of truth (same contract the mobile
      // bar below already uses).
      void popThen(VoidCallback action) {
        Navigator.of(context).pop();
        action();
      }

      return Scaffold(
        backgroundColor: _MainShellState._background,
        body: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  DesktopSidebar(
                    active: activeDesktopItem,
                    unreadConversationCount: unreadConversationCount,
                    unreadNotificationCount: unreadNotificationCount,
                    onSelect: (item) =>
                        popThen(() => onDesktopNavSelected!(item)),
                    onCreateRoom: () => popThen(onCreateRoom ?? () {}),
                    onCreateMoment: () => popThen(onCreateMoment ?? () {}),
                    onOpenProfile: () => popThen(onOpenProfile ?? () {}),
                    onOpenProfileSettings: () =>
                        popThen(onOpenProfileSettings ?? () {}),
                  ),
                  Expanded(
                    child: ResponsiveContentFrame(
                      width: ResponsiveContentWidth.workbench,
                      child: body,
                    ),
                  ),
                ],
              ),
            ),
            // Same contract as the primary desktop shell: the dock is the
            // bottom-most element here, so it owns the bottom inset.
            const SafeArea(top: false, child: RoomMiniBar()),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: _MainShellState._background,
      body: body,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const RoomMiniBar(),
          _BottomNavigation(
            selectedIndex: selectedIndex,
            unreadConversationCount: unreadConversationCount,
            onDestinationSelected: (index) {
              Navigator.of(context).pop();
              onDestinationSelected(index);
            },
            onVoicePressed: () {
              Navigator.of(context).pop();
              onVoicePressed();
            },
            onMorePressed: () {
              Navigator.of(context).pop();
              onMorePressed();
            },
          ),
        ],
      ),
    );
  }
}

class _VerificationBanner extends StatelessWidget {
  const _VerificationBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2E2410),
      child: InkWell(
        onTap: onTap,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.mark_email_unread_outlined,
                  color: Color(0xFFFFC94D),
                  size: 18,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "Your email isn't verified yet.",
                    style: TextStyle(
                      color: Color(0xFFFFE1A6),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Text(
                  'Verify now',
                  style: TextStyle(
                    color: Color(0xFFFFC94D),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFFFC94D),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IncomingMessageBanner extends StatelessWidget {
  const _IncomingMessageBanner({
    required this.senderName,
    required this.photoUrl,
    required this.preview,
    required this.onTap,
    required this.onClose,
  });

  final String senderName;
  final String photoUrl;
  final String preview;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl.trim().isNotEmpty;
    final initial = senderName.trim().isEmpty
        ? '?'
        : senderName.trim()[0].toUpperCase();

    return Material(
      color: const Color(0xFF181120),
      elevation: 18,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF513065)),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF251432), Color(0xFF17101F)],
            ),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: const Color(0xFF7526B4),
                    backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                    child: hasPhoto
                        ? null
                        : Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFF9D20FF),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF181120),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_rounded,
                        color: Colors.white,
                        size: 9,
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            senderName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const Text(
                          'now',
                          style: TextStyle(
                            color: Color(0xFF9D95AD),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFC8C0D0),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFF9D95AD),
                  size: 19,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({
    required this.selectedIndex,
    required this.unreadConversationCount,
    required this.onDestinationSelected,
    required this.onVoicePressed,
    required this.onMorePressed,
  });

  final int selectedIndex;
  final int unreadConversationCount;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onVoicePressed;
  final VoidCallback onMorePressed;

  /// Maps a selected index onto its SLOT in the five-slot dock row
  /// (voice occupies slot 2), or null when the current destination has
  /// no dock slot at all.
  ///
  /// Null is a real state, not a gap to paper over: Friends is still
  /// primary tab 2 and mobile Home's "Your circle" selects it, but it no
  /// longer owns a dock slot. Lighting the nearest slot would make the
  /// bar lie about where you are, so the capsule is simply not drawn —
  /// the same "nothing lit" the More item has always modelled.
  static int? _slotFor(int tabIndex) => switch (tabIndex) {
    0 => 0,
    1 => 1,
    _MainShellState._momentsSlot => 3,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Floating dock: detached from the screen edges, soft surface, thin
    // border, ambient shadow — navigation as part of the identity, not
    // an edge-to-edge slab. The voice action lives IN the dock, slightly
    // raised, instead of floating over it as an unrelated circle.
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, safeBottom > 0 ? safeBottom : 12),
      child: Container(
        height: 76,
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: .97),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: colors.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? .4 : .14),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: _MainShellState._primary.withValues(alpha: .13),
              blurRadius: 40,
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Stack(
          children: [
            // The selection capsule TRAVELS between slots instead of
            // blinking out and reappearing.
            if (_slotFor(selectedIndex) case final int slot)
              AnimatedAlign(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment(slot / 2 - 1, 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / 5,
                  heightFactor: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _MainShellState._primary.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: _MainShellState._primary.withValues(alpha: .35),
                      ),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: _NavigationItem(
                    icon: Icons.home_outlined,
                    selectedIcon: Icons.home_rounded,
                    label: copy.home,
                    isSelected: selectedIndex == 0,
                    onPressed: () => onDestinationSelected(0),
                  ),
                ),
                Expanded(
                  child: _NavigationItem(
                    icon: Icons.chat_bubble_outline_rounded,
                    selectedIcon: Icons.chat_bubble_rounded,
                    label: copy.chats,
                    badgeCount: unreadConversationCount,
                    isSelected: selectedIndex == 1,
                    onPressed: () => onDestinationSelected(1),
                  ),
                ),
                Expanded(child: _VoiceActionButton(onPressed: onVoicePressed)),
                // Moments, not Friends. The dock stays at five slots
                // (Material 3 caps a navigation bar at five, and 316 pt
                // of usable row on a 360 pt phone cannot carry six), so
                // promoting Moments to primary navigation meant one item
                // giving up its slot. Friends lost it because it is a
                // MANAGEMENT surface — accept a request, browse a list —
                // visited deliberately and rarely, while Moments is a
                // CONSUMPTION surface. Friends keeps its tab, its state,
                // its rail item, its Home entry point, and moves to the
                // first tile of the More sheet.
                //
                // Placed immediately after the create action: record,
                // then hear what everyone else recorded.
                Expanded(
                  child: _NavigationItem(
                    icon: Icons.graphic_eq_outlined,
                    selectedIcon: Icons.graphic_eq_rounded,
                    label: copy.moments,
                    isSelected:
                        selectedIndex == _MainShellState._momentsSlot,
                    onPressed: () =>
                        onDestinationSelected(_MainShellState._momentsSlot),
                  ),
                ),
                Expanded(
                  child: _NavigationItem(
                    icon: Icons.grid_view_rounded,
                    selectedIcon: Icons.grid_view_rounded,
                    label: copy.more,
                    isSelected: false,
                    onPressed: onMorePressed,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onPressed,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final Color color = isSelected ? colors.onSurface : colors.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: isSelected,
      label: badgeCount > 0
          ? '$label, $badgeCount unread conversations'
          : label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(22),
          child: SizedBox.expand(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // The traveling capsule behind the row is the
                      // selection surface; the icon itself just rises a
                      // touch and brightens — felt more than noticed.
                      AnimatedSlide(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        offset: isSelected
                            ? const Offset(0, -.06)
                            : Offset.zero,
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutBack,
                          scale: isSelected ? 1.06 : 1,
                          child: SizedBox(
                            width: 42,
                            height: 30,
                            child: Icon(
                              isSelected ? selectedIcon : icon,
                              color: color,
                              size: 23,
                            ),
                          ),
                        ),
                      ),
                      if (badgeCount > 0)
                        Positioned(
                          top: -5,
                          right: -7,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF3F72),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: colors.surface,
                                width: 2,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x66FF3F72),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Text(
                              badgeCount > 99 ? '99+' : '$badgeCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceActionButton extends StatelessWidget {
  const _VoiceActionButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Integrated into the dock (slightly raised) instead of hovering
    // over it. When a live room connection exists, a ring appears — the
    // dock itself tells you you're on air.
    return ListenableBuilder(
      listenable: VoiceCallService.instance,
      builder: (context, _) {
        final voice = VoiceCallService.instance;
        final live =
            voice.roomId != null &&
            voice.status != VoiceCallStatus.disconnected &&
            voice.status != VoiceCallStatus.failed;

        return Semantics(
          button: true,
          label: live ? 'Voice — live in a room' : 'Use your voice',
          child: Center(
            child: Transform.translate(
              offset: const Offset(0, -9),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: onPressed,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFC73AFF),
                          Color(0xFF981DFF),
                          Color(0xFF6A00FF),
                        ],
                      ),
                      border: live
                          ? Border.all(color: const Color(0xFFFF3F72), width: 2)
                          : null,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x779D20FF),
                          blurRadius: 22,
                          spreadRadius: 1,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Center(child: _WaveformIcon(compact: true)),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WaveformIcon extends StatelessWidget {
  const _WaveformIcon({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scale = compact ? .68 : 1.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _WaveBar(height: 14 * scale),
        const SizedBox(width: 3),
        _WaveBar(height: 25 * scale),
        const SizedBox(width: 3),
        _WaveBar(height: 35 * scale),
        const SizedBox(width: 3),
        _WaveBar(height: 25 * scale),
        const SizedBox(width: 3),
        _WaveBar(height: 14 * scale),
      ],
    );
  }
}

class _WaveBar extends StatelessWidget {
  const _WaveBar({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: const BoxDecoration(
        color: Color(0xFF151020),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: Color(0xFF3A284A))),
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
          const Text(
            'Use your voice',
            style: TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Choose what you want to create.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF9D95AD), fontSize: 14),
          ),
          const SizedBox(height: 24),
          _VoiceOption(
            icon: Icons.mic_rounded,
            title: 'Create Voice Moment',
            subtitle: 'Record and share a short voice update',
            colors: const [Color(0xFF9F22FF), Color(0xFF6A00FF)],
            onPressed: () {
              _openVoiceMoment(context);
            },
          ),
          const SizedBox(height: 13),
          _VoiceOption(
            icon: Icons.groups_2_rounded,
            title: 'Start Voice Room',
            subtitle: 'Open a live room and invite people',
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
    return Material(
      color: const Color(0xFF1C1627),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF382A47)),
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
                child: Icon(icon, color: Colors.white, size: 27),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF9D95AD),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF81768E)),
            ],
          ),
        ),
      ),
    );
  }
}
