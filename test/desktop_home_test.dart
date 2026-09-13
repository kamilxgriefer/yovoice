import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/core/presence/user_availability.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_friend_tile.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_greeting_header.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart';
import 'package:yovoice/shared/widgets/profile/availability_picker.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';

import 'semantics_probe.dart';
import 'voice_moment_test_doubles.dart';
import 'home_watermark_visual_capture.dart';

class _ServerStreams extends ServerService {
  _ServerStreams({
    required super.firestore,
    required super.auth,
    this.servers = const <Server>[],
    this.stream,
  });

  final List<Server> servers;
  final Stream<List<Server>>? stream;
  int calls = 0;

  @override
  Stream<List<Server>> watchMyServers() {
    calls++;
    return stream ??
        Stream<List<Server>>.multi(
          (controller) => controller.add(servers),
          isBroadcast: true,
        );
  }
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

  Server server(
    String id, {
    String? name,
    String description = 'A real place for ongoing conversations.',
    ServerType type = ServerType.community,
    String activationState = 'active',
  }) => Server(
    id: id,
    name: name ?? 'Server $id',
    description: description,
    ownerId: uid,
    type: type,
    privacy: type.allowsPublic
        ? ServerPrivacy.public
        : ServerPrivacy.inviteOnly,
    schemaVersion: 1,
    activationState: activationState,
  );

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
    VoidCallback? onOpenServers,
    VoidCallback? onFriends,
    void Function(VoiceMoment)? onOpenMoment,
    void Function(List<VoiceMoment>)? onOpenChain,
    VoidCallback? onCreateMoment,
    VoidCallback? onSeeAllMoments,
    void Function(Conversation)? onOpenConversation,
    VoidCallback? onSeeAllChats,
    ValueChanged<Server>? onOpenServer,
    ProfileMediaService? profileMediaService,
    ServerRepository? serverRepository,
    PresenceService? presenceService,
  }) {
    final firebaseAuth = auth();
    final notifications = NotificationService(
      firestore: db,
      auth: firebaseAuth,
    );
    return DesktopHome(
      currentUserId: uid,
      onSeeAllRooms: onOpenServers ?? () {},
      onViewAllFriends: onFriends ?? () {},
      onStartRoom: onOpenServers ?? () {},
      onOpenMoment: onOpenMoment ?? (_) {},
      onOpenChain: onOpenChain,
      onCreateMoment: onCreateMoment ?? () {},
      onSeeAllMoments: onSeeAllMoments ?? () {},
      onOpenConversation: onOpenConversation ?? (_) {},
      onSeeAllChats: onSeeAllChats ?? () {},
      onOpenClubs: onOpenServers ?? () {},
      onOpenServers: onOpenServers,
      onOpenServer: onOpenServer,
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
      serverRepository:
          serverRepository ?? _ServerStreams(firestore: db, auth: firebaseAuth),
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

  testWidgets('wide Home keeps friends first and answers with server data', (
    tester,
  ) async {
    useDesktop(tester, const Size(1440, 2600));
    final repository = _ServerStreams(
      firestore: db,
      auth: auth(),
      servers: [server('community', name: 'Evening Voices')],
    );
    await tester.pumpWidget(host(buildHome(serverRepository: repository)));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    for (final heading in [
      'Your people',
      'Here and now',
      'In your servers',
      'Your recent chats',
    ]) {
      expect(find.text(heading), findsOneWidget, reason: heading);
    }
    expect(
      tester.getTopLeft(find.text('Your people')).dy,
      lessThan(tester.getTopLeft(find.text('Here and now')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Your recent chats')).dx,
      greaterThan(tester.getTopLeft(find.text('Here and now')).dx),
    );
    expect(find.byKey(const ValueKey('home-secondary-column')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-server-continue-community')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-people-me')), findsOneWidget);
    expect(find.text('Record a Voice Moment'), findsOneWidget);
    expect(repository.calls, 1);

    for (final gone in [
      'From people you follow',
      'Top creators you follow',
      'Clubs',
      'Your active rooms',
      'Rooms for you',
      'Global conversations',
    ]) {
      expect(find.text(gone), findsNothing, reason: '$gone returned');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('server loading, empty, error and ready remain distinct', (
    tester,
  ) async {
    useDesktop(tester, const Size(1100, 2600));
    final controller = StreamController<List<Server>>.broadcast();
    addTearDown(controller.close);
    final repository = _ServerStreams(
      firestore: db,
      auth: auth(),
      stream: controller.stream,
    );
    await tester.pumpWidget(host(buildHome(serverRepository: repository)));
    await tester.pump();
    Finder stateKey(String value) =>
        find.byKey(ValueKey(value), skipOffstage: false);
    expect(stateKey('home-servers-loading'), findsOneWidget);

    controller.add(const <Server>[]);
    await tester.pump();
    expect(stateKey('home-servers-empty'), findsOneWidget);
    expect(stateKey('home-empty-create-server'), findsOneWidget);

    controller.addError(StateError('test connection loss'));
    await tester.pump();
    final error = stateKey('home-servers-error');
    expect(error, findsOneWidget);
    expect(stateKey('home-servers-empty'), findsNothing);
    expect(
      find.byKey(const ValueKey('home-quick-create-server')),
      findsOneWidget,
    );

    await tester.ensureVisible(error);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: error,
        matching: find.text('Try again'),
        skipOffstage: false,
      ),
    );
    await tester.pump();
    expect(repository.calls, 2);

    controller.add([server('ready', name: 'Ready together')]);
    await tester.pump();
    expect(stateKey('home-server-continue-ready'), findsOneWidget);
    expect(stateKey('home-servers-overview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home previews three servers and opens the selected workspace', (
    tester,
  ) async {
    useDesktop(tester, const Size(1440, 2600));
    final servers = [
      server('friends', name: 'Friday crew', type: ServerType.friends),
      server('family', name: 'Our family', type: ServerType.family),
      server('podcast', name: 'Studio notes', type: ServerType.podcast),
      server('company', name: 'YO Team', type: ServerType.company),
    ];
    final opened = <Server>[];
    await tester.pumpWidget(
      host(
        buildHome(
          serverRepository: _ServerStreams(
            firestore: db,
            auth: auth(),
            servers: servers,
          ),
          onOpenServer: opened.add,
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    expect(
      find.byKey(const ValueKey('home-server-continue-friends')),
      findsOneWidget,
    );
    for (final id in ['friends', 'family', 'podcast']) {
      expect(find.byKey(ValueKey('home-server-row-$id')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('home-server-row-company')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('home-server-continue-friends')),
    );
    await tester.tap(find.byKey(const ValueKey('home-server-row-family')));
    expect(opened, hasLength(2));
    expect(opened[0], same(servers[0]));
    expect(opened[1], same(servers[1]));
    expect(find.byKey(const ValueKey('home-featured-room')), findsNothing);
    expect(find.text('Your active rooms'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty server CTAs open the existing Servers destination', (
    tester,
  ) async {
    useDesktop(tester, const Size(1100, 1400));
    var directoryOpens = 0;
    await tester.pumpWidget(
      host(buildHome(onOpenServers: () => directoryOpens++)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    await tester.tap(find.byKey(const ValueKey('home-empty-create-server')));
    await tester.tap(find.byKey(const ValueKey('home-quick-create-server')));
    expect(directoryOpens, 2);
    expect(tester.takeException(), isNull);
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

  testWidgets('server-first Home survives 320 px and 200% text', (
    tester,
  ) async {
    for (final size in const [
      Size(320, 1800),
      Size(768, 1800),
      Size(1100, 1000),
      Size(1440, 1000),
    ]) {
      useDesktop(tester, size);
      final longServer = server(
        'long',
        name: 'The friends and family server with a deliberately long name',
        description:
            'Continue a real voice or text conversation in the channel '
            'that fits the moment.',
        type: ServerType.family,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(2),
            ),
            child: Scaffold(
              body: buildHome(
                serverRepository: _ServerStreams(
                  firestore: db,
                  auth: auth(),
                  servers: [longServer],
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      final card = find.byKey(const ValueKey('home-server-continue-long'));
      expect(card, findsOneWidget, reason: 'server card at ${size.width}');
      final bounds = tester.getRect(card);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(size.width));
      expect(
        find.byKey(const ValueKey('home-quick-create-server')),
        findsOneWidget,
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
      final servers = [
        for (var index = 0; index < 6; index++)
          server('s$index', name: 'Server $index'),
      ];

      await tester.pumpWidget(
        host(
          buildHome(
            serverRepository: _ServerStreams(
              firestore: db,
              auth: auth(),
              servers: servers,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.byKey(const ValueKey('home-server-continue-s0')),
        findsOneWidget,
        reason: 'Home continues the first repository server',
      );
      expect(find.byKey(const ValueKey('home-server-row-s0')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-server-row-s3')), findsNothing);
      expect(find.text('From people you follow'), findsNothing);
      expect(find.text('Clubs'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
