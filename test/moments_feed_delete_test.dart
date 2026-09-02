// Ownership on the Moments feed under the availability amendment:
// Delete on OWN Moments only (row overflow, story viewer), the detail
// routes from a row's title and Details item, and the permanent-Moment
// labels ("Stays until deleted" for the author, nothing for others).

import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

const _me = 'me';
final DateTime _anchor = DateTime.now();

VoiceMoment _moment(
  String id, {
  String author = _me,
  String? authorName,
  int likes = 0,
  int comments = 0,
  Duration age = const Duration(hours: 2),

  /// Null = PERMANENT ("keep until deleted") under the amended contract.
  Duration? lifetime = const Duration(hours: 24),
}) {
  final createdAt = _anchor.subtract(age);
  return VoiceMoment(
    id: id,
    authorId: author,
    authorName: authorName ?? 'Author $author',
    authorPhotoUrl: null,
    caption: 'caption $id',
    audioUrl: 'https://cdn.example/$id.m4a',
    durationSeconds: 12,
    likeCount: likes,
    commentCount: comments,
    isPublished: true,
    createdAt: createdAt,
    expiresAt: lifetime == null ? null : createdAt.add(lifetime),
    schemaVersion: 2,
    status: 'published',
  );
}

Map<String, dynamic> _doc(VoiceMoment moment) => <String, dynamic>{
  'authorId': moment.authorId,
  'authorName': moment.authorName,
  'authorPhotoUrl': null,
  'caption': moment.caption,
  'audioUrl': moment.audioUrl,
  'durationSeconds': moment.durationSeconds,
  'likeCount': moment.likeCount,
  'commentCount': moment.commentCount,
  'isPublished': moment.isPublished,
  'createdAt': Timestamp.fromDate(moment.createdAt!),
  if (moment.expiresAt != null)
    'expiresAt': Timestamp.fromDate(moment.expiresAt!),
  'schemaVersion': 2,
  'status': 'published',
  'isDeleted': false,
};

class _StaticDiscovery implements MomentDiscoveryService {
  _StaticDiscovery(this.moments);

  final List<VoiceMoment> moments;

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async => MomentDiscoveryFeed(
    moments: moments,
    fetchedCount: moments.length,
    drops: const <String, MomentDropReason>{},
    seed: seed ?? 0,
    poolExhausted: false,
  );

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
  }) => const Stream<Map<String, MomentEngagement>>.empty();

  @override
  Future<List<VoiceMoment>> topLikedMoments({int limit = 3}) async =>
      moments.take(limit).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietFeed extends HomeFeedService {
  _QuietFeed({super.firestore, super.auth, this.social = const []});

  final List<VoiceMoment> social;

  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream<List<VoiceMoment>>.value(social);

  @override
  Stream<bool> watchLiked(String momentId) => Stream<bool>.value(false);

  @override
  Future<void> toggleLike(String momentId) async {}
}

class _SilentPlayer implements audio.AudioPlayer {
  @override
  Stream<Duration> get onPositionChanged => const Stream<Duration>.empty();

  @override
  Stream<Duration> get onDurationChanged => const Stream<Duration>.empty();

  @override
  Stream<void> get onPlayerComplete => const Stream<void>.empty();

  @override
  Future<void> play(
    audio.Source source, {
    double? volume,
    double? balance,
    audio.AudioContext? ctx,
    Duration? position,
    audio.PlayerMode? mode,
  }) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A real service over the fake DB whose delete can be forced to fail, so
/// the failure branch is testable without breaking the fake.
class _FailingDeleteService extends MomentService {
  _FailingDeleteService({
    required super.firestore,
    required super.auth,
    required super.storage,
  });

  bool failDelete = false;

  /// Stands in for the SERVER half of deletion. The real
  /// MomentService.deleteMoment now invokes the deployed `deleteMoment`
  /// callable (the client-side subcollection sweep failed
  /// permission-denied on any Moment somebody else had liked or commented
  /// — rules only let each engager delete their own docs), and
  /// fake_cloud_firestore has no callable runtime. The double keeps the
  /// client-side ownership guard and then performs what the callable's
  /// canonical cleanup would: the document goes. The callable NAME and
  /// PAYLOAD are pinned separately in the 'delete wiring' test below.
  @override
  Future<void> deleteMoment(VoiceMoment moment) async {
    if (failDelete) throw StateError('backend said no');
    final uid = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: _me),
    ).currentUser!.uid;
    if (moment.authorId != uid) {
      throw StateError('You can only delete your own Voice Moments.');
    }
    await FakeDeleteBackend.instance!.delete(moment.id);
  }
}

/// The fake "server": deletes the doc the way the callable's canonical
/// cleanup does, from whichever FakeFirebaseFirestore the test seeded.
class FakeDeleteBackend {
  FakeDeleteBackend(this.db);
  static FakeDeleteBackend? instance;
  final FakeFirebaseFirestore db;
  Future<void> delete(String momentId) =>
      db.collection('voiceMoments').doc(momentId).delete();
}

