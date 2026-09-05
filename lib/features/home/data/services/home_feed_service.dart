import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_expiry_scheduler.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';

class HomeFeedService {
  HomeFeedService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    VoiceMomentReadService? voiceMomentReadService,
    MomentExpiryClock? expiryClock,
    MomentExpiryTimerFactory? expiryTimerFactory,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functionsOverride = functions,
       _voiceMomentReadServiceOverride = voiceMomentReadService,
       _expiryClock = expiryClock,
       _expiryTimerFactory = expiryTimerFactory;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functionsOverride;
  final VoiceMomentReadService? _voiceMomentReadServiceOverride;
  final MomentExpiryClock? _expiryClock;
  final MomentExpiryTimerFactory? _expiryTimerFactory;

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

  VoiceMomentReadService get _voiceMomentReads =>
      _voiceMomentReadServiceOverride ??
      VoiceMomentReadService(functions: _functionsOverride);

  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) {
    if (limit < 1 || limit > 40) {
      throw RangeError.range(limit, 1, 40, 'limit');
    }
    final controller = StreamController<List<VoiceMoment>>.broadcast();
    var moments = <VoiceMoment>[];
    DateTime? expiredThrough;
    late final MomentExpiryScheduler expiry;

    void emit([DateTime? deadline]) {
      if (controller.isClosed) return;
      if (deadline != null &&
          (expiredThrough == null || deadline.isAfter(expiredThrough!))) {
        expiredThrough = deadline;
      }
      // Expiry is enforced client-side on every surface this stream feeds
      // (Home strips, the social feed, the Following filter): a Moment
      // past its `expiresAt` must not render during the sweeper's
      // ≤10-minute gap. A document with NO `expiresAt` is PERMANENT under
      // the amended availability contract ("keep until deleted") and
      // stays live. `isActiveAt` is the single definition of "still
      // alive".
      final wallNow = expiry.now();
      final floor = expiredThrough;
      final now = floor != null && floor.isAfter(wallNow) ? floor : wallNow;
      final filtered = moments
          .where((moment) => moment.isActiveAt(now))
          .toList(growable: false);
      filtered.sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
      controller.add(filtered);
      // Firestore will not emit merely because wall time crossed an
      // `expiresAt`. Re-arm one timer for the next finite deadline so the
      // already-delivered list removes it without waiting for the sweeper.
      expiry.schedule(filtered);
    }

    expiry = MomentExpiryScheduler(
      onDeadline: emit,
      clock: _expiryClock,
      timerFactory: _expiryTimerFactory,
    );

    Future<void> load() async {
      final reads = _voiceMomentReads;
      final loaded = <VoiceMoment>[];
      final seen = <String>{};
      String? cursor;
      var scanned = 0;
      do {
        final remaining = limit - scanned;
        final page = await reads.loadFeedPage(
          limit: remaining > 10 ? 10 : remaining,
          cursor: cursor,
          mode: VoiceMomentFeedMode.following,
        );
        scanned += page.scannedCount;
        for (final moment in page.moments) {
          if (seen.add(moment.id)) loaded.add(moment);
        }
        cursor = page.hasMore ? page.nextCursor : null;
      } while (cursor != null && scanned < limit);
      if (controller.isClosed) return;
      moments = List<VoiceMoment>.unmodifiable(loaded);
      emit();
    }

    var started = false;
    controller.onListen = () {
      if (started) return;
      started = true;
      unawaited(
        load().catchError((Object error, StackTrace stackTrace) {
          if (!controller.isClosed) controller.addError(error, stackTrace);
        }),
      );
    };

    controller.onCancel = () {
      expiry.dispose();
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

  /// Compatibility snapshot for older callers.
  ///
  /// Build 20 surfaces render [VoiceMoment.callerLiked] from the v2 projection
  /// and call [setLike] with an explicit desired state. This method deliberately
  /// uses the same server-owned projection rather than reading
  /// `voiceMoments/{id}/likes/{uid}` directly; it therefore cannot bypass the
  /// Moment audience/block/restriction checks.
  Stream<bool> watchLiked(String momentId) => Stream<bool>.fromFuture(
    _voiceMomentReads
        .loadView(momentId: momentId, commentLimit: 1, reactionLimit: 1)
        .then((view) => view.moment.callerLiked),
  );

  /// Sets the caller's like to an explicit desired state through the callable.
  ///
  /// There is intentionally no read-before-write. A local toggle based on a
  /// direct like document both leaked a Firestore access path and raced across
  /// slow connections. The callable is idempotent for the desired boolean and
  /// every UI surface updates optimistically from its v2 `callerLiked` value.
  Future<void> setLike(String momentId, {required bool liked}) async {
    if (_auth.currentUser == null) {
      throw StateError('User is not signed in.');
    }
    try {
      final requestId = _newRequestId();
      final functions = _functions;
      if (functions == null) {
        throw FirebaseFunctionsException(
          code: 'no-app',
          message: 'Cloud Functions unavailable.',
        );
      }
      final callable = functions.httpsCallable('setMomentLike');
      final response = await callable.call<Map<Object?, Object?>>({
        'momentId': momentId,
        'liked': liked,
        'requestId': requestId,
      });
      if (response.data['liked'] != liked) {
        throw const FormatException('Malformed server like response.');
      }
      return;
    } catch (error) {
      if (!_isCallableUnavailable(error)) {
        rethrow;
      }
    }

    throw StateError(
      'Liking needs the YO Voice server right now and it could not be '
      'reached. Try again in a moment.',
    );
  }

  /// Backwards-compatible toggle for non-UI integrations.
  ///
  /// It remains privacy-safe by deriving the current state from v2 and then
  /// delegating to the callable-only desired-state mutation. Production UI
  /// does not use this extra round trip.
  Future<void> toggleLike(String momentId) async {
    final current = await _voiceMomentReads.loadView(
      momentId: momentId,
      commentLimit: 1,
      reactionLimit: 1,
    );
    await setLike(momentId, liked: !current.moment.callerLiked);
  }
}
