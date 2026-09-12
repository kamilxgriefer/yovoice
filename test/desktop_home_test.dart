import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/core/presence/user_availability.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/core/theme/role_identity.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_friend_tile.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_greeting_header.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_here_now_hero.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_room_board.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart';
import 'package:yovoice/shared/widgets/profile/availability_picker.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';

import 'semantics_probe.dart';
import 'voice_moment_test_doubles.dart';
import 'home_watermark_visual_capture.dart';

class _RoomStreams extends RoomService {
  _RoomStreams({required List<VoiceRoom> live, required List<VoiceRoom> owned})
    : _live = List<VoiceRoom>.unmodifiable(live),
      _owned = List<VoiceRoom>.unmodifiable(owned),
      super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me-uid'),
        ),
      );

  final List<VoiceRoom> _live;
  final List<VoiceRoom> _owned;

  @override
  Stream<List<VoiceRoom>> watchLivePublicRooms() =>
      Stream.multi((controller) => controller.add(_live), isBroadcast: true);

  @override
  Stream<List<VoiceRoom>> watchOwnedRooms() =>
      Stream.multi((controller) => controller.add(_owned), isBroadcast: true);
}

class _FailingOwnedRooms extends _RoomStreams {
  _FailingOwnedRooms() : super(live: const [], owned: const []);

  @override
  Stream<List<VoiceRoom>> watchOwnedRooms() =>
      Stream<List<VoiceRoom>>.error(StateError('owned rooms unavailable'));
}

class _ControlledRoomStream extends _RoomStreams {
  _ControlledRoomStream(this.stream) : super(live: [], owned: []);
  final Stream<List<VoiceRoom>> stream;
  @override
  Stream<List<VoiceRoom>> watchLivePublicRooms() => stream;
}