void main() {
  _deleteWiringTests();
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

  MockFirebaseAuth authMe() =>
      MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me));

  late FakeFirebaseFirestore db;

  Future<_FailingDeleteService> seeded(List<VoiceMoment> mine) async {
    db = FakeFirebaseFirestore();
    FakeDeleteBackend.instance = FakeDeleteBackend(db);
    for (final moment in mine) {
      await db.collection('voiceMoments').doc(moment.id).set(_doc(moment));
    }
    return _FailingDeleteService(
      firestore: db,
      auth: authMe(),
      storage: MockFirebaseStorage(),
    );
  }

  Future<void> pumpFollowing(
    WidgetTester tester, {
    required MomentService moments,
    List<VoiceMoment> social = const [],
    void Function(VoiceMoment moment)? onOpenDetail,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: MomentsScreen(
          initialTab: MomentsTab.following,
          momentService: moments,
          auth: authMe(),
          feedService: _QuietFeed(
            firestore: FakeFirebaseFirestore(),
            auth: authMe(),
            social: social,
          ),
          discoveryService: _StaticDiscovery(const []),
          onOpenDetail: onOpenDetail,
          playerFactory: _SilentPlayer.new,
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  group('row overflow delete', () {
    testWidgets('the author deletes from the row menu: exact destructive '
        'copy, the row goes immediately, the document goes for real', (
      tester,
    ) async {
      final moments = await seeded([
        _moment('mine-1', age: const Duration(hours: 1)),
        _moment('mine-2', age: const Duration(hours: 3)),
      ]);
      await pumpFollowing(tester, moments: moments);

      expect(find.byKey(const ValueKey('moment-row-mine-1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('moment-row-menu-mine-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('moment-row-delete-mine-1')));
      await tester.pumpAndSettle();

      // The exact destructive copy.
      expect(find.text('Delete this moment?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('moment-delete-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('moment-row-mine-1')), findsNothing);
      expect(find.byKey(const ValueKey('moment-row-mine-2')), findsOneWidget);
      expect(find.text('Voice Moment deleted.'), findsOneWidget);
      final snapshot = await db.collection('voiceMoments').doc('mine-1').get();
      expect(snapshot.exists, isFalse);
    });

    testWidgets('a failed delete keeps the row and says so', (tester) async {
      final moments = await seeded([
        _moment('mine-1', age: const Duration(hours: 1)),
      ]);
      moments.failDelete = true;
      await pumpFollowing(tester, moments: moments);

      await tester.tap(find.byKey(const ValueKey('moment-row-menu-mine-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('moment-row-delete-mine-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('moment-delete-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('moment-row-mine-1')), findsOneWidget);
      expect(
        find.text('The Moment could not be deleted. Try again.'),
        findsOneWidget,
      );
    });

    testWidgets('a non-author never sees Delete — anywhere on the row', (
      tester,
    ) async {
      final moments = await seeded(const []);
      await pumpFollowing(
        tester,
        moments: moments,
        social: [_moment('theirs', author: 'friend', authorName: 'Ola')],
      );

      await tester.tap(find.byKey(const ValueKey('moment-row-menu-theirs')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('moment-row-delete-theirs')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('moment-row-report-theirs')),
        findsOneWidget,
      );
      expect(find.text('Delete'), findsNothing);
    });
  });

  group('the story viewer delete', () {
    testWidgets('the author deletes the only link: confirmation, the viewer '
        'closes, the feed row is gone', (tester) async {
      final moments = await seeded([
        _moment('mine-1', age: const Duration(hours: 1)),
      ]);
      await pumpFollowing(tester, moments: moments);

      await tester.tap(find.byKey(const ValueKey('moments-chain-me')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('story-delete-mine-1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story-delete-mine-1')));
      await tester.pumpAndSettle();

      expect(find.text('Delete this moment?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story-delete-confirm')));
      await tester.pumpAndSettle();

      // The viewer closed (its close control is gone) and the feed lost
      // the row.
      expect(find.byKey(const ValueKey('story-close')), findsNothing);
      expect(find.byKey(const ValueKey('moment-row-mine-1')), findsNothing);
      final snapshot = await db.collection('voiceMoments').doc('mine-1').get();
      expect(snapshot.exists, isFalse);
    });

    testWidgets('someone else\'s Moment in the viewer offers Report, never '
        'Delete', (tester) async {
      final moments = await seeded(const []);
      await pumpFollowing(
        tester,
        moments: moments,
        social: [_moment('theirs', author: 'friend', authorName: 'Ola')],
      );

      await tester.tap(find.byKey(const ValueKey('moments-chain-friend')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('story-report-theirs')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-delete-theirs')), findsNothing);
    });
  });

  group('the detail route', () {
    testWidgets('a row\'s title opens the detail page and Back returns to '
        'the feed', (tester) async {
      final moments = await seeded([
        _moment('mine-1', age: const Duration(hours: 1)),
      ]);
      await pumpFollowing(tester, moments: moments);

      await tester.tap(find.byKey(const ValueKey('moment-row-title-mine-1')));
      await tester.pumpAndSettle();

      expect(find.byType(MomentDetailScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-detail-play')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('moment-detail-back')));
      await tester.pumpAndSettle();
      expect(find.byType(MomentDetailScreen), findsNothing);
      expect(find.byKey(const ValueKey('moment-row-mine-1')), findsOneWidget);
    });

    testWidgets('the overflow menu\'s Details item is the same destination', (
      tester,
    ) async {
      final moments = await seeded([
        _moment('mine-1', age: const Duration(hours: 1)),
      ]);
      await pumpFollowing(tester, moments: moments);

      await tester.tap(find.byKey(const ValueKey('moment-row-menu-mine-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();

      expect(find.byType(MomentDetailScreen), findsOneWidget);
    });

    testWidgets('when the shell provides onOpenDetail the feed routes '
        'through it instead of pushing its own page', (tester) async {
      final moments = await seeded([
        _moment('mine-1', age: const Duration(hours: 1)),
      ]);
      VoiceMoment? opened;
      await pumpFollowing(
        tester,
        moments: moments,
        onOpenDetail: (moment) => opened = moment,
      );

      await tester.tap(find.byKey(const ValueKey('moment-row-title-mine-1')));
      await tester.pumpAndSettle();

      expect(opened?.id, 'mine-1');
      expect(find.byType(MomentDetailScreen), findsNothing);
    });
  });

  group('permanent Moments on the feed', () {
    testWidgets('the author\'s permanent row says "Stays until deleted" and '
        'never counts down', (tester) async {
      final moments = await seeded([
        _moment('mine-forever', lifetime: null, age: const Duration(hours: 1)),
      ]);
      await pumpFollowing(tester, moments: moments);

      expect(
        find.byKey(const ValueKey('moment-row-mine-forever')),
        findsOneWidget,
        reason:
            'a null expiresAt is PERMANENT and must render '
            '(the ADR-101 amendment)',
      );
      expect(find.text('Stays until deleted'), findsOneWidget);
      expect(find.textContaining('Expires in'), findsNothing);
    });

    testWidgets('someone else\'s permanent Moment renders with NO expiry '
        'label at all', (tester) async {
      final moments = await seeded(const []);
      await pumpFollowing(
        tester,
        moments: moments,
        social: [
          _moment(
            'theirs-forever',
            author: 'friend',
            authorName: 'Ola',
            lifetime: null,
          ),
        ],
      );

      expect(
        find.byKey(const ValueKey('moment-row-theirs-forever')),
        findsOneWidget,
      );
      expect(find.text('Stays until deleted'), findsNothing);
      expect(find.textContaining('Expires in'), findsNothing);
    });

    testWidgets('a timed own row still shows its real countdown', (
      tester,
    ) async {
      final moments = await seeded([
        _moment('mine-timed', age: const Duration(hours: 2)),
      ]);
      await pumpFollowing(tester, moments: moments);

      expect(find.textContaining('Expires in'), findsOneWidget);
      expect(find.text('Stays until deleted'), findsNothing);
    });
  });
}

/// The one test of the REAL wiring: production deleteMoment must invoke the
/// deployed `deleteMoment` callable with exactly {momentId, requestId} — the
/// widget tests above stand the server in, so without this pin the callable
/// routing itself would be unproven.
void _deleteWiringTests() {
  test('MomentService.deleteMoment calls the deleteMoment callable with '
      'momentId and a requestId', () async {
    final functions = _WireFunctions();
    final service = MomentService(
      firestore: FakeFirebaseFirestore(),
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      storage: MockFirebaseStorage(),
      functions: functions,
    );
    await service.deleteMoment(
      _moment('mine-9', age: const Duration(hours: 1)),
    );
    expect(functions.calls, hasLength(1));
    expect(functions.calls.single.name, 'deleteMoment');
    expect(functions.calls.single.payload['momentId'], 'mine-9');
    expect(
      functions.calls.single.payload['requestId'],
      isA<String>().having((id) => id.isNotEmpty, 'non-empty', isTrue),
    );
  });

  test('with no Functions the delete refuses loudly instead of sweeping '
      'subcollections client-side', () async {
    final service = MomentService(
      firestore: FakeFirebaseFirestore(),
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _me)),
      storage: MockFirebaseStorage(),
    );
    await expectLater(
      service.deleteMoment(_moment('mine-9', age: const Duration(hours: 1))),
      throwsA(isA<StateError>()),
    );
  });
}

class _WireCall {
  _WireCall(this.name, this.payload);
  final String name;
  final Map<String, dynamic> payload;
}

class _WireFunctions implements FirebaseFunctions {
  final calls = <_WireCall>[];
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _WireCallable(this, name);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WireCallable implements HttpsCallable {
  _WireCallable(this.owner, this.name);
  final _WireFunctions owner;
  final String name;
  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async {
    owner.calls.add(
      _WireCall(name, Map<String, dynamic>.from(parameters! as Map)),
    );
    return _WireResult<T>({'success': true} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WireResult<T> implements HttpsCallableResult<T> {
  _WireResult(this.data);
  @override
  final T data;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
