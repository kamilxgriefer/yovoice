import 'dart:async';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_upload.dart';

enum ReelAssetKind { media, backingAudio }

typedef ReelCallableInvoker =
    Future<Map<Object?, Object?>> Function(
      String name,
      Map<String, Object?> payload,
    );

typedef ReelUploadInvoker =
    Future<String> Function({
      required String storagePath,
      required ReelUploadPayload payload,
      required Map<String, String> metadata,
      void Function(double progress)? onProgress,
    });

@immutable
class ReelDraftPlan {
  const ReelDraftPlan({
    required this.media,
    required this.composition,
    this.backingAudio,
    this.availability = ReelAvailabilityChoice.fallback,
  });

  final ReelUploadPayload media;
  final ReelUploadPayload? backingAudio;
  final ReelComposition composition;
  final ReelAvailabilityChoice availability;

  String? validate() {
    if (media.mediaKind == ReelMediaKind.image &&
        media.size > maxReelImageBytes) {
      return 'The selected image is too large.';
    }
    if (media.mediaKind == ReelMediaKind.video &&
        media.size > maxReelVideoBytes) {
      return 'The selected video is too large.';
    }
    final audio = backingAudio;
    if (audio != null &&
        (!audio.contentType.startsWith('audio/') ||
            audio.size > maxReelBackingAudioBytes)) {
      return 'The selected backing audio is unsupported.';
    }
    return composition.validate(
      mediaKind: media.mediaKind,
      durationMs: media.durationMs,
      hasBackingAudio: audio != null,
    );
  }
}

/// Retry-stable state for one publish. A lost reserve/upload/finalize response
/// reuses the same request id, object paths and generations instead of creating
/// duplicate Reels or orphan uploads.
class ReelPublishSession {
  ReelPublishSession({required this.plan, String? requestId})
    : requestId = requestId ?? newRequestId();

  final ReelDraftPlan plan;
  final String requestId;
  String? reelId;
  String? mediaStoragePath;
  String? backingAudioStoragePath;
  String? mediaGeneration;
  String? backingAudioGeneration;
  DateTime? reservationExpiresAt;
  DateTime? contentExpiresAt;
  String? _ownerId;
  int? _identityEpoch;
  bool _identityInvalidated = false;

  void _bindIdentity(String uid, int epoch) {
    if (_identityInvalidated ||
        (_ownerId != null && (_ownerId != uid || _identityEpoch != epoch))) {
      _identityInvalidated = true;
      throw StateError('This Reel draft belongs to an ended sign-in session.');
    }
    _ownerId ??= uid;
    _identityEpoch ??= epoch;
  }