/// Pulse Home (desktop) coverage: every module must render REAL data,
/// the section actions must delegate to the shell's fixed-slot
/// navigation (never a route), and the whole screen must fit every
/// supported desktop size without overflow.
void main() {
  const uid = 'me-uid';
  setUpAll(loadHomeWatermarkFonts);

  late FakeFirebaseFirestore db;

  MockFirebaseAuth auth() => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: uid, email: 'me@yovoice.app', displayName: 'Kamil'),
  );

  Future<void> seedRoom({
    required String id,
    required String name,
    required String description,
    int participants = 12,
    String hostId = '',
    String hostName = 'Host',
    Duration age = Duration.zero,
    bool isLive = true,
  }) async {
    await db.collection('rooms').doc(id).set({
      'hostId': hostId.isEmpty ? 'host-$id' : hostId,
      'hostName': hostName,
      'name': name,
      'description': description,
      'category': 'talk',
      'visibility': 'public',
      'language': 'English',
      'participantCount': participants,
      'memberCount': 0,
      'isLive': isLive,
      'roomType': 'community',
      'status': 'active',
      'experience': 'community',
      // watchLivePublicRooms orders by createdAt desc, so age decides
      // which room is Featured and which fall through to "For you".
      'createdAt': Timestamp.fromDate(DateTime.now().subtract(age)),
    });
    await db
        .collection('rooms')
        .doc(id)
        .collection('participants')
        .doc('speaker-$id')
        .set({
          'userId': 'speaker-$id',
          'displayName': 'Speaker $id',
          'role': 'host',
          'isMuted': false,
          'isSpeaker': true,
        });
  }

  Future<void> seedFriend(String friendId, String name) async {
    await db.collection('users').doc(friendId).set({
      'uid': friendId,
      'displayName': name,
      'email': '$friendId@yovoice.app',
      'isOnline': true,
    });
    await db.collection('publicProfiles').doc(friendId).set({
      'uid': friendId,
      'displayName': name,
      'username': name.toLowerCase(),
      'photoUrl': null,
      'premiumIdentity': false,
    });
    await db.collection('socialPresence').doc(friendId).set({
      'uid': friendId,
      'isOnline': true,
      'lastSeen': Timestamp.now(),
    });
    await db
        .collection('users')
        .doc(uid)
        .collection('friends')
        .doc(friendId)
        .set({'friendId': friendId, 'createdAt': Timestamp.now()});
  }

  Future<void> seedFollowing(String creatorId, String name) async {
    await db.collection('users').doc(creatorId).set({
      'uid': creatorId,
      'displayName': name,
      'username': name.toLowerCase(),
    });
    await db.collection('publicProfiles').doc(creatorId).set({
      'uid': creatorId,
      'displayName': name,
      'username': name.toLowerCase(),
      'photoUrl': null,
      'premiumIdentity': false,
    });
    await db
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(creatorId)
        .set({
          'uid': creatorId,
          'displayName': name,
          'username': name.toLowerCase(),
          'followedAt': Timestamp.now(),
        });
  }

  Future<void> seedMoment({
    required String id,
    required String authorId,
    required String authorName,
    required String caption,
    Duration age = const Duration(minutes: 30),
    int durationSeconds = 42,

    /// Defaults to the shape `finalizeMomentDraft` writes: createdAt +
    /// 24h. Since the expiry contract landed, a Moment without a future
    /// `expiresAt` never renders on Home (see `HomeFeedService`'s
    /// `isActiveAt` filter), so live fixtures must carry one.
    DateTime? expiresAt,
    bool withoutExpiry = false,
  }) async {
    final createdAt = DateTime.now().subtract(age);
    await db.collection('voiceMoments').doc(id).set({
      'authorId': authorId,
      'authorName': authorName,
      'caption': caption,
      'mediaGeneration': '1700000000000001',
      'mediaContentType': 'audio/mp4',
      'mediaSize': 4096,
      'durationSeconds': durationSeconds,
      'likeCount': 0,
      'commentCount': 0,
      'isPublished': true,
      'schemaVersion': 2,
      'status': 'published',
      'isDeleted': false,
      'createdAt': Timestamp.fromDate(createdAt),
      if (!withoutExpiry)
        'expiresAt': Timestamp.fromDate(
          expiresAt ?? createdAt.add(const Duration(hours: 24)),
        ),
    });
  }

  Future<void> seedConversation({
    required String id,
    required String otherId,
    required String otherName,
    required String lastMessage,
    int unread = 0,
    Duration age = Duration.zero,
  }) async {
    await db.collection('conversations').doc(id).set({
      'participantIds': [uid, otherId],
      'participantNames': {uid: 'Kamil', otherId: otherName},
      'participantEmails': {
        uid: 'me@yovoice.app',
        otherId: '$otherId@yovoice.app',
      },
      'participantPhotoUrls': <String, String>{},
      'unreadCounts': {uid: unread, otherId: 0},
      'lastMessage': lastMessage,
      'lastMessageType': 'text',
      'lastMessageSenderId': otherId,
      'updatedAt': Timestamp.fromDate(DateTime.now().subtract(age)),
      'createdAt': Timestamp.now(),
      'archivedBy': <String>[],
      'mutedBy': <String>[],
    });
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc(uid).set({
      'uid': uid,
      'displayName': 'Kamil',
      'email': 'me@yovoice.app',
    });
  });

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  DesktopHome buildHome({
    void Function(VoiceRoom)? onOpenRoom,
    VoidCallback? onSeeAll,
    VoidCallback? onFindCreators,
    VoidCallback? onFriends,
    VoidCallback? onStartRoom,
    void Function(VoiceMoment)? onOpenMoment,
    void Function(List<VoiceMoment>)? onOpenChain,
    VoidCallback? onCreateMoment,
    VoidCallback? onSeeAllMoments,
    void Function(Conversation)? onOpenConversation,
    void Function(Club)? onOpenClub,
    VoidCallback? onSeeAllChats,
    VoidCallback? onOpenClubs,
    ProfileMediaService? profileMediaService,
    RoomService? roomService,
    PresenceService? presenceService,
  }) {
    final firebaseAuth = auth();
    final notifications = NotificationService(
      firestore: db,
      auth: firebaseAuth,
    );
    return DesktopHome(
      currentUserId: uid,
      onOpenRoom: onOpenRoom ?? (_) {},
      onSeeAllRooms: onSeeAll ?? () {},
      onFindCreators: onFindCreators,
      onViewAllFriends: onFriends ?? () {},
      onStartRoom: onStartRoom ?? () {},
      onOpenMoment: onOpenMoment ?? (_) {},
      onOpenChain: onOpenChain,
      onCreateMoment: onCreateMoment ?? () {},
      onSeeAllMoments: onSeeAllMoments ?? () {},
      onOpenConversation: onOpenConversation ?? (_) {},
      onOpenClub: onOpenClub ?? (_) {},
      onSeeAllChats: onSeeAllChats ?? () {},
      onOpenClubs: onOpenClubs ?? () {},
      roomService:
          roomService ?? RoomService(firestore: db, auth: firebaseAuth),
      friendService: FriendService(firestore: db, auth: firebaseAuth),
      followService: FollowService(firestore: db, auth: firebaseAuth),
      profileService: ProfileService(firestore: db, auth: firebaseAuth),
      profileMediaService: profileMediaService,
      feedService: HomeFeedService(
        firestore: db,
        auth: firebaseAuth,
        voiceMomentReadService: VoiceMomentReadService(
          feedInvoker: fakeVoiceMomentFeedInvoker(firestore: db),
        ),
      ),
      messageService: MessageService(
        firestore: db,
        auth: firebaseAuth,
        notificationService: notifications,
      ),
      clubService: ClubService(
        firestore: db,
        auth: firebaseAuth,
        storage: MockFirebaseStorage(),
        notificationService: notifications,
      ),
      clubChatService: ClubChatService(firestore: db, auth: firebaseAuth),
      presenceService: presenceService,
      firebaseAuth: firebaseAuth,
    );
  }

  void useDesktop(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  for (final (name, theme) in [
    ('dark', AppTheme.darkTheme),
    ('pearl', AppTheme.lightTheme),
  ]) {
    testWidgets('production Home watermark desktop $name', (tester) async {
      const size = Size(1440, 900);
      useDesktop(tester, size);
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: Scaffold(body: buildHome()),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          AssetImage(YoPageSection.home.asset),
          capture.currentContext!,
        ),
      );
      await tester.pumpAndSettle();
      final mark = find.descendant(
        of: find.byType(DesktopHome),
        matching: find.byKey(const ValueKey('yo-atmosphere-home')),
      );
      expect(mark, findsOneWidget);
      final canvas = tester.widget<YoPageBackground>(
        find.descendant(
          of: find.byType(DesktopHome),
          matching: find.byType(YoPageBackground),
        ),
      );
      expect(
        canvas.decoration,
        const BoxDecoration(),
        reason: 'desktop shell retains the canvas',
      );
      expect(tester.getSize(find.byType(YoPageBackground)), size);
      await captureHomeWatermarkFrame(
        tester,
        capture,
        'yo-watermark-desktop-home-$name',
      );
      final before = tester.getRect(mark);
      await tester.drag(find.byType(ListView).first, const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(tester.getRect(mark), before);
      expect(tester.takeException(), isNull);
    });
  }

  setUp(ProfileService.resetCurrentProfileCache);
  tearDown(() {
    ProfileService.resetCurrentProfileCache();
    ProfileMediaService.clearAllMediaAccessCaches();
  });

  testWidgets(
    'wide Home answers its four questions in parallel columns, once each',
    (tester) async {
      useDesktop(tester, const Size(1440, 2600));
      await seedRoom(id: 'r1', name: 'Evening Talks', description: 'Real talk');
      // Hosted here but not live: "Your active rooms" renders for a host
      // without adding a second board banner.
      await seedRoom(
        id: 'mine',
        name: 'My hosted room',
        description: 'Owned, not live',
        hostId: uid,
        isLive: false,
      );
      await tester.pumpWidget(host(buildHome()));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      for (final heading in [
        'Your people',
        'Here and now',
        'Your active rooms',
        'Your recent chats',
      ]) {
        expect(find.text(heading), findsOneWidget, reason: heading);
      }
      // The followed-Moments rail moved to the Momenty destination; the
      // Record affordance it carried survives as its own row card, and a
      // friend's new Voice Moment survives as a mark on their face.
      expect(find.text('From people you follow'), findsNothing);
      expect(find.text('Record a Voice Moment'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-people-me')), findsOneWidget);

      double y(String label) => tester.getTopLeft(find.text(label)).dy;
      double x(String label) => tester.getTopLeft(find.text(label)).dx;
      // Approved wide layout: the friends row spans the full width ABOVE
      // the split; the conversation leads the main column and the context
      // column of doors sits to its right.
      expect(y('Your people'), lessThan(y('Here and now')));
      expect(x('Your people'), closeTo(x('Here and now'), 0.01));
      expect(x('Your recent chats'), greaterThan(x('Here and now')));
      expect(y('Here and now'), lessThan(y('Your active rooms')));
      expect(
        find.byKey(const ValueKey('home-secondary-column')),
        findsOneWidget,
      );

      // The removed compositions must not come back.
      for (final gone in [
        'Live around you',
        'Live for you',
        'Your circle',
        'For you',
        'Rooms for you',
        'Recommended now',
        'Global Chat',
        'Global conversations',
        'Top creators you follow',
        'Voice Trending',
      ]) {
        expect(find.text(gone), findsNothing, reason: '$gone returned');
      }
    },
  );

  testWidgets('live loading, true empty and error are distinct states', (
    tester,
  ) async {
    useDesktop(tester, const Size(1100, 900));
    final controller = StreamController<List<VoiceRoom>>.broadcast();
    addTearDown(controller.close);
    await tester.pumpWidget(
      host(buildHome(roomService: _ControlledRoomStream(controller.stream))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('home-rooms-loading')), findsOneWidget);
    expect(
      find.textContaining('A good conversation starts here.'),
      findsNothing,
    );
    expect(find.byType(HomeHereNowHero), findsNothing);
    controller.add([]);
    await tester.pump();
    expect(find.byKey(const ValueKey('home-rooms-loading')), findsNothing);
    expect(
      find.textContaining('A good conversation starts here.'),
      findsOneWidget,
    );
    controller.addError(StateError('test connection loss'));
    await tester.pump();
    expect(
      find.textContaining('A good conversation starts here.'),
      findsNothing,
    );
    // The section sentence leads and already carries this cause, so it is
    // not repeated: an error card says WHICH section failed before it says
    // why.
    expect(
      find.text(
        'Live rooms could not be loaded. '
        'Check your connection and try again.',
      ),
      findsOneWidget,
    );
    // A failed room read must not also cost the reader the way to start a
    // room of their own.
    expect(
      find.byKey(const ValueKey('home-quick-create-room')),
      findsOneWidget,
    );
    expect(find.byType(HomeHereNowHero), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the room directory is NOT on Home, and the other live rooms '
      'still feed the one room the hero features', (tester) async {
    useDesktop(tester, const Size(1440, 2600));
    await seedRoom(
      id: 'r1',
      name: 'Evening Talks',
      description: 'Real talk',
      age: const Duration(minutes: 1),
    );
    await seedRoom(
      id: 'r2',
      name: 'Night Shift',
      description: 'Late voices',
      age: const Duration(minutes: 9),
    );

    await tester.pumpWidget(host(buildHome()));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      if (find.text('Enter').evaluate().isNotEmpty) break;
    }

    // ONE room is featured, never a grid of them: full discovery lives in
    // the Discover destination and in the invitation card's own link.
    expect(find.byType(HomeHereNowHero), findsOneWidget);
    expect(find.byKey(const ValueKey('home-featured-room')), findsOneWidget);
    final hero = tester.widget<HomeHereNowHero>(find.byType(HomeHereNowHero));
    // The newest live room leads; the other one is still a candidate the
    // selection rule considered, not an invented extra card.
    expect(hero.candidate.room.name, 'Evening Talks');
    expect(find.text('Night Shift'), findsNothing);
    expect(find.text('Rooms for you'), findsNothing);

    // Exactly one primary action on the card.
    expect(find.byKey(const ValueKey('home-hero-join')), findsOneWidget);
    expect(find.text('Join the conversation'), findsOneWidget);
  });

  testWidgets('Join room opens the real room through the shell callback', (
    tester,
  ) async {
    useDesktop(tester, const Size(1440, 2600));
    await seedRoom(id: 'r1', name: 'Evening Talks', description: 'Real talk');
    VoiceRoom? opened;
    await tester.pumpWidget(host(buildHome(onOpenRoom: (r) => opened = r)));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    await tester.tap(find.byKey(const ValueKey('home-hero-join')));
    await tester.pump();
    expect(opened?.name, 'Evening Talks');
  });

  for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
    for (final width in [320.0, 768.0, 1440.0]) {
      testWidgets(
        'featured room bright uploaded cover retains long text contrast '
        '${theme.brightness.name} ${width.toInt()} at 200%',
        (tester) async {
          useDesktop(tester, Size(width, 900));
          const title =
              'An unusually long real room title that must remain '
              'fully readable when the room cover is entirely white';
          const description =
              'A long user supplied room description should '
              'wrap naturally at enlarged text sizes without entering a '
              'weak part of the photo scrim or losing any of its content. '
              'The user photo remains visible above these details.';
          const coverUrl = 'https://example.test/bright-home-room.png';
          await seedRoom(
            id: 'bright',
            name: title,
            description: description,
            hostId: uid,
          );
          var manageOpens = 0;
          final room = VoiceRoom.fromFirestore(
            await db.collection('rooms').doc('bright').get(),
          ).withResolvedImageUrl(coverUrl);
          // Populate the real NetworkImage cache with an all-white upload.
          // This exercises production cover precedence without network I/O.
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawColor(Colors.white, BlendMode.src);
          final picture = recorder.endRecording();
          final whiteImage = await tester.runAsync(() => picture.toImage(2, 2));
          picture.dispose();
          final uploadImage = NetworkImage(coverUrl);
          PaintingBinding.instance.imageCache.putIfAbsent(
            uploadImage,
            () => OneFrameImageStreamCompleter(
              Future.value(ImageInfo(image: whiteImage!)),
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 900),
                  textScaler: const TextScaler.linear(2),
                ),
                child: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: HomeRoomBanner(
                      room: room,
                      featured: true,
                      compact: width < 600,
                      onJoin: (_) {},
                      currentUserId: uid,
                      onManageOwnedRoom: () => manageOpens++,
                      staffCapabilities: const StaffCapabilities(
                        staffRole: 'moderator',
                        endPublicRoomWithReason: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester.widget<RoomVisual>(find.byType(RoomVisual)).room.imageUrl,
            coverUrl,
          );
          expect(
            find.byWidgetPredicate(
              (widget) => widget is Image && widget.image == uploadImage,
            ),
            findsOneWidget,
            reason: 'A decorative asset must not replace a real room cover.',
          );
          final backing = find.byKey(
            const ValueKey('home-featured-text-backing'),
          );
          final panel = tester.widget<DecoratedBox>(backing);
          final panelColor = (panel.decoration as BoxDecoration).color!;
          // White is the worst-case uploaded photo luminance. This lower
          // bound does not rely on the card-wide proportional gradient.
          final worstBackground = Color.alphaBlend(panelColor, Colors.white);
          final panelBounds = tester.getRect(backing);
          for (final content in [title, description]) {
            final text = tester.widget<Text>(find.text(content));
            final contrast =
                (text.style!.color!.computeLuminance() + .05) /
                (worstBackground.computeLuminance() + .05);
            expect(contrast, greaterThanOrEqualTo(4.5));
            expect(text.maxLines, isNull);
            expect(text.overflow, TextOverflow.visible);
            final bounds = tester.getRect(find.text(content));
            expect(panelBounds.contains(bounds.topLeft), isTrue);
            expect(panelBounds.contains(bounds.bottomRight), isTrue);
          }
          expect(
            panelBounds.top - tester.getTopLeft(find.byType(HomeRoomBanner)).dy,
            greaterThan(48),
            reason: 'The art remains visible above the text backing.',
          );
          final actions = find.byKey(
            const ValueKey('home-featured-actions-backing'),
          );
          final actionPanel = tester.widget<DecoratedBox>(actions);
          final actionBackground = Color.alphaBlend(
            (actionPanel.decoration as BoxDecoration).color!,
            Colors.white,
          );
          final actionIcons = tester.widgetList<Icon>(
            find.descendant(of: actions, matching: find.byType(Icon)),
          );
          expect(
            actionIcons.map((icon) => icon.icon),
            containsAll([Icons.more_horiz_rounded, Icons.shield_rounded]),
          );
          for (final foreground in [
            ...actionIcons.map((icon) => icon.color!),
            RoleIdentity.ownerColor,
            RoleIdentity.superModeratorColor,
            RoleIdentity.moderatorColor,
          ]) {
            expect(
              (foreground.computeLuminance() + .05) /
                  (actionBackground.computeLuminance() + .05),
              greaterThanOrEqualTo(3),
              reason: 'All role tier icons remain identifiable over white.',
            );
          }
          for (final tooltip in ['Manage your room', 'Staff actions']) {
            final target = find.byTooltip(tooltip);
            // Preserve the native theme's compact 44px menu target. The
            // decorative backing must neither shrink nor replace that action.
            expect(tester.getSize(target).width, greaterThanOrEqualTo(44));
            expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
          }
          await tester.tap(find.byTooltip('Manage your room'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Room settings'));
          await tester.pumpAndSettle();
          expect(manageOpens, 1);
          await tester.tap(find.byTooltip('Staff actions'));
          await tester.pumpAndSettle();
          expect(find.text('End public room…'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          PaintingBinding.instance.imageCache.evict(uploadImage);
        },
      );
    }
  }

  testWidgets('the hero names the real people in the room, and its portrait '
      'cluster opens the real roster on demand', (tester) async {
    useDesktop(tester, const Size(1440, 2600));
    await seedRoom(
      id: 'r1',
      name: 'Evening Talks',
      description: 'Real talk',
      participants: 7,
      hostName: 'Hosty',
    );
    await tester.pumpWidget(host(buildHome()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // The people named on the card are the room's own participant
    // documents, never its `participantCount` dressed up as names.
    expect(find.textContaining('Speaker r1'), findsWidgets);

    final facePile = find.byTooltip('See who is in the room');
    expect(facePile, findsOneWidget);

    await tester.tap(facePile);
    // The dialog route has to finish its transition AND the roster
    // stream has to deliver its first snapshot.
    await tester.pumpAndSettle();
    // The roster came from the room's own participant documents.
    expect(find.text('Speaker r1'), findsOneWidget);
  });

  testWidgets('a very busy room still shows only the faces it can read, '
      'never placeholder people', (tester) async {
    useDesktop(tester, const Size(1440, 2600));
    await seedRoom(
      id: 'busy',
      name: 'Late Night Creators',
      description: 'Deep conversations',
      participants: 2400,
    );
    await tester.pumpWidget(host(buildHome()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // 2400 people, ONE readable participant document: the card shows that
    // one face and says nothing about the other 2399.
    expect(find.text('2.4K'), findsNothing);
    expect(find.byTooltip('See who is in the room'), findsOneWidget);
    expect(find.byType(HomeHereNowHero), findsOneWidget);
  });

  testWidgets('no live rooms: an honest note, never invented rooms', (
    tester,
  ) async {
    useDesktop(tester, const Size(1440, 2600));
    await tester.pumpWidget(host(buildHome()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(
      find.textContaining('A good conversation starts here.'),
      findsOneWidget,
    );
    expect(find.text('Join the conversation'), findsNothing);
    expect(find.byType(HomeHereNowHero), findsNothing);
  });

  testWidgets('Your active rooms lists only rooms this account hosts, and '
      'only the owner sees the settings affordance', (tester) async {
    useDesktop(tester, const Size(1440, 2600));
    await seedRoom(
      id: 'mine',
      name: 'My Room',
      description: 'I host this',
      hostId: uid,
    );
    await seedRoom(
      id: 'theirs',
      name: 'Someone Elses',
      description: 'Not mine',
      hostId: 'other-uid',
    );

    final mine = VoiceRoom.fromFirestore(
      await db.collection('rooms').doc('mine').get(),
    );
    final theirs = VoiceRoom.fromFirestore(
      await db.collection('rooms').doc('theirs').get(),
    );

    await tester.pumpWidget(
      host(
        buildHome(
          roomService: _RoomStreams(live: [theirs, mine], owned: [mine]),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // The owned room appears once on the board and once in the active-room
    // strip; both surfaces expose the owner-only menu, while the non-owned
    // room never receives it.
    expect(find.byTooltip('Manage your room'), findsNWidgets(2));
    expect(find.text('Enter'), findsOneWidget);
  });

  test('one listener-count format, so a banner and the owned card under '
      'it can never disagree about the same room', () {
    expect(compactCount(0), '0');
    expect(compactCount(782), '782');
    expect(compactCount(999), '999');
    expect(compactCount(1000), '1K');
    expect(compactCount(1800), '1.8K');
    expect(compactCount(2400), '2.4K');
    // Below 10K keeps one decimal; at and above it drops to whole
    // thousands, so the chip never grows past four characters.
    expect(compactCount(9950), '9.9K');
    expect(compactCount(12400), '12K');
    expect(compactCount(999999), '1000K');
  });

  testWidgets('Your active rooms ends in a Create room tile that starts the '
      'existing room flow', (tester) async {
    useDesktop(tester, const Size(1440, 2600));
    await seedRoom(
      id: 'mine',
      name: 'My Room',
      description: 'I host this',
      hostId: uid,
    );

    var started = 0;
    await tester.pumpWidget(host(buildHome(onStartRoom: () => started++)));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // The tile sits AFTER the room this account owns. The owner-only
    // settings button is the unambiguous marker for that card — the
    // room's name also appears on its banner in the board above.
    final ownedCreate = find.descendant(
      of: find.byType(HomeActiveRooms),
      matching: find.text('Create room'),
    );
    expect(ownedCreate, findsOneWidget);
    expect(
      tester.getTopLeft(ownedCreate).dx,
      greaterThan(
        tester.getTopLeft(find.byTooltip('Manage your room').last).dx,
      ),
    );

    await tester.tap(ownedCreate);
    await tester.pump();
    expect(started, 1);
  });

  testWidgets('an account hosting nothing gets no owned-rooms section at all', (
    tester,
  ) async {
    useDesktop(tester, const Size(1440, 2600));
    await seedRoom(id: 'r1', name: 'Evening Talks', description: 'Real talk');
    await tester.pumpWidget(host(buildHome()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // A permanently empty card whose Create Room button duplicated the
    // quick-action pill is not information; the section simply hides.
    expect(find.text('Your active rooms'), findsNothing);
    expect(find.text('You have no rooms yet.'), findsNothing);
    expect(find.text('Create Room'), findsNothing);
    expect(find.byTooltip('Manage your room'), findsNothing);
    // Creating a room is still one tap away, from the quick-action pill.
    expect(
      find.byKey(const ValueKey('home-quick-create-room')),
      findsOneWidget,
    );
  });

  testWidgets('an owned-rooms failure still renders the section with a '
      'retry, because an error is not "no rooms"', (tester) async {
    useDesktop(tester, const Size(1440, 2600));
    await tester.pumpWidget(host(buildHome(roomService: _FailingOwnedRooms())));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.text('Your active rooms'), findsOneWidget);
    // Section sentence first, mapped cause second — four simultaneous
    // denials used to print four identical, unattributable cards.
    expect(
      find.text(
        'Could not load rooms. '
        'This is taking longer than expected. Please try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('You have no rooms yet.'), findsNothing);
  });

  testWidgets('recent chats shows at most the three newest conversations', (
    tester,
  ) async {
    useDesktop(tester, const Size(1440, 2600));
    for (var index = 0; index < 4; index++) {
      await seedConversation(
        id: 'c$index',
        otherId: 'friend-$index',
        otherName: 'Friend $index',
        lastMessage: 'Message $index',
        age: Duration(minutes: 4 - index),
      );
    }

    await tester.pumpWidget(host(buildHome()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.text('Friend 3'), findsOneWidget);
    expect(find.text('Friend 2'), findsOneWidget);
    expect(find.text('Friend 1'), findsOneWidget);
    expect(find.text('Friend 0'), findsNothing);
  });

  testWidgets(
    'recent chats refreshes an avatar through a viewer-aware private grant',
    (tester) async {
      useDesktop(tester, const Size(1440, 2600));
      await seedConversation(
        id: 'c-photo',
        otherId: 'friend-photo',
        otherName: 'Fresh Portrait',
        lastMessage: 'The conversation copy has no avatar.',
      );
      await db.collection('publicProfiles').doc('friend-photo').set({
        'uid': 'friend-photo',
        'displayName': 'Fresh Portrait',
        'username': 'freshportrait',
        'profileUpdatedAt': Timestamp.now(),
        'premiumIdentity': false,
      });
      const grantUrl =
          'https://storage.googleapis.com/yovoice-private/'
          'fresh-portrait.jpg?X-Goog-Signature=test';
      final media = ProfileMediaService(
        auth: auth(),
        invoker: (name, request) async {
          expect(name, 'getProfileMediaAccess');
          expect(request, {'userId': 'friend-photo', 'kind': 'avatar'});
          return <Object?, Object?>{
            'schemaVersion': 1,
            'available': true,
            'expiresAtMillis': DateTime.now()
                .toUtc()
                .add(const Duration(seconds: 80))
                .millisecondsSinceEpoch,
            'url': grantUrl,
            'generation': '1700000000000001',
            'contentType': 'image/jpeg',
            'size': 4096,
          };
        },
      );

      await tester.pumpWidget(host(buildHome(profileMediaService: media)));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      final artwork = find.byKey(const ValueKey('recent-chat-photo-c-photo'));
      expect(artwork, findsOneWidget);
      final image = tester.widget<Image>(artwork);
      expect(image.image, isA<NetworkImage>());
      expect((image.image as NetworkImage).url, grantUrl);
      expect(find.byType(ImageFiltered), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  // The followed-Moments rail left Home for the Momenty destination (the
  // package rule: an ordinary Home carries no followed section). What it
  // used to prove about Home is now proved about the FRIENDS row, which is
  // where a new Voice Moment still reaches the reader — gated by real
  // friendship rather than by a follow.
  group('friends with a new Voice Moment', () {
    testWidgets('keeps typical full names readable at 1100 and 1440', (
      tester,
    ) async {
      await seedFriend('friend-long', 'Aleksandra Kwiatkowska');
      await seedFollowing('friend-long', 'Aleksandra Kwiatkowska');
      await seedMoment(
        id: 'moment-long',
        authorId: 'friend-long',
        authorName: 'Aleksandra Kwiatkowska',
        caption: 'A full-name layout regression',
      );
      await seedFriend('follow-long', 'Katarzyna Wierzbicka');
      await seedFollowing('follow-long', 'Katarzyna Wierzbicka');
      await seedMoment(
        id: 'moment-follow-long',
        authorId: 'follow-long',
        authorName: 'Katarzyna Wierzbicka',
        caption: 'Another full-name layout regression',
      );

      useDesktop(tester, const Size(1100, 800));
      await tester.pumpWidget(host(buildHome()));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      // The friends row prints ONE line per name with an ellipsis and
      // announces the whole name — the contract this test has always
      // protected is that a long real name is never silently lost, not that
      // it must always fit on the painted line.
      void expectFullName(String name) {
        final finder = find.descendant(
          of: find.byType(HomeFriendTile),
          matching: find.text(name),
        );
        expect(finder, findsOneWidget);
        final label = tester.widget<Text>(finder);
        expect(label.maxLines, 1);
        expect(label.overflow, TextOverflow.ellipsis);
        final tile = tester.widget<HomeFriendTile>(
          find.ancestor(of: finder, matching: find.byType(HomeFriendTile)),
        );
        expect(
          tile.displayName,
          name,
          reason: '$name must reach a screen reader in full',
        );
        // The desktop label column is the wide one, so the ellipsis is a
        // last resort rather than the ordinary case.
        expect(tester.getSize(finder).width, greaterThanOrEqualTo(120));
      }

      expectFullName('Aleksandra Kwiatkowska');
      expectFullName('Katarzyna Wierzbicka');
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(1440, 900);
      await tester.pump();

      expectFullName('Aleksandra Kwiatkowska');
      expectFullName('Katarzyna Wierzbicka');
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows one tile per followed person with an active Moment, '
        'and no own tile', (tester) async {
      useDesktop(tester, const Size(1440, 820));
      await seedFriend('friend-1', 'Ola');
      await seedFollowing('friend-1', 'Ola');
      await seedFollowing('creator-1', 'Marek');
      await seedMoment(
        id: 'm1',
        authorId: 'friend-1',
        authorName: 'Ola',
        caption: 'Morning thoughts',
      );
      await seedMoment(
        id: 'm2',
        authorId: 'creator-1',
        authorName: 'Marek',
        caption: 'Studio update',
        age: const Duration(days: 3),
        durationSeconds: 55,
        // Older than the 24-hour "New" window but explicitly still live:
        // the claim under test is that a non-fresh Moment shows its REAL
        // duration, and the strip trusts the document's expiresAt rather
        // than re-deriving it.
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      // A stranger the user neither follows nor is friends with.
      await seedMoment(
        id: 'm3',
        authorId: 'stranger',
        authorName: 'Nobody',
        caption: 'Not in the circle',
      );
      await seedFriend('friend-only', 'Friend only');
      await seedMoment(
        id: 'm-friend-only',
        authorId: 'friend-only',
        authorName: 'Friend only',
        caption: 'Friends are not automatically followed voices',
      );
      // In the circle but DEAD: past its 24-hour life. The expiry filter
      // must keep it off Home even before the sweeper marks it.
      await seedFollowing('creator-2', 'Bartek');
      await seedMoment(
        id: 'm4',
        authorId: 'creator-2',
        authorName: 'Bartek',
        caption: 'Expired yesterday',
        age: const Duration(days: 2),
      );
      // In the circle with no expiresAt at all — PERMANENT under the
      // amended availability contract ("keep until deleted"), so it MUST
      // render. This ADAPTS the ADR-101-era pin that read a missing
      // expiresAt as legacy-expired; that direction was deliberately
      // reversed when operator-chosen availability shipped.
      await seedFollowing('creator-3', 'Celina');
      await seedMoment(
        id: 'm5',
        authorId: 'creator-3',
        authorName: 'Celina',
        caption: 'No expiry field',
        withoutExpiry: true,
      );

      await tester.pumpWidget(host(buildHome()));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      // The whole followed rail and its own story tile left Home; creation
      // survives as the "Got a minute?" card.
      expect(find.byType(MomentStoryTile), findsNothing);
      expect(find.byKey(const ValueKey('home-your-moment')), findsNothing);
      expect(find.byKey(const ValueKey('home-record-moment')), findsOneWidget);

      HomeFriendVoice? voiceFor(String id) => tester
          .widget<HomeFriendTile>(find.byKey(ValueKey('home-person-$id')))
          .voice;

      // A FRIEND with playable, unexpired, unheard media gets the mark.
      expect(voiceFor('friend-1'), isNotNull);
      // A followed author who is not a friend never gets one: the page came
      // from the following feed, but only friendship may mark a face.
      expect(find.byKey(const ValueKey('home-person-creator-1')), findsNothing);
      // Nobody outside the circle may appear at all.
      expect(find.text('Nobody'), findsNothing);
      // A friend whose Moment is past its expiresAt keeps presence only.
      expect(find.byKey(const ValueKey('home-person-creator-2')), findsNothing);
      // Compact Home avatars carry no invented presence or redundant status.
      expect(find.text('New'), findsNothing);
      // The duplicate recap of the same authors left Home entirely.
      expect(find.text('Your circle'), findsNothing);
      expect(find.text('From people you follow'), findsNothing);
    });

    testWidgets('a Moment tile opens the existing viewer and the plus opens '
        'the existing creation flow', (tester) async {
      useDesktop(tester, const Size(1440, 820));
      await seedFriend('friend-1', 'Ola');
      await seedFollowing('friend-1', 'Ola');
      await seedMoment(
        id: 'm1',
        authorId: 'friend-1',
        authorName: 'Ola',
        caption: 'Morning thoughts',
      );

      List<VoiceMoment>? openedChain;
      var created = 0;
      var seeAllMoments = 0;

      await tester.pumpWidget(
        host(
          buildHome(
            onOpenChain: (moments) => openedChain = moments,
            onCreateMoment: () => created++,
            onSeeAllMoments: () => seeAllMoments++,
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      // The friend's own tile is the door to her chain.
      await tester.tap(find.byKey(const ValueKey('home-person-friend-1')));
      await tester.pump();
      expect(openedChain?.map((moment) => moment.id), ['m1']);
      expect(openedChain!.every((moment) => moment.audioUrl == null), isTrue);
      expect(
        openedChain!.every((moment) => moment.mediaGeneration == null),
        isTrue,
      );
      expect(openedChain!.every((moment) => moment.hasAuthorizedMedia), isTrue);

      await tester.tap(find.byKey(const ValueKey('home-record-moment')));
      await tester.pump();
      expect(created, 1);

      expect(seeAllMoments, 0, reason: 'avatar actions open their real Moment');
    });

    testWidgets('never shows profile-only suggestions in the Moments rail', (
      tester,
    ) async {
      useDesktop(tester, const Size(1440, 900));
      // Neither a friend nor a followed profile without audio belongs here.
      await seedFriend('friend-1', 'Ola');
      await seedFollowing('creator-1', 'Marek');

      await tester.pumpWidget(host(buildHome()));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      // A friend WITHOUT a playable Moment is a face with presence and no
      // mark; a followed profile is not on Home's friends row at all.
      expect(find.byType(MomentStoryTile), findsNothing);
      final ola = tester.widget<HomeFriendTile>(
        find.byKey(const ValueKey('home-person-friend-1')),
      );
      expect(ola.voice, isNull);
      expect(find.byKey(const ValueKey('home-person-creator-1')), findsNothing);
      expect(find.text('Follow'), findsNothing);
    });

    testWidgets('empty circle is an avatar-only rail without filler or CTAs', (
      tester,
    ) async {
      useDesktop(tester, const Size(1440, 820));
      await tester.pumpWidget(host(buildHome()));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(find.text('YO Moments from your circle'), findsNothing);
      // An empty circle is not a section on Home at all any more: the
      // followed rail lives in the Momenty destination.
      expect(find.text('From people you follow'), findsNothing);
      expect(find.byType(MomentStoryTile), findsNothing);
      expect(find.text('Record a Voice Moment'), findsOneWidget);
      // The one "You" on the screen is the people rail's own tile.
      expect(find.text('You'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-people-me')), findsOneWidget);
      // The rail keeps a real creation target rather than filler copy.
      expect(find.byKey(const ValueKey('home-record-moment')), findsOneWidget);
      expect(
        find.textContaining('No Moments from your circle yet'),
        findsNothing,
      );
      expect(find.text('Find creators'), findsNothing);
    });
  });

  group('availability on desktop Home', () {
    testWidgets('the greeting card carries NO chip; the own tile carries the '
        'readable one with its 44 px target', (tester) async {
      useDesktop(tester, const Size(1440, 900));
      await db.collection('users').doc(uid).set({
        'uid': uid,
        'displayName': 'Kamil',
        'email': 'me@yovoice.app',
        'availability': UserAvailability.busy.wire,
      });
      await tester.pumpWidget(host(buildHome()));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      // The header is a greeting, a bell and an avatar — nothing competes
      // with the reader's own name for the line.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-greeting-card')),
          matching: find.byType(AvailabilityChip),
        ),
        findsNothing,
      );

      // The picker moved to the "You" tile at the head of the friends row,
      // where it is still one tap away and still a 44 px target.
      final me = find.byKey(const ValueKey('home-people-me'));
      expect(me, findsOneWidget);
      expect(tester.getSize(me).height, greaterThanOrEqualTo(44));
      expect(tester.widget<HomeFriendTile>(me).statusLabel, 'Do not disturb');
      // The tile is the FIRST thing in the row it heads.
      expect(
        tester.getTopLeft(me).dy,
        greaterThan(tester.getTopLeft(find.text('Your people')).dy),
      );
      // The avatar's own presence dot reads from the same availability.
      expect(find.byType(HomeGreetingHeader), findsOneWidget);
    });

    testWidgets('the own tile opens the picker as a dialog at >= 900 px and '
        'writes the choice', (tester) async {
      useDesktop(tester, const Size(1440, 900));
      final presence = PresenceService(firestore: db, auth: auth());
      await tester.pumpWidget(host(buildHome(presenceService: presence)));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      final me = find.byKey(const ValueKey('home-people-me'));
      expect(me, findsOneWidget);
      expect(tester.widget<HomeFriendTile>(me).status, PeopleStatus.online);

      await tester.tap(me);
      await tester.pumpAndSettle();
      // Wide viewports get the dialog, never the phone sheet.
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Your availability'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('availability-option-invisible')),
      );
      await tester.pumpAndSettle();
      expect(
        (await db.collection('users').doc(uid).get()).data()!['availability'],
        'invisible',
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      // Invisible is grey to its owner — the projected "Away" ring — and is
      // still labelled with the state the account actually chose.
      expect(tester.widget<HomeFriendTile>(me).status, PeopleStatus.away);
      expect(tester.widget<HomeFriendTile>(me).statusLabel, 'Invisible');
    });

    testWidgets('the chip is its own semantics node: the greeting and the '
        'subtitle are never swallowed into a button', (tester) async {
      useDesktop(tester, const Size(1440, 1200));
      await db.collection('users').doc(uid).set({
        'uid': uid,
        'displayName': 'Kamil',
        'email': 'me@yovoice.app',
        'availability': UserAvailability.busy.wire,
      });
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(buildHome()));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      // The availability action is announced exactly once on this screen,
      // and it belongs to the own tile.
      const phrase = 'You. Availability: Do not disturb. Change';
      final buttons = compiledButtonLabels(tester);
      expect(buttons.where((label) => label == phrase).length, 1);
      // The regression this pins: the greeting Row's Text nodes used to be
      // merged into a neighbouring control's node, giving a 138x44 control a
      // 1396x60 activation region named after the whole greeting.
      for (final label in buttons) {
        expect(
          label,
          isNot(
            anyOf(
              contains('Good to see you again'),
              contains('Here is what sounds good right now'),
            ),
          ),
          reason: 'no control may claim the greeting as its name: "$label"',
        );
      }
      // Two header controls, each named for what it opens and nothing more.
      expect(buttons, contains('Notifications'));
      expect(buttons, contains('Open your profile'));
      semantics.dispose();
    });
  });

  testWidgets('Your active rooms survives 200% text without clipping', (
    tester,
  ) async {
    // WCAG 1.4.4: at 200 % text the owned-room card must reflow, not be cut
    // off. The row used to pin itself to artwork + a flat 96 px, and clipped
    // the Enter button by 36 px.
    await seedRoom(
      id: 'mine',
      name: 'Evening Talks',
      description: 'Real talk',
      hostId: uid,
    );
    for (final size in const [
      Size(1100, 1000),
      Size(1440, 1000),
      Size(1440, 6000),
    ]) {
      useDesktop(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(2),
            ),
            child: Scaffold(body: buildHome()),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      // At 200 % text the page above it is far taller, so the section is
      // below the fold — it must still BE there, and still reflow.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-owned-rooms')),
        600,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 120,
      );
      expect(
        find.text('Your active rooms'),
        findsOneWidget,
        reason: 'the section must actually render at ${size.width}',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'at ${size.width}x${size.height} @200% text',
      );
    }
  });

  // Every supported desktop size, plus the narrow end of the range.
  for (final size in const [
    Size(1920, 1080),
    Size(1440, 900),
    Size(1366, 768),
    Size(1100, 800),
  ]) {
    testWidgets('lays out without overflow at ${size.width.toInt()}x'
        '${size.height.toInt()}', (tester) async {
      useDesktop(tester, size);
      await seedFriend('friend-1', 'Ola');
      await seedMoment(
        id: 'm1',
        authorId: 'friend-1',
        authorName: 'Ola',
        caption: 'Morning',
      );
      await seedConversation(
        id: 'c1',
        otherId: 'friend-1',
        otherName: 'Ola',
        lastMessage: 'See you tonight',
        unread: 2,
      );
      for (var index = 0; index < 6; index++) {
        await seedRoom(
          id: 'r$index',
          name: 'Room $index',
          description: 'Room number $index',
        );
      }

      await tester.pumpWidget(host(buildHome()));
      await tester.pump(const Duration(milliseconds: 200));

      // ONE room is featured however many are live: Discover owns the rest,
      // so Home never mounts a participants listener per live room.
      expect(
        find.byType(HomeHereNowHero),
        findsOneWidget,
        reason: 'Home features exactly one live room',
      );
      expect(find.text('Rooms for you'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
