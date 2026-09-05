import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_palette.dart';

import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_moments_strip.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home_sections.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_overview_sections.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/profile/data/models/profile_visibility.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

final _anchor = DateTime.utc(2026, 8, 27, 12);

VoiceMoment _moment(
  String id, {
  required DateTime expiresAt,
  String authorId = 'friend',
  String authorName = 'Friend',
  DateTime? createdAt,
}) => VoiceMoment(
  id: id,
  authorId: authorId,
  authorName: authorName,
  authorPhotoUrl: null,
  caption: 'caption $id',
  audioUrl: 'https://cdn.example/$id.m4a',
  durationSeconds: 12,
  likeCount: 0,
  commentCount: 0,
  isPublished: true,
  createdAt: createdAt ?? _anchor.subtract(const Duration(minutes: 5)),
  expiresAt: expiresAt,
  schemaVersion: 2,
  status: 'published',
  isDeleted: false,
);

UserProfile _profile() => UserProfile(
  uid: 'me',
  email: 'me@example.com',
  displayName: 'Me',
  username: 'me',
  bio: '',
  country: '',
  nativeLanguage: '',
  spokenLanguages: const [],
  learningLanguages: const [],
  photoUrl: null,
  bannerUrl: null,
  website: '',
  accountType: AccountType.personal,
  friendCount: 0,
  followerCount: 0,
  followingCount: 0,
  roomCount: 0,
  communityCount: 0,
  voiceMinutes: 0,
  messageCount: 0,
  activeDays: 0,
  momentCount: 0,
  reactionCount: 0,
  hostMinutes: 0,
  selectedTitleId: '',
  unlockedTitleIds: const [],
  unlockedTitleTimestamps: const {},
  createdAt: _anchor,
  profileVisibility: ProfileVisibility.public,
);

List<Map<Object?, Object?>> _captureAnnouncements(WidgetTester tester) {
  final captured = <Map<Object?, Object?>>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
    SystemChannels.accessibility,
    (Object? message) async {
      if (message is Map && message['type'] == 'announce') {
        captured.add(message['data'] as Map<Object?, Object?>);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          SystemChannels.accessibility,
          null,
        ),
  );
  return captured;
}

List<String> _messages(List<Map<Object?, Object?>> captured) =>
    captured.map((event) => event['message'] as String).toList(growable: false);

Future<void> _seedFollowing(
  FakeFirebaseFirestore firestore,
  String userId,
) async {
  await firestore.collection('publicProfiles').doc(userId).set({
    'uid': userId,
    'displayName': 'Friend',
    'username': 'friend',
  });
  await firestore
      .collection('users')
      .doc('me')
      .collection('following')
      .doc(userId)
      .set({'uid': userId, 'followedAt': Timestamp.now()});
}

class _Clock {
  _Clock(this.now);

  DateTime now;
}

class _ControlledFeed extends HomeFeedService {
  _ControlledFeed(MockFirebaseAuth auth)
    : super(firestore: FakeFirebaseFirestore(), auth: auth);

  final _controller = StreamController<List<VoiceMoment>>.broadcast(sync: true);

  void emit(List<VoiceMoment> moments) => _controller.add(moments);

  Future<void> close() => _controller.close();

  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      _controller.stream;

  @override
  Stream<bool> watchLiked(String momentId) => Stream<bool>.value(false);

  @override
  Future<void> toggleLike(String momentId) async {}
}

class _EmptyDiscovery extends MomentDiscoveryService {
  _EmptyDiscovery(MockFirebaseAuth auth)
    : super(firestore: FakeFirebaseFirestore(), auth: auth);

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async => MomentDiscoveryFeed(
    moments: const <VoiceMoment>[],
    fetchedCount: 0,
    drops: const <String, MomentDropReason>{},
    seed: seed ?? 1,
    poolExhausted: false,
  );

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
  }) => Stream<Map<String, MomentEngagement>>.value(
    const <String, MomentEngagement>{},
  );
}

