import 'dart:async';

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
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

const _viewer = 'owner';

VoiceMoment _moment(String id, {String author = _viewer}) {
  final now = DateTime.now();
  return VoiceMoment(
    id: id,
    authorId: author,
    authorName: author,
    authorPhotoUrl: null,
    caption: 'Recording $id',
    audioUrl: 'https://example.invalid/$id.m4a',
    durationSeconds: 12,
    likeCount: 0,
    commentCount: 0,
    isPublished: true,
    createdAt: now.subtract(const Duration(hours: 1)),
    expiresAt: now.add(const Duration(hours: 23)),
    schemaVersion: 2,
    status: 'published',
  );
}

class _PendingDiscovery implements MomentDiscoveryService {
  _PendingDiscovery(this.initial);

  final MomentDiscoveryFeed initial;
  final pending = <Completer<MomentDiscoveryFeed>>[];
  int calls = 0;

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) {
    if (++calls == 1) return Future.value(initial);
    final read = Completer<MomentDiscoveryFeed>();
    pending.add(read);
    return read.future;
  }

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
  }) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietFeed extends HomeFeedService {
  _QuietFeed({required super.firestore, required super.auth});

  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream.value(const []);
}

/// Only the server transport is replaced. The widget calls the real
/// MomentService.deleteMoment (including its author guard and wire payload).
/// This is not evidence of a deployed callable or real Firebase deletion.
class _DeleteFunctions implements FirebaseFunctions {
  _DeleteFunctions(this.db);

  final FakeFirebaseFirestore db;
  final acknowledged = Completer<void>();
  final calls = <({String name, Map<String, dynamic> payload})>[];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _DeleteCallable(this, name);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeleteCallable implements HttpsCallable {
  _DeleteCallable(this.owner, this.name);

  final _DeleteFunctions owner;
  final String name;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async {
    final payload = Map<String, dynamic>.from(parameters! as Map);
    owner.calls.add((name: name, payload: payload));
    await owner.acknowledged.future;
    await owner.db.collection('voiceMoments').doc(payload['momentId']).delete();
    return _Result<T>({'success': true} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Result<T> implements HttpsCallableResult<T> {
  _Result(this.data);

  @override
  final T data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'Voice confirmed deletion survives an earlier read and merged page',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _viewer),
      );
      final previousIdentity = PublicIdentityRepository.instance;
      PublicIdentityRepository.instance = PublicIdentityRepository(
        auth: auth,
        fetchOverride: (uids) async => <String, dynamic>{
          for (final uid in uids)
            uid: {'uid': uid, 'role': 'user', 'vip': false},
        },
        flushDelay: const Duration(milliseconds: 1),
      );
      final db = FakeFirebaseFirestore();
      final own = _moment('own');
      final other = _moment('other', author: 'friend');
      final next = _moment('next', author: 'friend');
      await db.collection('voiceMoments').doc(own.id).set({
        'authorId': own.authorId,
        'authorName': own.authorName,
        'caption': own.caption,
        'audioUrl': own.audioUrl,
        'durationSeconds': own.durationSeconds,
        'likeCount': 0,
        'commentCount': 0,
        'isPublished': true,
        'createdAt': Timestamp.fromDate(own.createdAt!),
        'expiresAt': Timestamp.fromDate(own.expiresAt!),
        'schemaVersion': 2,
        'status': 'published',
        'isDeleted': false,
      });
      var pageCalls = 0;
      final initial = MomentDiscoveryFeed(
        moments: [own, other],
        fetchedCount: 2,
        drops: const {},
        seed: 7,
        poolExhausted: true,
        nextCursor: 'opaque-next',
        loadMore: () async {
          pageCalls++;
          // Paging merges the previous page with fresh records. Its previous
          // projection must not resurrect an item already deleted by this user.
          return MomentDiscoveryFeed(
            moments: [own, other, next],
            fetchedCount: 3,
            drops: const {},
            seed: 7,
            poolExhausted: false,
          );
        },
      );
      final discovery = _PendingDiscovery(initial);
      final functions = _DeleteFunctions(db);
      final moments = MomentService(
        firestore: db,
        auth: auth,
        storage: MockFirebaseStorage(),
        functions: functions,
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: MomentsFeedView(
                onRecord: () {},
                auth: auth,
                momentService: moments,
                feedService: _QuietFeed(firestore: db, auth: auth),
                discoveryService: discovery,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('moment-row-menu-own')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('moment-row-delete-own')));
        await tester.pumpAndSettle();
        expect(find.text('Delete this moment?'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('moment-delete-confirm')));
        await tester.pumpAndSettle();

        expect(functions.calls.single.name, 'deleteMoment');
        expect(functions.calls.single.payload['momentId'], 'own');
        expect(functions.calls.single.payload['requestId'], isNotEmpty);
        expect(discovery.pending, isNotEmpty);
        final readsBeforeDeleteAck = List.of(discovery.pending);
        expect(find.byKey(const ValueKey('moment-row-own')), findsOneWidget);

        functions.acknowledged.complete();
        await tester.pumpAndSettle();
        expect(
          (await db.collection('voiceMoments').doc('own').get()).exists,
          isFalse,
        );
        expect(find.text('Voice Moment deleted.'), findsOneWidget);
        expect(find.byKey(const ValueKey('moment-row-own')), findsNothing);

        // This response was REQUESTED before the delete ACK. An old snapshot
        // arriving now is a legitimate race, not a permanently stale backend.
        for (final read in readsBeforeDeleteAck) {
          read.complete(initial);
        }
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('moment-row-own')),
          findsNothing,
          reason: 'An older read cannot undo a confirmed local deletion.',
        );
        expect(find.byKey(const ValueKey('moment-row-other')), findsOneWidget);

        // Removing a record must retain the real opaque continuation too.
        final loadMore = find.byKey(const ValueKey('moments-load-more'));
        expect(loadMore, findsOneWidget);
        await tester.ensureVisible(loadMore);
        await tester.pump();
        await tester.tap(loadMore);
        await tester.pumpAndSettle();
        expect(pageCalls, 1);
        expect(find.byKey(const ValueKey('moment-row-own')), findsNothing);
        expect(find.byKey(const ValueKey('moment-row-next')), findsOneWidget);
        expect(find.byKey(const ValueKey('moment-row-other')), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        if (!functions.acknowledged.isCompleted) {
          functions.acknowledged.complete();
        }
        for (final read in discovery.pending) {
          if (!read.isCompleted) read.complete(initial);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        PublicIdentityRepository.instance = previousIdentity;
      }
    },
  );
}
