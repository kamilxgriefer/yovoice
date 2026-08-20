// Home's "Your Moment" tile: the reported "I click my own avatar and
// nothing happens".
//
// Two separate defects met on that tile, and both are pinned here.
//
//  1. DEAD PIXELS. Every other tile in the desktop rail wrapped its whole
//     column in one InkWell. Your own tile wrapped only the 66 pt disc,
//     so the "Your Moment" label and the "New" / duration line under it
//     were not a tap target at all — a click that landed a few pixels low
//     did nothing. Reproduced with a widget test before the fix: tapping
//     the label fired neither callback.
//
//  2. NO ENTRY POINT ON A PHONE. The mobile strip's own bubble always
//     opened the recorder, and the whole strip was hidden when nobody
//     else had posted — so on a phone your own Moment could not be opened
//     from Home under any circumstances.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_moments_strip.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home_sections.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/profile/data/models/profile_visibility.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

const _me = 'me';

UserProfile _profile() => UserProfile(
  uid: _me,
  email: 'me@example.com',
  displayName: 'Kamil',
  username: 'kamil',
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
  momentCount: 1,
  reactionCount: 0,
  hostMinutes: 0,
  selectedTitleId: '',
  unlockedTitleIds: const [],
  unlockedTitleTimestamps: const {},
  createdAt: DateTime(2026, 1, 1),
  profileVisibility: ProfileVisibility.public,
);

VoiceMoment _mine() => VoiceMoment(
  id: 'mine',
  authorId: _me,
  authorName: 'Kamil',
  authorPhotoUrl: null,
  caption: 'hello',
  audioUrl: 'https://cdn.example/mine.m4a',
  durationSeconds: 2,
  likeCount: 1,
  commentCount: 1,
  isPublished: true,
  // Inside the 24 hour window, so the tile renders its "New" line — the
  // exact state the report described.
  createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
  schemaVersion: 2,
  status: 'published',
);

class _Feed extends HomeFeedService {
  _Feed(this.moments, {super.firestore, super.auth});

  final List<VoiceMoment> moments;

  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream<List<VoiceMoment>>.value(moments);
}

void main() {
  late PublicIdentityRepository originalIdentity;

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  group('the desktop People & Moments rail', () {
    Future<({List<String> opened, List<int> created})> pumpStrip(
      WidgetTester tester, {
      required List<VoiceMoment> moments,
    }) async {
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _me),
      );
      final opened = <String>[];
      final created = <int>[];

      await tester.binding.setSurfaceSize(const Size(1176, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopMomentsStrip(
              profile: Stream<UserProfile>.value(_profile()),
              feedService: _Feed(moments, firestore: db, auth: auth),
              friendService: FriendService(firestore: db, auth: auth),
              followService: FollowService(firestore: db, auth: auth),
              currentUserId: _me,
              onOpenMoment: (moment) => opened.add(moment.id),
              onCreateMoment: () => created.add(1),
              onSeeAll: () {},
              onDiscover: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      return (opened: opened, created: created);
    }

    testWidgets('tapping the LABEL under your avatar opens your Moment — the '
        'dead-pixel defect', (tester) async {
      final calls = await pumpStrip(tester, moments: [_mine()]);

      // The state the report described: a Moment posted minutes ago, so
      // the tile reads "Your Moment / New".
      expect(find.text('Your Moment'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);

      // Before the fix this fired nothing at all.
      await tester.tap(find.text('Your Moment'));
      await tester.pump();
      expect(calls.opened, ['mine']);
      expect(calls.created, isEmpty);

      // The status line under it is part of the same target.
      await tester.tap(find.text('New'));
      await tester.pump();
      expect(calls.opened, ['mine', 'mine']);
    });

    testWidgets('the plus badge still records rather than playing', (
      tester,
    ) async {
      final calls = await pumpStrip(tester, moments: [_mine()]);

      await tester.tap(find.byKey(const ValueKey('home-record-moment')));
      await tester.pump();

      expect(calls.created, hasLength(1));
      expect(
        calls.opened,
        isEmpty,
        reason: 'the nested badge must win its own area',
      );
    });

    testWidgets('with no Moment of your own the tile opens the recorder', (
      tester,
    ) async {
      final calls = await pumpStrip(tester, moments: const []);

      expect(find.text('Record'), findsOneWidget);
      await tester.tap(find.text('Your Moment'));
      await tester.pump();

      expect(calls.created, hasLength(1));
      expect(calls.opened, isEmpty);
    });
  });

  group('the mobile Moments strip', () {
    Future<({List<String> opened, List<int> created})> pumpStrip(
      WidgetTester tester, {
      required List<VoiceMoment> moments,
    }) async {
      final opened = <String>[];
      final created = <int>[];

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: MobileMomentsStrip(
                moments: moments,
                profile: _profile(),
                currentUserId: _me,
                onOpenMoment: (moment) => opened.add(moment.id),
                onCreateMoment: () => created.add(1),
                onDiscover: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (opened: opened, created: created);
    }

    testWidgets('your own bubble plays your Moment instead of always opening '
        'the recorder', (tester) async {
      final calls = await pumpStrip(tester, moments: [_mine()]);

      await tester.tap(find.byKey(const ValueKey('home-your-moment')));
      await tester.pump();

      expect(calls.opened, ['mine']);
      expect(calls.created, isEmpty);
    });

    testWidgets('your own bubble survives a quiet circle — it was hidden '
        'entirely when nobody else had posted', (tester) async {
      final calls = await pumpStrip(tester, moments: [_mine()]);

      expect(find.byKey(const ValueKey('home-your-moment')), findsOneWidget);
      // The quiet-circle copy is still shown beside it, not instead of it.
      expect(
        find.textContaining('No Moments from your circle yet'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(calls.created, isEmpty);
    });

    testWidgets('the plus badge records, and with no Moment of your own the '
        'bubble does too', (tester) async {
      final withMine = await pumpStrip(tester, moments: [_mine()]);
      await tester.tap(find.byKey(const ValueKey('home-record-moment')));
      await tester.pump();
      expect(withMine.created, hasLength(1));
      expect(withMine.opened, isEmpty);

      final withoutMine = await pumpStrip(tester, moments: const []);
      await tester.tap(find.byKey(const ValueKey('home-your-moment')));
      await tester.pump();
      expect(withoutMine.created, hasLength(1));
      expect(withoutMine.opened, isEmpty);
    });
  });
}
