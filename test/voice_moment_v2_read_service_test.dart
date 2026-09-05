import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';

const _createdAtMillis = 1_800_000_000_000;
const _reportReceipt = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<Object?, Object?> _moment({
  String id = 'moment_1',
  String authorId = 'oidc:tenant|user',
  int likes = 2,
}) => <Object?, Object?>{
  'schemaVersion': 2,
  'momentId': id,
  'authorId': authorId,
  'authorName': 'Safe author',
  'authorPhotoUrl': null,
  'caption': 'A projected Voice Moment',
  'durationSeconds': 12,
  'likeCount': likes,
  'commentCount': 1,
  'callerLiked': false,
  'createdAtMillis': _createdAtMillis,
  'publishedAtMillis': _createdAtMillis + 1000,
  'expiresAtMillis': _createdAtMillis + 86_400_000,
  'reportReceipt': _reportReceipt,
};

Map<Object?, Object?> _feed({
  required List<Map<Object?, Object?>> moments,
  bool hasMore = false,
  String? cursor,
  int? scannedCount,
}) => <Object?, Object?>{
  'schemaVersion': 2,
  'moments': moments,
  'scannedCount': scannedCount ?? moments.length,
  'hasMore': hasMore,
  'nextCursor': cursor,
};

Map<Object?, Object?> _comment({String id = 'comment_1'}) => <Object?, Object?>{
  'schemaVersion': 2,
  'commentId': id,
  'type': 'text',
  'authorId': 'saml:workspace|commenter',
  'authorName': 'Commenter',
  'authorPhotoUrl': null,
  'text': 'Visible comment',
  'durationSeconds': null,
  'createdAtMillis': _createdAtMillis + 2000,
  'reportReceipt': _reportReceipt,
};

Map<Object?, Object?> _view({
  List<Map<Object?, Object?>>? comments,
  bool truncated = false,
  String? cursor,
}) => <Object?, Object?>{
  'schemaVersion': 2,
  'moment': _moment(),
  'comments': comments ?? <Map<Object?, Object?>>[_comment()],
  'commentsTruncated': truncated,
  'nextCommentCursor': cursor,
  'topReactions': <Map<Object?, Object?>>[
    <Object?, Object?>{
      'userId': 'custom:reaction|uid',
      'displayName': 'Reactor',
      'photoUrl': null,
    },
  ],
};