  static String newRequestId() {
    final random = Random.secure();
    return List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

class ReelService {
  ReelService({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
    ReelCallableInvoker? callableInvoker,
    ReelUploadInvoker? uploadInvoker,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _functionsOverride = functions,
       _storage = storage,
       _callableInvoker = callableInvoker,
       _uploadInvoker = uploadInvoker;

  final FirebaseAuth _auth;
  final FirebaseFunctions? _functionsOverride;
  final FirebaseStorage? _storage;
  final ReelCallableInvoker? _callableInvoker;
  final ReelUploadInvoker? _uploadInvoker;

  static final Map<String, _CachedReelGrant> _grantCache = {};
  static int _grantEpoch = 0;
  final Map<String, Future<Uri>> _pendingGrants = {};
  final Map<String, String> _deleteRequestIds = <String, String>{};

  /// Retry-stable request ids for the engagement callables, keyed by the exact
  /// intent they encode. A lost acknowledgement must replay to the identical
  /// server result instead of double-posting or double-counting, so an id
  /// survives a failure and is dropped only once the operation completed (or
  /// the server proved the id can never succeed).
  final Map<String, String> _engagementRequestIds = <String, String>{};

  /// Identity only: profile/claim refreshes do not reset a populated feed.
  String? get currentUserId {
    final uid = _auth.currentUser?.uid;
    return uid == null || uid.isEmpty ? null : uid;
  }

  /// The client's cached view of the outbound-content privilege.
  ///
  /// `setReelLike` and `createReelComment` require a verified email; reading a
  /// Reel and deleting your own comment do not. This is a presentation hint so
  /// an unverified account is told *why* it cannot post instead of meeting a
  /// dead control — the server remains the only authority, and a stale cache
  /// simply means the callable answers `failed-precondition` and the UI shows
  /// the same explanation.
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  Stream<String?> get identityChanges =>
      _auth.userChanges().map((user) => user?.uid).distinct();

  Future<T> _withIdentity<T>(
    Future<T> Function(_ReelIdentityLease identity) action, {
    ReelPublishSession? session,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Sign in before continuing with Reels.');
    final epoch = _grantEpoch;
    session?._bindIdentity(uid, epoch);
    final identity = _ReelIdentityLease(
      uid: uid,
      isCurrent: () => currentUserId == uid && _grantEpoch == epoch,
      changes: identityChanges,
      onInvalidated: () {
        if (session != null) session._identityInvalidated = true;
      },
    );
    try {
      identity.ensureCurrent();
      final result = await action(identity);
      identity.close();
      identity.ensureCurrent();
      return result;
    } finally {
      identity.close();
    }
  }

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  Future<Map<Object?, Object?>> _call(
    String name,
    Map<String, Object?> payload,
  ) async {
    final invoker = _callableInvoker;
    if (invoker != null) return invoker(name, payload);
    final result = await _functions
        .httpsCallable(name)
        .call<Map<Object?, Object?>>(payload);
    return result.data;
  }

  Future<String> publish(
    ReelPublishSession session, {
    void Function(double progress)? onProgress,
  }) => _withIdentity(
    (identity) => _publishBound(session, identity, onProgress: onProgress),
    session: session,
  );

  Future<String> _publishBound(
    ReelPublishSession session,
    _ReelIdentityLease identity, {
    void Function(double progress)? onProgress,
  }) async {
    final problem = session.plan.validate();
    if (problem != null) throw FormatException(problem);

    if (session.reelId == null || session.mediaStoragePath == null) {
      final plan = session.plan;
      final audio = plan.backingAudio;
      final reserved = await _call('reserveReelDraftV2', <String, Object?>{
        'requestId': session.requestId,
        'mediaKind': plan.media.mediaKind.name,
        'mediaContentType': plan.media.contentType,
        'mediaSize': plan.media.size,
        'durationMs': plan.media.durationMs,
        'hasBackingAudio': audio != null,
        'audioContentType': audio?.contentType,
        'audioSize': audio?.size,
        'audioDurationMs': audio?.durationMs,
        'availabilityHours': plan.availability.wireValue,
      });
      identity.ensureCurrent();
      final reservation = _ReelReservationV2.fromWire(reserved);
      if (reservation.availability != plan.availability) {
        throw const FormatException(
          'The Reel reservation availability is inconsistent.',
        );
      }
      final now = DateTime.now().toUtc();
      if (!reservation.reservationExpiresAt.isAfter(now) ||
          (reservation.contentExpiresAt != null &&
              !reservation.contentExpiresAt!.isAfter(now))) {
        throw const FormatException('The Reel reservation already expired.');
      }
      session
        ..reelId = reservation.reelId
        ..mediaStoragePath = reservation.mediaStoragePath
        ..backingAudioStoragePath = audio == null
            ? null
            : reservation.backingAudioStoragePath
        ..reservationExpiresAt = reservation.reservationExpiresAt
        ..contentExpiresAt = reservation.contentExpiresAt;
      if ((audio == null && reservation.backingAudioStoragePath != null) ||
          (audio != null && reservation.backingAudioStoragePath == null)) {
        throw const FormatException(
          'The Reel audio reservation is inconsistent.',
        );
      }
    }

    final reelId = session.reelId!;
    identity.ensureCurrent();
    if (session.mediaGeneration == null) {
      final generation = await _upload(
        storagePath: session.mediaStoragePath!,
        payload: session.plan.media,
        metadata: <String, String>{
          'ownerId': identity.uid,
          'reelId': reelId,
          'assetKind': 'media',
        },
        onProgress: onProgress == null
            ? null
            : (progress) {
                if (identity.isCurrent) onProgress(progress * .8);
              },
      );
      identity.ensureCurrent();
      session.mediaGeneration = generation;
    }

    final audio = session.plan.backingAudio;
    if (audio != null && session.backingAudioGeneration == null) {
      identity.ensureCurrent();
      final generation = await _upload(
        storagePath: session.backingAudioStoragePath!,
        payload: audio,
        metadata: <String, String>{
          'ownerId': identity.uid,
          'reelId': reelId,
          'assetKind': 'backingAudio',
        },
        onProgress: onProgress == null
            ? null
            : (progress) {
                if (identity.isCurrent) onProgress(.8 + (progress * .15));
              },
      );
      identity.ensureCurrent();
      session.backingAudioGeneration = generation;
    }

    identity.ensureCurrent();
    final finalized = await _call('finalizeReelDraftV2', <String, Object?>{
      'requestId': session.requestId,
      'reelId': reelId,
      'mediaGeneration': session.mediaGeneration,
      'backingAudioGeneration': session.backingAudioGeneration,
      'composition': session.plan.composition.toWire(),
    });
    identity.ensureCurrent();
    final result = _ReelFinalizeResultV2.fromWire(finalized);
    if (result.reelId != reelId ||
        result.availability != session.plan.availability ||
        result.contentExpiresAt != session.contentExpiresAt) {
      throw const FormatException('The Reel publish response is inconsistent.');
    }
    onProgress?.call(1);
    return reelId;
  }

  Future<String> _upload({
    required String storagePath,
    required ReelUploadPayload payload,
    required Map<String, String> metadata,
    void Function(double progress)? onProgress,
  }) async {
    final invoker = _uploadInvoker;
    if (invoker != null) {
      return invoker(
        storagePath: storagePath,
        payload: payload,
        metadata: metadata,
        onProgress: onProgress,
      );
    }
    final storage = _storage ?? FirebaseStorage.instance;
    final reference = storage.ref(storagePath);
    final task = reference.putData(
      payload.bytes,
      SettableMetadata(
        contentType: payload.contentType,
        customMetadata: metadata,
      ),
    );
    StreamSubscription<TaskSnapshot>? progressSubscription;
    if (onProgress != null) {
      progressSubscription = task.snapshotEvents.listen((snapshot) {
        final total = snapshot.totalBytes;
        if (total > 0) onProgress(snapshot.bytesTransferred / total);
      });
    }
    try {
      try {
        final snapshot = await task;
        final generation = snapshot.metadata?.generation;
        if (generation != null &&
            RegExp(r'^[0-9]{1,30}$').hasMatch(generation)) {
          return generation;
        }
      } catch (error, stackTrace) {
        // Storage can commit an object and lose only the acknowledgement. An
        // exact metadata recovery makes retry idempotent without accepting an
        // unrelated object left at the deterministic path.
        final recovered = await _recoverUpload(
          reference: reference,
          payload: payload,
          expectedMetadata: metadata,
        );
        if (recovered != null) return recovered;
        Error.throwWithStackTrace(error, stackTrace);
      }
      final recovered = await _recoverUpload(
        reference: reference,
        payload: payload,
        expectedMetadata: metadata,
      );
      if (recovered == null) {
        throw const FormatException('The uploaded Reel media is invalid.');
      }
      return recovered;
    } finally {
      await progressSubscription?.cancel();
    }
  }

  Future<String?> _recoverUpload({
    required Reference reference,
    required ReelUploadPayload payload,
    required Map<String, String> expectedMetadata,
  }) async {
    try {
      final recovered = await reference.getMetadata();
      final generation = recovered.generation;
      final custom = recovered.customMetadata ?? const <String, String>{};
      if (recovered.size != payload.size ||
          recovered.contentType != payload.contentType ||
          generation == null ||
          !RegExp(r'^[0-9]{1,30}$').hasMatch(generation) ||
          expectedMetadata.entries.any(
            (entry) => custom[entry.key] != entry.value,
          )) {
        return null;
      }
      return generation;
    } catch (_) {
      return null;
    }
  }

  Future<ReelFeedPage> fetchFeed({String? cursor, int limit = 10}) =>
      _withIdentity((identity) async {
        if (limit < 1 || limit > 20) {
          throw ArgumentError.value(
            limit,
            'limit',
            'Use a page size from 1 to 20.',
          );
        }
        final response = await _call('listReelsV2', <String, Object?>{
          'cursor': cursor,
          'limit': limit,
        });
        identity.ensureCurrent();
        final page = ReelFeedPage.fromV2Wire(response);
        final now = DateTime.now().toUtc();
        return ReelFeedPage(
          items: page.items
              .where((reel) => reel.availability.isAvailableAt(now))
              .toList(growable: false),
          nextCursor: page.nextCursor,
        );
      });

  Future<Uri> resolveMediaUri(
    String reelId, {
    ReelAssetKind asset = ReelAssetKind.media,
  }) {
    final uid = _auth.currentUser?.uid ?? '';
    final cleanId = _requiredSafeId(reelId, 'reelId');
    if (uid.isEmpty) throw StateError('Sign in before playing a Reel.');
    final key = '$uid:$cleanId:${asset.name}';
    final now = DateTime.now().toUtc();
    final cached = _grantCache[key];
    if (cached != null &&
        cached.expiresAt.isAfter(now.add(const Duration(seconds: 15)))) {
      return Future<Uri>.value(cached.uri);
    }
    return _pendingGrants.putIfAbsent(key, () async {
      final epoch = _grantEpoch;
      try {
        final response = await _call('getReelMediaAccessV2', <String, Object?>{
          'reelId': cleanId,
          'asset': asset.name,
        });
        if (_auth.currentUser?.uid != uid || epoch != _grantEpoch) {
          throw StateError('Reel media access was cleared. Try again.');
        }
        final grant = _ReelMediaGrantV2.fromWire(response);
        final checkedAt = DateTime.now().toUtc();
        if (!grant.expiresAt.isAfter(checkedAt) ||
            !grant.availability.isAvailableAt(checkedAt) ||
            (grant.availability.contentExpiresAt != null &&
                grant.expiresAt.isAfter(
                  grant.availability.contentExpiresAt!,
                ))) {
          throw const FormatException('Expired Reel media grant.');
        }
        _grantCache[key] = _CachedReelGrant(
          uri: grant.uri,
          expiresAt: grant.expiresAt,
        );
        return grant.uri;
      } finally {
        _pendingGrants.remove(key);
      }
    });
  }

  Future<void> deleteReel(String reelId, {String? requestId}) async {
    final id = _requiredSafeId(reelId, 'reelId');
    final stableRequestId = requestId == null
        ? _deleteRequestIds.putIfAbsent(id, ReelPublishSession.newRequestId)
        : _requiredSafeId(requestId, 'requestId');
    final response = await _call('deleteReel', <String, Object?>{
      'reelId': id,
      'requestId': stableRequestId,
    });
    final result = _exactWireMap(response, const <String>{
      'reelId',
      'deleted',
    }, 'Reel deletion');
    if (_requiredSafeId(result['reelId'], 'reelId') != id ||
        result['deleted'] != true) {
      throw const FormatException('Malformed Reel deletion response.');
    }
    if (_deleteRequestIds[id] == stableRequestId) {
      _deleteRequestIds.remove(id);
    }
    _grantCache.removeWhere((key, _) => key.contains(':$id:'));
  }

  bool isCurrentUserAuthor(Reel reel) =>
      currentUserId != null && currentUserId == reel.authorId;

  /// Creates an idempotent safety report through the privileged backend.
  /// Reporting intentionally remains available to signed-in users whose email
  /// is not verified yet; content-safety controls must not be gated by an
  /// outbound-content privilege.
  Future<String> reportReel(
    String reelId, {
    required String reason,
    String note = '',
    String? requestId,
  }) async {
    if (_auth.currentUser == null) {
      throw StateError('Sign in before reporting a Reel.');
    }
    final id = _requiredSafeId(reelId, 'reelId');
    final cleanReason = reason.trim();
    final cleanNote = note.trim();
    const reasons = <String>{
      'spam',
      'harassment',
      'hate',
      'sexual',
      'violence',
      'selfHarm',
      'impersonation',
      'other',
    };
    if (!reasons.contains(cleanReason)) {
      throw ArgumentError.value(reason, 'reason', 'Choose a report reason.');
    }
    if (cleanNote.length > 300) {
      throw ArgumentError.value(note, 'note', 'Use up to 300 characters.');
    }
    final response = await _call('createReelReport', <String, Object?>{
      'reelId': id,
      'requestId': requestId ?? ReelPublishSession.newRequestId(),
      'reason': cleanReason,
      'note': cleanNote,
    });
    if (response.length != 2 ||
        response['created'] is! bool ||
        !response.containsKey('reportId')) {
      throw const FormatException('Malformed Reel report response.');
    }
    return _requiredSafeId(response['reportId'], 'reportId');
  }

  // ---------------------------------------------------------------------
  // Engagement (likes and comments).
  //
  // Every entry point follows the conventions already established above:
  // `_withIdentity` binds the operation to one signed-in account and discards
  // a result that lands after an account boundary, `_call` reaches the same
  // europe-west1 callable surface, and a retry-stable requestId makes a lost
  // acknowledgement replay instead of duplicating server state.
  // ---------------------------------------------------------------------

  /// Runs one engagement callable and translates its status code into an
  /// outcome the UI can explain.
  ///
  /// Each branch corresponds to a real refusal in the deployed function. In
  /// particular `permission-denied` is the backend's single deliberate
  /// refusal envelope for "this Reel is unavailable" — it deliberately does
  /// not distinguish a block, a suspension, moderation or expiry, so this
  /// client must not invent that distinction either.
  ///
  /// [retryStableKey] is set only when this service owns the request id for
  /// the call, so a refusal that poisons that id can release it.
  Future<Map<Object?, Object?>> _engagementCall(
    String name,
    Map<String, Object?> payload, {
    String? retryStableKey,
  }) async {
    try {
      return await _call(name, payload);
    } on FirebaseFunctionsException catch (error, stackTrace) {
      final failure = _classifyEngagement(error);
      // Only a poisoned id is discarded. `already-exists` means this id is
      // already bound to a different input, and `invalid-argument` means the
      // payload will never be accepted; replaying either is pure loss. Every
      // other refusal left no ledger row, so the id stays retry-stable.
      if (retryStableKey != null &&
          (failure == ReelEngagementFailure.conflict ||
              failure == ReelEngagementFailure.invalid)) {
        _engagementRequestIds.remove(retryStableKey);
      }
      Error.throwWithStackTrace(
        ReelEngagementException(failure, cause: error),
        stackTrace,
      );
    } on FirebaseException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ReelEngagementException(
          error.code == 'no-app'
              ? ReelEngagementFailure.unavailable
              : ReelEngagementFailure.unknown,
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  static ReelEngagementFailure _classifyEngagement(
    FirebaseFunctionsException error,
  ) => switch (error.code) {
    'unauthenticated' => ReelEngagementFailure.signedOut,
    // requireActor's email-verification gate on setReelLike and
    // createReelComment, and the availability deadline on every path.
    'failed-precondition' => ReelEngagementFailure.emailUnverified,
    // consumeRateLimit: 60 likes/min, 20 comments/min, 30 deletes/10 min,
    // 60 views/min, per account.
    'resource-exhausted' => ReelEngagementFailure.rateLimited,
    // The single refusal envelope. Never branched on.
    'permission-denied' || 'not-found' => ReelEngagementFailure.unavailable,
    'already-exists' => ReelEngagementFailure.conflict,
    'invalid-argument' => ReelEngagementFailure.invalid,
    'unavailable' || 'deadline-exceeded' => ReelEngagementFailure.offline,
    _ => ReelEngagementFailure.unknown,
  };

  /// Sets this viewer's like state on [reelId].
  ///
  /// `changed: false` means the server already held the requested state — a
  /// successful no-op, not a failure. The returned `likeCount` is always the
  /// authority, so a caller that applied an optimistic toggle adopts it
  /// verbatim instead of incrementing its own copy.
  Future<ReelLikeResult> setLike(
    String reelId, {
    required bool liked,
    String? requestId,
  }) => _withIdentity((identity) async {
    final id = _requiredSafeId(reelId, 'reelId');
    final key = 'like:$id:$liked';
    final stableRequestId = requestId == null
        ? _engagementRequestIds.putIfAbsent(
            key,
            ReelPublishSession.newRequestId,
          )
        : _requiredSafeId(requestId, 'requestId');
    final response = await _engagementCall('setReelLike', <String, Object?>{
      'reelId': id,
      'liked': liked,
      'requestId': stableRequestId,
    }, retryStableKey: requestId == null ? key : null);
    identity.ensureCurrent();
    final result = ReelLikeResult.fromWire(response);
    if (result.reelId != id || result.liked != liked) {
      throw const FormatException('Malformed Reel like response.');
    }
    // Both directions are released once either completes: a stale id from an
    // earlier failed toggle must never be replayed after the opposite toggle
    // succeeded, or the replay would answer with a long-obsolete count.
    _engagementRequestIds
      ..remove('like:$id:true')
      ..remove('like:$id:false');
    return result;
  });

  /// Posts one text comment on [reelId].
  ///
  /// [text] is trimmed here so the value hashed into the server's idempotency
  /// identity is byte-identical across retries of the same attempt.
  ///
  /// Unlike a like or a comment deletion, one composition attempt has no
  /// natural key this service could derive — the same person may legitimately
  /// post the same words twice. The composer therefore owns [requestId] and
  /// holds it across retries, exactly as [reportReel] expects of its caller.
  Future<ReelCommentResult> createComment(
    String reelId, {
    required String text,
    String? requestId,
  }) => _withIdentity((identity) async {
    final id = _requiredSafeId(reelId, 'reelId');
    final body = text.trim();
    if (body.isEmpty || body.length > ReelComment.maxTextLength) {
      throw ArgumentError.value(
        text,
        'text',
        'Use 1 to ${ReelComment.maxTextLength} characters.',
      );
    }
    final response =
        await _engagementCall('createReelComment', <String, Object?>{
          'reelId': id,
          'text': body,
          'requestId': requestId == null
              ? ReelPublishSession.newRequestId()
              : _requiredSafeId(requestId, 'requestId'),
        });
    identity.ensureCurrent();
    final result = ReelCommentResult.fromWire(response);
    if (result.reelId != id) {
      throw const FormatException('Malformed Reel comment response.');
    }
    return result;
  });

  /// Removes one of this viewer's own comments. The backend refuses any other
  /// author with the same single refusal envelope; there is no moderator or
  /// report path on Reel comments yet, so this client offers neither.
  Future<ReelCommentDeletion> deleteComment(
    String reelId, {
    required String commentId,
    String? requestId,
  }) => _withIdentity((identity) async {
    final id = _requiredSafeId(reelId, 'reelId');
    final comment = _requiredSafeId(commentId, 'commentId');
    final key = 'commentDelete:$id:$comment';
    final stableRequestId = requestId == null
        ? _engagementRequestIds.putIfAbsent(
            key,
            ReelPublishSession.newRequestId,
          )
        : _requiredSafeId(requestId, 'requestId');
    final response = await _engagementCall(
      'deleteReelComment',
      <String, Object?>{
        'reelId': id,
        'commentId': comment,
        'requestId': stableRequestId,
      },
      retryStableKey: requestId == null ? key : null,
    );
    identity.ensureCurrent();
    final result = ReelCommentDeletion.fromWire(response);
    if (result.reelId != id || result.commentId != comment) {
      throw const FormatException('Malformed Reel comment deletion response.');
    }
    _engagementRequestIds.remove(key);
    return result;
  });

  /// Loads one Reel with a page of its comment thread, oldest first.
  Future<ReelView> loadView(
    String reelId, {
    int commentLimit = ReelView.maxCommentLimit,
    String? commentCursor,
  }) => _withIdentity((identity) async {
    final id = _requiredSafeId(reelId, 'reelId');
    if (commentLimit < 1 || commentLimit > ReelView.maxCommentLimit) {
      throw ArgumentError.value(
        commentLimit,
        'commentLimit',
        'Use a page size from 1 to ${ReelView.maxCommentLimit}.',
      );
    }
    // A read carries no idempotency identity, so there is no id to keep.
    final response = await _engagementCall('getReelViewV2', <String, Object?>{
      'reelId': id,
      'commentLimit': commentLimit,
      'commentCursor': commentCursor,
    });
    identity.ensureCurrent();
    final view = ReelView.fromWire(response);
    if (view.reel.id != id) {
      throw const FormatException('Malformed Reel view response.');
    }
    return view;
  });

  static void clearAllMediaAccessCaches() {
    _grantEpoch += 1;
    _grantCache.clear();
  }
}

/// Why an engagement call did not go through, in terms a viewer can act on.
///
/// Deliberately coarser than the callable's status codes: [unavailable] is the
/// backend's one refusal envelope for a Reel this viewer may not engage with,
/// and splitting it back apart in the client would rebuild exactly the oracle
/// the server refuses to be.
enum ReelEngagementFailure {
  /// The sign-in ended, or the token was rejected.
  signedOut,

  /// Liking and commenting need a verified email; reading and deleting your
  /// own comment do not.
  emailUnverified,

  /// The per-account budget for this operation is spent.
  rateLimited,

  /// This Reel cannot be engaged with. One refusal, no reason.
  unavailable,

  /// The retry-stable request id is already bound to different input.
  conflict,

  /// The payload was rejected outright.
  invalid,

  /// Transport, not policy.
  offline,

  /// Anything else, including an undeployed callable.
  unknown,
}

/// A refused engagement call, carrying the raw cause for logging only.
@immutable
class ReelEngagementException implements Exception {
  const ReelEngagementException(this.reason, {this.cause});

  final ReelEngagementFailure reason;
  final Object? cause;

  @override
  String toString() => 'ReelEngagementException(${reason.name})';
}

@immutable
class ReelLikeResult {
  const ReelLikeResult({
    required this.reelId,
    required this.liked,
    required this.changed,
    required this.likeCount,
  });

  final String reelId;
  final bool liked;

  /// False when the server already held this state. Replaying the same
  /// requestId returns the identical result, including this flag.
  final bool changed;
  final int likeCount;

  factory ReelLikeResult.fromWire(Map<Object?, Object?> raw) {
    final map = _exactWireMap(raw, const <String>{
      'reelId',
      'liked',
      'changed',
      'likeCount',
    }, 'Reel like result');
    final liked = map['liked'];
    final changed = map['changed'];
    final likeCount = map['likeCount'];
    if (liked is! bool || changed is! bool || likeCount is! int) {
      throw const FormatException('Malformed Reel like result.');
    }
    if (likeCount < 0) {
      throw const FormatException('Negative Reel like count.');
    }
    return ReelLikeResult(
      reelId: _requiredSafeId(map['reelId'], 'reelId'),
      liked: liked,
      changed: changed,
      likeCount: likeCount,
    );
  }
}

@immutable
class ReelCommentResult {
  const ReelCommentResult({
    required this.reelId,
    required this.commentId,
    required this.commentCount,
  });

  final String reelId;
  final String commentId;
  final int commentCount;

  factory ReelCommentResult.fromWire(Map<Object?, Object?> raw) {
    final map = _exactWireMap(raw, const <String>{
      'reelId',
      'commentId',
      'created',
      'commentCount',
    }, 'Reel comment result');
    final commentCount = map['commentCount'];
    if (map['created'] != true || commentCount is! int || commentCount < 1) {
      throw const FormatException('Malformed Reel comment result.');
    }
    return ReelCommentResult(
      reelId: _requiredSafeId(map['reelId'], 'reelId'),
      commentId: _requiredSafeId(map['commentId'], 'commentId'),
      commentCount: commentCount,
    );
  }
}

@immutable
class ReelCommentDeletion {
  const ReelCommentDeletion({
    required this.reelId,
    required this.commentId,
    required this.commentCount,
  });

  final String reelId;
  final String commentId;
  final int commentCount;

  factory ReelCommentDeletion.fromWire(Map<Object?, Object?> raw) {
    final map = _exactWireMap(raw, const <String>{
      'reelId',
      'commentId',
      'deleted',
      'commentCount',
    }, 'Reel comment deletion');
    final commentCount = map['commentCount'];
    if (map['deleted'] != true || commentCount is! int || commentCount < 0) {
      throw const FormatException('Malformed Reel comment deletion.');
    }
    return ReelCommentDeletion(
      reelId: _requiredSafeId(map['reelId'], 'reelId'),
      commentId: _requiredSafeId(map['commentId'], 'commentId'),
      commentCount: commentCount,
    );
  }
}

/// A bounded operation subscription, not a service-lifetime listener. Once an
/// account boundary is observed it stays invalid even if A signs back in before
/// the pending network operation resolves. Already-issued backend work remains
/// server-authorized; the client stops the next stage and discards late results.
class _ReelIdentityLease {
  _ReelIdentityLease({
    required this.uid,
    required bool Function() isCurrent,
    required Stream<String?> changes,
    required this.onInvalidated,
  }) : _isCurrent = isCurrent {
    _subscription = changes.listen((nextUid) {
      if (nextUid != uid) _invalidate();
    }, onError: (Object error, StackTrace stackTrace) => _invalidate());
  }

  final String uid;
  final bool Function() _isCurrent;
  final VoidCallback onInvalidated;
  late final StreamSubscription<String?> _subscription;
  bool _invalidated = false;
  bool _closed = false;

  bool get isCurrent {
    if (!_isCurrent()) _invalidate();
    return !_invalidated;
  }

  void _invalidate() {
    if (_invalidated) return;
    _invalidated = true;
    onInvalidated();
  }

  void ensureCurrent() {
    if (!isCurrent) {
      throw StateError('The Reel sign-in session changed. Try again.');
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    // Cancellation stops delivery synchronously. Its future is provider
    // cleanup, not an identity barrier, and can belong to another async zone
    // (including Firebase Auth's shared broadcast stream). Do not hold a
    // completed operation hostage to that cleanup. The caller still checks
    // the latched identity and current UID/epoch after cancellation.
    _subscription.cancel().ignore();
  }
}

@immutable
class _CachedReelGrant {
  const _CachedReelGrant({required this.uri, required this.expiresAt});

  final Uri uri;
  final DateTime expiresAt;
}

@immutable
class _ReelReservationV2 {
  const _ReelReservationV2({
    required this.reelId,
    required this.mediaStoragePath,
    required this.backingAudioStoragePath,
    required this.reservationExpiresAt,
    required this.availability,
    required this.contentExpiresAt,
  });

  final String reelId;
  final String mediaStoragePath;
  final String? backingAudioStoragePath;
  final DateTime reservationExpiresAt;
  final ReelAvailabilityChoice availability;
  final DateTime? contentExpiresAt;

  factory _ReelReservationV2.fromWire(Map<Object?, Object?> raw) {
    final map = _exactWireMap(raw, const <String>{
      'schemaVersion',
      'reelId',
      'mediaStoragePath',
      'backingAudioStoragePath',
      'expiresAtMillis',
      'availabilityHours',
      'contentExpiresAtMillis',
    }, 'Reel reservation');
    if (map['schemaVersion'] != 2) {
      throw const FormatException('Unsupported Reel reservation schema.');
    }
    final choice = ReelAvailabilityChoice.fromWire(map['availabilityHours']);
    final contentExpiresAt = _contentExpiry(
      choice,
      map['contentExpiresAtMillis'],
      'contentExpiresAtMillis',
    );
    final rawAudioPath = map['backingAudioStoragePath'];
    if (rawAudioPath != null && rawAudioPath is! String) {
      throw const FormatException('backingAudioStoragePath is invalid.');
    }
    return _ReelReservationV2(
      reelId: _requiredSafeId(map['reelId'], 'reelId'),
      mediaStoragePath: _requiredPath(
        map['mediaStoragePath'],
        'mediaStoragePath',
      ),
      backingAudioStoragePath: rawAudioPath == null
          ? null
          : _requiredPath(rawAudioPath, 'backingAudioStoragePath'),
      reservationExpiresAt: _positiveTimestamp(
        map['expiresAtMillis'],
        'expiresAtMillis',
      ),
      availability: choice,
      contentExpiresAt: contentExpiresAt,
    );
  }
}

@immutable
class _ReelFinalizeResultV2 {
  const _ReelFinalizeResultV2({
    required this.reelId,
    required this.availability,
    required this.contentExpiresAt,
  });

  final String reelId;
  final ReelAvailabilityChoice availability;
  final DateTime? contentExpiresAt;

  factory _ReelFinalizeResultV2.fromWire(Map<Object?, Object?> raw) {
    final map = _exactWireMap(raw, const <String>{
      'schemaVersion',
      'reelId',
      'published',
      'availabilityHours',
      'expiresAtMillis',
    }, 'Reel finalize result');
    if (map['schemaVersion'] != 2 || map['published'] != true) {
      throw const FormatException('Malformed Reel finalize result.');
    }
    final choice = ReelAvailabilityChoice.fromWire(map['availabilityHours']);
    return _ReelFinalizeResultV2(
      reelId: _requiredSafeId(map['reelId'], 'reelId'),
      availability: choice,
      contentExpiresAt: _contentExpiry(
        choice,
        map['expiresAtMillis'],
        'expiresAtMillis',
      ),
    );
  }
}

@immutable
class _ReelMediaGrantV2 {
  const _ReelMediaGrantV2({
    required this.uri,
    required this.expiresAt,
    required this.generation,
    required this.availability,
  });

  final Uri uri;
  final DateTime expiresAt;
  final String generation;
  final ReelAvailability availability;

  factory _ReelMediaGrantV2.fromWire(Map<Object?, Object?> raw) {
    final map = _exactWireMap(raw, const <String>{
      'schemaVersion',
      'url',
      'expiresAtMillis',
      'generation',
      'availabilityHours',
      'contentExpiresAtMillis',
    }, 'Reel media grant');
    if (map['schemaVersion'] != 2) {
      throw const FormatException('Unsupported Reel media grant schema.');
    }
    final rawUrl = map['url'];
    final rawGeneration = map['generation'];
    if (rawUrl is! String ||
        rawGeneration is! String ||
        !RegExp(r'^[0-9]{1,30}$').hasMatch(rawGeneration)) {
      throw const FormatException('Malformed Reel media grant.');
    }
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'storage.googleapis.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort) {
      throw const FormatException('Unsafe Reel media grant.');
    }
    final choice = ReelAvailabilityChoice.fromWire(map['availabilityHours']);
    final contentExpiresAt = _contentExpiry(
      choice,
      map['contentExpiresAtMillis'],
      'contentExpiresAtMillis',
    );
    return _ReelMediaGrantV2(
      uri: uri,
      expiresAt: _positiveTimestamp(map['expiresAtMillis'], 'expiresAtMillis'),
      generation: rawGeneration,
      availability: ReelAvailability(
        schemaVersion: 2,
        choice: choice,
        contentExpiresAt: contentExpiresAt,
      ),
    );
  }
}

Map<String, Object?> _exactWireMap(
  Map<Object?, Object?> raw,
  Set<String> expected,
  String label,
) {
  final map = <String, Object?>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is! String) throw FormatException('$label has an invalid key.');
    map[key] = entry.value;
  }
  if (map.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(map.keys.toSet()).isNotEmpty) {
    throw FormatException('$label has an unsupported shape.');
  }
  return map;
}

DateTime _positiveTimestamp(Object? raw, String label) {
  if (raw is! int || raw <= 0) {
    throw FormatException('$label must be a positive integer.');
  }
  return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
}

DateTime? _contentExpiry(
  ReelAvailabilityChoice choice,
  Object? raw,
  String label,
) {
  if (choice.isPermanent) {
    if (raw != null) throw FormatException('$label must be null.');
    return null;
  }
  return _positiveTimestamp(raw, label);
}

String _requiredSafeId(Object? value, String label) {
  if (value is! String || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value)) {
    throw FormatException('$label is invalid.');
  }
  return value;
}

String _requiredPath(Object? value, String label) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 1024 ||
      value.startsWith('/') ||
      value.endsWith('/') ||
      value.contains('..') ||
      value.contains('\\')) {
    throw FormatException('$label is invalid.');
  }
  return value;
}
