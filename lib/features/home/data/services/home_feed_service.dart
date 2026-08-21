import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';

class HomeFeedService {
  HomeFeedService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functionsOverride = functions;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functionsOverride;

  FirebaseFunctions? get _functions =>
      _functionsOverride ??
      (() {
        try {
          return FirebaseFunctions.instanceFor(region: 'europe-west1');
        } on FirebaseException catch (error) {
          if (error.code == 'no-app') {
            return null;
          }
          rethrow;
        }
      })();

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('User is not signed in.');
    return user.uid;
  }

  String _newRequestId() {
    final random = Random.secure();
    final randomPart = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}-$randomPart';
  }

  bool _isCallableUnavailable(Object error) {
    return error is FirebaseFunctionsException &&
        (error.code == 'unimplemented' ||
            error.code == 'not-found' ||
            error.code == 'no-app');
  }

  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) {
    final controller = StreamController<List<VoiceMoment>>.broadcast();
    var friendIds = <String>{};
    var followingIds = <String>{};
    var moments = <VoiceMoment>[];

    void emit() {
      if (controller.isClosed) return;
      final allowedAuthors = <String>{_uid, ...friendIds, ...followingIds};
      // Expiry is enforced client-side on every surface this stream feeds
      // (Home strips, the social feed, the Following filter): a Moment
      // past its `expiresAt` — or a legacy document with none — must not
      // render during the sweeper's ≤10-minute gap. `isActiveAt` is the
      // single definition of "still alive".
      final now = DateTime.now();
      final filtered = moments
          .where(
            (moment) =>
                allowedAuthors.contains(moment.authorId) &&
                moment.isActiveAt(now),
          )
          .toList(growable: false);
      filtered.sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
      controller.add(filtered);
    }

    final subscriptions = <StreamSubscription<dynamic>>[];

    subscriptions.add(
      _firestore
          .collection('users')
          .doc(_uid)
          .collection('friends')
          .snapshots()
          .listen((snapshot) {
            friendIds = snapshot.docs.map((doc) => doc.id).toSet();
            emit();
          }, onError: controller.addError),
    );

    subscriptions.add(
      _firestore
          .collection('users')
          .doc(_uid)
          .collection('following')
          .snapshots()
          .listen((snapshot) {
            followingIds = snapshot.docs.map((doc) => doc.id).toSet();
            emit();
          }, onError: controller.addError),
    );

    subscriptions.add(
      _firestore
          .collection('voiceMoments')
          .where('isPublished', isEqualTo: true)
          // Ordered NEWEST-FIRST, deliberately. Without an orderBy this
          // limit(40) returned the 40 LOWEST DOCUMENT IDS among published
          // docs — an arbitrary slice. Legacy pre-expiry documents keep
          // isPublished forever (the sweeper skips a missing expiresAt), so
          // they would permanently squat the window while the client-side
          // expiry filter hides them, and a friend's genuinely live Moment
          // whose id sorts late would silently never reach Home or the
          // Following feed. Freshest-first makes the window exactly the 40
          // most recent — live moments always in, squatters aged out. The
          // (isPublished ASC, createdAt DESC) composite this needs is
          // deployed and query-proved.
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .listen((snapshot) {
            moments = snapshot.docs
                .map(VoiceMoment.fromFirestore)
                .toList(growable: false);
            emit();
          }, onError: controller.addError),
    );

    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    };
    return controller.stream;
  }

  /// Home's "Discover clubs" rail.
  ///
  /// ALL THREE EQUALITIES ARE LOAD-BEARING; dropping any one of them
  /// makes the whole query permission-denied rather than merely broader.
  /// `match /clubs/{clubId}`'s list rule reads
  ///
  ///     allow list: if isActiveAccount() &&
  ///         resource.data.privacy == 'public' &&
  ///         resource.data.type == 'community' &&
  ///         resource.data.status == 'active';
  ///
  /// and a Firestore `list` rule is evaluated against the QUERY'S
  /// CONSTRAINTS, never against the documents it would return: a clause on
  /// a bare `resource.data.X` is provable only when the query itself
  /// carries a matching equality filter on X. So this is not defence in
  /// depth over a server-side filter — the filters below ARE how the query
  /// is authorized, and the index is what excludes family rooms, suspended
  /// clubs and private clubs from the result.
  ///
  /// This shape needs no composite index (a zigzag merge join serves three
  /// equalities plus a limit), verified against production with the Admin
  /// SDK. Documents missing `type` or `status` are absent from those
  /// indexes and so never surface here, which is the correct direction for
  /// a discovery rail to fail.
  ///
  /// Until 2026-08-19 this sent only `privacy == 'public'` while the rule
  /// said `allow list: if false`, so the rail was denied for every account
  /// — including a club owner listing their own public club — for the
  /// entire life of the product. The denial was invisible because the rail
  /// read `snapshot.data ?? []` with no `hasError` branch; the error state
  /// added alongside this change is what keeps a future denial audible.
  Stream<List<Club>> watchSuggestedClubs({int limit = 8}) {
    return _firestore
        .collection('clubs')
        .where('privacy', isEqualTo: 'public')
        .where('type', isEqualTo: 'community')
        .where('status', isEqualTo: 'active')
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final clubs = snapshot.docs.map(Club.fromFirestore).toList();
          clubs.sort((a, b) => b.memberCount.compareTo(a.memberCount));
          return clubs;
        });
  }

  Stream<bool> watchLiked(String momentId) {
    return _firestore
        .collection('voiceMoments')
        .doc(momentId)
        .collection('likes')
        .doc(_uid)
        .snapshots()
        .map((document) => document.exists);
  }

  Future<void> toggleLike(String momentId) async {
    final like = _firestore
        .collection('voiceMoments')
        .doc(momentId)
        .collection('likes')
        .doc(_uid);

    try {
      final snapshot = await like.get();
      final requestId = _newRequestId();
      final functions = _functions;
      if (functions == null) {
        throw FirebaseFunctionsException(
          code: 'no-app',
          message: 'Cloud Functions unavailable.',
        );
      }
      final callable = functions.httpsCallable('setMomentLike');
      await callable.call<Map<Object?, Object?>>({
        'momentId': momentId,
        'liked': !snapshot.exists,
        'requestId': requestId,
      });
      return;
    } catch (error) {
      if (!_isCallableUnavailable(error)) {
        rethrow;
      }
    }

    final moment = _firestore.collection('voiceMoments').doc(momentId);

    await _firestore.runTransaction((transaction) async {
      final momentSnapshot = await transaction.get(moment);
      final likeSnapshot = await transaction.get(like);
      if (!momentSnapshot.exists) {
        throw StateError('Voice Moment no longer exists.');
      }
      final current =
          (momentSnapshot.data()?['likeCount'] as num?)?.toInt() ?? 0;
      if (likeSnapshot.exists) {
        transaction.delete(like);
        transaction.update(moment, {
          'likeCount': current > 0 ? current - 1 : 0,
        });
      } else {
        transaction.set(like, {
          'userId': _uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(moment, {'likeCount': current + 1});
      }
    });
  }
}