void main() {
  test('strict v2 feed accepts opaque Firebase UIDs but no media secrets', () {
    final page = VoiceMomentFeedPageV2.parse(
      _feed(moments: <Map<Object?, Object?>>[_moment()]),
    );

    expect(page.moments.single.authorId, 'oidc:tenant|user');
    expect(page.moments.single.audioUrl, isNull);
    expect(page.moments.single.authorPhotoUrl, isNull);
    expect(page.moments.single.hasAuthorizedMedia, isTrue);
    expect(page.moments.single.reportReceipt, _reportReceipt);

    final leaked = _moment()..['audioUrl'] = 'https://durable.invalid/audio';
    expect(
      () => VoiceMomentFeedPageV2.parse(
        _feed(moments: <Map<Object?, Object?>>[leaked]),
      ),
      throwsFormatException,
    );
    final leakedAvatar = _moment()
      ..['authorPhotoUrl'] = 'https://durable.invalid/avatar';
    expect(
      () => VoiceMomentFeedPageV2.parse(
        _feed(moments: <Map<Object?, Object?>>[leakedAvatar]),
      ),
      throwsFormatException,
    );

    final missingReceipt = _moment()..remove('reportReceipt');
    expect(
      () => VoiceMomentFeedPageV2.parse(
        _feed(moments: <Map<Object?, Object?>>[missingReceipt]),
      ),
      throwsFormatException,
    );
    final malformedReceipt = _moment()..['reportReceipt'] = 'short';
    expect(
      () => VoiceMomentFeedPageV2.parse(
        _feed(moments: <Map<Object?, Object?>>[malformedReceipt]),
      ),
      throwsFormatException,
    );
  });

  test('following mode is explicit and cannot pretend to be popular', () async {
    late Map<String, Object?> request;
    final service = VoiceMomentReadService(
      feedInvoker: (payload) async {
        request = payload;
        return _feed(moments: const <Map<Object?, Object?>>[]);
      },
    );

    await service.loadFeedPage(mode: VoiceMomentFeedMode.following);
    expect(request['feedMode'], 'following');
    await expectLater(
      service.loadFeedPage(
        mode: VoiceMomentFeedMode.following,
        sort: VoiceMomentFeedSort.popular,
      ),
      throwsArgumentError,
    );
  });

  test('Home social feed reads only the following v2 projection', () async {
    final requests = <Map<String, Object?>>[];
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'viewer'),
    );
    final home = HomeFeedService(
      firestore: FakeFirebaseFirestore(),
      auth: auth,
      voiceMomentReadService: VoiceMomentReadService(
        feedInvoker: (payload) async {
          requests.add(Map<String, Object?>.of(payload));
          return _feed(moments: const <Map<Object?, Object?>>[]);
        },
      ),
    );

    expect(await home.watchSocialMoments().first, isEmpty);
    expect(requests, hasLength(1));
    expect(requests.single['feedMode'], 'following');
  });

  test(
    'client forwards only the opaque feed cursor and exact sort mode',
    () async {
      late Map<String, Object?> request;
      final service = VoiceMomentReadService(
        feedInvoker: (payload) async {
          request = payload;
          return _feed(moments: const <Map<Object?, Object?>>[]);
        },
      );

      await service.loadFeedPage(
        limit: 4,
        cursor: 'opaque_cursor-2',
        sort: VoiceMomentFeedSort.popular,
      );

      expect(request, <String, Object?>{
        'limit': 4,
        'sortMode': 'popular',
        'feedMode': 'discover',
        'cursor': 'opaque_cursor-2',
      });
    },
  );

  test(
    'strict detail parses safe comments and forwards comment cursor',
    () async {
      late Map<String, Object?> request;
      final service = VoiceMomentReadService(
        viewInvoker: (payload) async {
          request = payload;
          return _view();
        },
      );

      final view = await service.loadView(
        momentId: 'moment_1',
        commentCursor: 'comment_cursor-2',
      );

      expect(view.comments.single.authorId, 'saml:workspace|commenter');
      expect(view.comments.single.authorPhotoUrl, isNull);
      expect(view.comments.single.reportReceipt, _reportReceipt);
      expect(view.topReactions.single.uid, 'custom:reaction|uid');
      expect(request['commentCursor'], 'comment_cursor-2');
      expect(request.keys, <String>{
        'momentId',
        'commentLimit',
        'reactionLimit',
        'commentCursor',
      });
    },
  );

  test('discovery pagination merges v2 pages without duplicates', () async {
    final requests = <Map<String, Object?>>[];
    final discovery = MomentDiscoveryService(
      feedInvoker: (payload) async {
        requests.add(Map<String, Object?>.of(payload));
        if (payload['cursor'] == null) {
          return _feed(
            moments: <Map<Object?, Object?>>[_moment(id: 'moment_1')],
            scannedCount: 1,
            hasMore: true,
            cursor: 'page_2',
          );
        }
        return _feed(
          moments: <Map<Object?, Object?>>[
            _moment(id: 'moment_1'),
            _moment(id: 'moment_2', authorId: 'author:two'),
          ],
          scannedCount: 2,
        );
      },
    );
    final first = await discovery.loadDiscoveryFeed(poolSize: 3, seed: 7);
    expect(first.canLoadMore, isTrue);
    final second = await first.loadMore!();

    expect(second.moments.map((moment) => moment.id).toSet(), <String>{
      'moment_1',
      'moment_2',
    });
    expect(requests.last['cursor'], 'page_2');
    expect(second.canLoadMore, isFalse);
  });

  test(
    'detail permission denial is one indistinguishable gone state',
    () async {
      final readService = VoiceMomentReadService(
        viewInvoker: (_) => throw FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'unavailable',
        ),
      );
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'viewer'),
        signedIn: true,
      );
      final moments = MomentService(
        firestore: FakeFirebaseFirestore(),
        auth: auth,
        storage: MockFirebaseStorage(),
        readService: readService,
      );

      expect(await moments.watchMomentOrMissing('moment_1').first, isNull);
    },
  );
}