void main() {
  late PublicIdentityRepository originalIdentity;
  late MockFirebaseAuth auth;

  setUp(() {
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me'));
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: auth,
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'uid': uid, 'role': 'user', 'vip': false},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  for (final anotherRemains in [false, true]) {
    testWidgets(
      'circle expiry recovers visible focus without duplicate announcement: $anotherRemains',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final semantics = tester.ensureSemantics();
        final announcements = _captureAnnouncements(tester);
        final clock = _Clock(_anchor);
        final expiring = _moment(
          'circle-expiring',
          expiresAt: _anchor.add(const Duration(seconds: 10)),
        );
        final remaining = _moment(
          'circle-remaining',
          authorId: 'other',
          authorName: 'Other',
          expiresAt: _anchor.add(const Duration(hours: 1)),
        );
        var friendsOpens = 0;
        Future<void> pump(List<VoiceMoment> moments) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    MobileMomentsStrip(
                      moments: moments,
                      profile: _profile(),
                      currentUserId: 'me',
                      expiryClock: () => clock.now,
                      onOpenMoment: (_) {},
                      onCreateMoment: () {},
                    ),
                    HomeCircleActivity(
                      moments: moments,
                      currentUserId: 'me',
                      expiryClock: () => clock.now,
                      onOpenMoment: (_) {},
                      onFriends: () => friendsOpens++,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await pump([]);
        expect(
          find.byKey(const ValueKey('home-circle-expiry-friends')),
          findsNothing,
        );
        await pump([expiring, if (anotherRemains) remaining]);
        final tile = tester.widget<ListTile>(
          find.byKey(const ValueKey('home-circle-friend')),
        );
        tile.focusNode!.requestFocus();
        await tester.pump();
        expect(tile.focusNode!.hasFocus, isTrue);
        clock.now = expiring.expiresAt!;
        await pump([if (anotherRemains) remaining]);
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const ValueKey('home-circle-friend')), findsNothing);
        if (anotherRemains) {
          final heading = tester.widget<MomentExpiryFocusTarget>(
            find.byKey(const ValueKey('home-circle-expiry-heading')),
          );
          expect(heading.focusNode.hasFocus, isTrue);
        } else {
          final recovery = tester.widget<OutlinedButton>(
            find.byKey(const ValueKey('home-circle-expiry-friends')),
          );
          expect(recovery.focusNode!.hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(friendsOpens, 1);
        }
        expect(_messages(announcements), [
          'One Voice Moment expired and was removed from Home.',
        ]);
        await pump([if (anotherRemains) remaining]);
        expect(_messages(announcements), hasLength(1));
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'visible mobile Home strip announces once and recovers a removed tile',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      final announcements = _captureAnnouncements(tester);
      final clock = _Clock(_anchor);
      final expiring = _moment(
        'mobile-expiring',
        createdAt: _anchor.subtract(const Duration(days: 1)),
        expiresAt: _anchor.add(const Duration(seconds: 10)),
      );
      final remaining = [
        for (var index = 0; index < 6; index++)
          _moment(
            'mobile-remaining-$index',
            authorId: 'remaining-$index',
            authorName: 'Other $index',
            createdAt: _anchor.subtract(Duration(minutes: index)),
            expiresAt: _anchor.add(const Duration(hours: 1)),
          ),
      ];
      var records = 0;

      Future<void> pump(List<VoiceMoment> moments) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileMomentsStrip(
              moments: moments,
              profile: _profile(),
              currentUserId: 'me',
              expiryClock: () => clock.now,
              onOpenMoment: (_) {},
              onCreateMoment: () => records++,
            ),
          ),
        ),
      );

      await pump([expiring, ...remaining]);
      final tile = find.byKey(const ValueKey('home-moment-mobile-expiring'));
      await tester.ensureVisible(tile);
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const ValueKey('home-your-moment'))).right,
        lessThan(0),
        reason: 'The recovery target starts offscreen in the scrolled rail.',
      );
      final tileInk = tester.widget<InkWell>(
        find.descendant(of: tile, matching: find.byType(InkWell)).first,
      );
      tileInk.focusNode!.requestFocus();
      await tester.pump();
      expect(tileInk.focusNode!.hasFocus, isTrue);

      clock.now = expiring.expiresAt!;
      await pump(remaining);
      await tester.pump();
      await tester.pump();

      final ownAvatar = find.byKey(const ValueKey('home-your-moment'));
      final ownAction = tester.widget<InkWell>(
        find.descendant(of: ownAvatar, matching: find.byType(InkWell)).first,
      );
      expect(ownAction.focusNode!.hasFocus, isTrue);
      expect(tester.getSize(ownAvatar).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(ownAvatar).height, greaterThanOrEqualTo(44));
      final ownBounds = tester.getRect(ownAvatar);
      expect(ownBounds.left, greaterThanOrEqualTo(0));
      expect(ownBounds.right, lessThanOrEqualTo(320));
      expect(
        find.byKey(const ValueKey('mobile-home-moments-heading')),
        findsNothing,
        reason: 'Recovery must not land on an invisible heading placeholder.',
      );
      final outline = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('home-own-moment-focus-outline')),
      );
      final border = (outline.decoration as BoxDecoration).border! as Border;
      expect(border.top.width, 2);
      expect(border.top.color, tester.element(ownAvatar).appPalette.focus);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        records,
        1,
        reason: 'The visible recovery action records a Moment.',
      );
      expect(_messages(announcements), [
        'One Voice Moment expired and was removed from Home.',
      ]);

      await pump(remaining);
      expect(_messages(announcements), hasLength(1));
      semantics.dispose();
    },
  );

  testWidgets('mobile expiry stays silent for the capped thirteenth author', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    final announcements = _captureAnnouncements(tester);
    final clock = _Clock(_anchor);
    final shown = <VoiceMoment>[
      for (var index = 0; index < 12; index++)
        _moment(
          'shown-$index',
          authorId: 'shown-author-$index',
          authorName: 'Shown $index',
          createdAt: _anchor.subtract(Duration(seconds: index)),
          expiresAt: _anchor.add(const Duration(hours: 1)),
        ),
    ];
    final hidden = _moment(
      'hidden-thirteenth',
      authorId: 'hidden-author',
      authorName: 'Hidden thirteenth',
      createdAt: _anchor.subtract(const Duration(minutes: 10)),
      expiresAt: _anchor.add(const Duration(seconds: 10)),
    );

    Future<void> pump(List<VoiceMoment> moments) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileMomentsStrip(
            moments: moments,
            profile: _profile(),
            currentUserId: 'me',
            expiryClock: () => clock.now,
            onOpenMoment: (_) {},
            onCreateMoment: () {},
          ),
        ),
      ),
    );

    await pump([...shown, hidden]);
    expect(
      find.byKey(const ValueKey('home-moment-hidden-thirteenth')),
      findsNothing,
    );

    clock.now = hidden.expiresAt!;
    await pump(shown);
    await tester.pump();

    expect(_messages(announcements), isEmpty);
    semantics.dispose();
  });

  testWidgets(
    'visible desktop Home strip announces once and recovers a removed tile',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      final announcements = _captureAnnouncements(tester);
      final clock = _Clock(_anchor);
      final feed = _ControlledFeed(auth);
      addTearDown(feed.close);
      final db = FakeFirebaseFirestore();
      await _seedFollowing(db, 'friend');
      final expiring = _moment(
        'desktop-expiring',
        expiresAt: _anchor.add(const Duration(seconds: 10)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopMomentsStrip(
              profile: Stream<UserProfile>.value(_profile()),
              feedService: feed,
              friendService: FriendService(firestore: db, auth: auth),
              followService: FollowService(firestore: db, auth: auth),
              currentUserId: 'me',
              expiryClock: () => clock.now,
              onOpenMoment: (_) {},
              onCreateMoment: () {},
              onSeeAll: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      feed.emit([expiring]);
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump(const Duration(milliseconds: 2));

      final tile = find.byKey(
        const ValueKey('desktop-home-moment-desktop-expiring'),
      );
      final tileInk = tester.widget<InkWell>(
        find.descendant(of: tile, matching: find.byType(InkWell)).first,
      );
      tileInk.focusNode!.requestFocus();
      await tester.pump();
      expect(tileInk.focusNode!.hasFocus, isTrue);

      clock.now = expiring.expiresAt!;
      feed.emit(const <VoiceMoment>[]);
      await tester.pump();
      await tester.pump();

      final heading = tester.widget<MomentExpiryFocusTarget>(
        find.byKey(const ValueKey('desktop-home-moments-heading')),
      );
      expect(heading.focusNode.hasFocus, isTrue);
      expect(_messages(announcements), [
        'One Voice Moment expired and was removed from Home.',
      ]);

      feed.emit(const <VoiceMoment>[]);
      await tester.pump();
      expect(_messages(announcements), hasLength(1));
      semantics.dispose();
    },
  );

  testWidgets('desktop expiry stays silent for a hidden non-followed Moment', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    final announcements = _captureAnnouncements(tester);
    final clock = _Clock(_anchor);
    final feed = _ControlledFeed(auth);
    addTearDown(feed.close);
    final db = FakeFirebaseFirestore();
    final hidden = _moment(
      'hidden-friend-only',
      authorId: 'not-followed',
      authorName: 'Hidden user',
      expiresAt: _anchor.add(const Duration(seconds: 10)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopMomentsStrip(
            profile: Stream<UserProfile>.value(_profile()),
            feedService: feed,
            friendService: FriendService(firestore: db, auth: auth),
            followService: FollowService(firestore: db, auth: auth),
            currentUserId: 'me',
            expiryClock: () => clock.now,
            onOpenMoment: (_) {},
            onCreateMoment: () {},
            onSeeAll: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    feed.emit([hidden]);
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump(const Duration(milliseconds: 2));
    expect(find.text('Hidden user'), findsNothing);

    clock.now = hidden.expiresAt!;
    feed.emit(const <VoiceMoment>[]);
    await tester.pump();
    await tester.pump();

    expect(_messages(announcements), isEmpty);
    semantics.dispose();
  });

  testWidgets('cached desktop Home strip stays silent while hidden', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final announcements = _captureAnnouncements(tester);
    final clock = _Clock(_anchor);
    final feed = _ControlledFeed(auth);
    addTearDown(feed.close);
    final visibleFocus = FocusNode(debugLabel: 'visible cached tab');
    addTearDown(visibleFocus.dispose);
    final expiring = _moment(
      'hidden-expiring',
      expiresAt: _anchor.add(const Duration(seconds: 10)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IndexedStack(
            index: 1,
            children: [
              DesktopMomentsStrip(
                profile: Stream<UserProfile>.value(_profile()),
                feedService: feed,
                currentUserId: 'me',
                expiryClock: () => clock.now,
                onOpenMoment: (_) {},
                onCreateMoment: () {},
                onSeeAll: () {},
              ),
              Center(
                child: FilledButton(
                  focusNode: visibleFocus,
                  onPressed: () {},
                  child: const Text('Visible tab'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    feed.emit([expiring]);
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump(const Duration(milliseconds: 2));
    visibleFocus.requestFocus();
    await tester.pump();

    clock.now = expiring.expiresAt!;
    feed.emit(const <VoiceMoment>[]);
    await tester.pump();
    await tester.pump();

    expect(_messages(announcements), isEmpty);
    expect(visibleFocus.hasFocus, isTrue);
    semantics.dispose();
  });

  testWidgets(
    'Following expires a focused social-only row before replacing its cache',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      final announcements = _captureAnnouncements(tester);
      final clock = _Clock(_anchor);
      final feed = _ControlledFeed(auth);
      addTearDown(feed.close);
      final expiring = _moment(
        'social-only',
        expiresAt: _anchor.add(const Duration(seconds: 10)),
      );
      final moments = MomentService(
        firestore: FakeFirebaseFirestore(),
        auth: auth,
        storage: MockFirebaseStorage(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsScreen(
            initialTab: MomentsTab.following,
            auth: auth,
            feedService: feed,
            momentService: moments,
            discoveryService: _EmptyDiscovery(auth),
            expiryClock: () => clock.now,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      feed.emit([expiring]);
      for (var attempt = 0; attempt < 5; attempt += 1) {
        await tester.pump(const Duration(milliseconds: 10));
        if (find
            .byKey(const ValueKey('moment-row-social-only'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      await tester.pump(const Duration(milliseconds: 2));
      expect(
        find.byKey(const ValueKey('moment-row-social-only')),
        findsOneWidget,
      );
      Focus.of(
        tester.element(
          find.byKey(const ValueKey('moment-row-title-social-only')),
        ),
      ).requestFocus();
      await tester.pump();

      clock.now = expiring.expiresAt!;
      feed.emit(const <VoiceMoment>[]);
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('moment-row-social-only')),
        findsNothing,
      );
      final reload = tester.widget<IconButton>(
        find.byKey(const ValueKey('moments-discovery-refresh')),
      );
      expect(reload.focusNode!.hasFocus, isTrue);
      expect(_messages(announcements), [
        'One Voice Moment expired and was removed.',
      ]);

      feed.emit(const <VoiceMoment>[]);
      await tester.pump();
      expect(_messages(announcements), hasLength(1));

      final distinctAtSameClock = _moment(
        'social-distinct-same-clock',
        expiresAt: clock.now,
      );
      feed.emit([distinctAtSameClock]);
      await tester.pump();
      expect(_messages(announcements), [
        'One Voice Moment expired and was removed.',
        'One Voice Moment expired and was removed.',
      ]);

      // The same removed-id set at the same instant is still one transition.
      feed.emit([distinctAtSameClock]);
      await tester.pump();
      expect(_messages(announcements), hasLength(2));
      semantics.dispose();
    },
  );
}
