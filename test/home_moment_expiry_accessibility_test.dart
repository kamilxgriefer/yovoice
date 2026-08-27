import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_moments_strip.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home_sections.dart';
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

VoiceMoment _moment(String id, {required DateTime expiresAt}) => VoiceMoment(
  id: id,
  authorId: 'friend',
  authorName: 'Friend',
  authorPhotoUrl: null,
  caption: 'caption $id',
  audioUrl: 'https://cdn.example/$id.m4a',
  durationSeconds: 12,
  likeCount: 0,
  commentCount: 0,
  isPublished: true,
  createdAt: _anchor.subtract(const Duration(minutes: 5)),
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

  testWidgets(
    'visible mobile Home strip announces once and recovers a removed tile',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      final announcements = _captureAnnouncements(tester);
      final clock = _Clock(_anchor);
      final expiring = _moment(
        'mobile-expiring',
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
              onDiscover: () {},
            ),
          ),
        ),
      );

      await pump([expiring]);
      final tile = find.byKey(const ValueKey('home-moment-mobile-expiring'));
      final tileInk = tester.widget<InkWell>(
        find.descendant(of: tile, matching: find.byType(InkWell)).first,
      );
      tileInk.focusNode!.requestFocus();
      await tester.pump();
      expect(tileInk.focusNode!.hasFocus, isTrue);

      clock.now = expiring.expiresAt!;
      await pump(const <VoiceMoment>[]);
      await tester.pump();

      final heading = tester.widget<MomentExpiryFocusTarget>(
        find.byKey(const ValueKey('mobile-home-moments-heading')),
      );
      expect(heading.focusNode.hasFocus, isTrue);
      expect(_messages(announcements), [
        'One Voice Moment expired and was removed from Home.',
      ]);

      await pump(const <VoiceMoment>[]);
      expect(_messages(announcements), hasLength(1));
      semantics.dispose();
    },
  );

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
              onDiscover: () {},
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
                onDiscover: () {},
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
