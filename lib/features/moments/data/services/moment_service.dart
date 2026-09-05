import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:yovoice/core/security/ephemeral_media_access_registry.dart';
import 'package:yovoice/features/moments/data/models/moment_availability.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';

export 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart'
    show MomentComment, MomentReactor, VoiceMomentViewV2;

typedef MomentMediaAccessInvoker =
    Future<Map<Object?, Object?>> Function(Map<String, Object?> request);

class MomentService {
  MomentService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
    FirebaseFunctions? functions,
    MomentMediaAccessInvoker? mediaAccessInvoker,
    VoiceMomentReadService? readService,
    this.callableTimeout = const Duration(seconds: 20),
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _functionsOverride = functions,
       _mediaAccessInvoker = mediaAccessInvoker,
       _readService =
           readService ??
           VoiceMomentReadService(
             functions: functions,
             callableTimeout: callableTimeout,
           );

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final FirebaseFunctions? _functionsOverride;
  final MomentMediaAccessInvoker? _mediaAccessInvoker;
  final VoiceMomentReadService _readService;
  final Duration callableTimeout;
  // Playback surfaces create short-lived MomentService instances. Keep the
  // bearer-grant cache process-wide so logout can invalidate every surface in
  // one operation instead of leaving an unreachable per-instance URL alive.
  static final Map<String, _CachedMomentMediaAccess> _mediaAccessCache = {};
  static int _mediaAccessCacheEpoch = 0;
  final Map<String, Future<Uri>> _pendingMediaAccess = {};

  /// One logical publish operation per recording. Keeping this state in the
  /// service makes the screen's "try publishing again" a real retry: the
  /// same server reservation and request id are reused instead of consuming a
  /// second quota slot and leaving another abandoned draft behind.
  final Map<RecordedAudio, _PendingMomentPublish> _pendingMomentPublishes =
      Map<RecordedAudio, _PendingMomentPublish>.identity();

  /// Forgets the retry identity when the author explicitly abandons a take.
  ///
  /// This deliberately does not delete Storage. A finalize response can be
  /// lost after the server has published the Moment/reply, and client deletion
  /// cannot be made atomic with that Firestore commit. Unfinished uploads are
  /// removed by the server's bounded abandoned-draft schedulers instead.
  void abandonPendingPublish(RecordedAudio audio) {
    _pendingMomentPublishes.remove(audio);
  }

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

  CollectionReference<Map<String, dynamic>> get _moments =>
      _firestore.collection('voiceMoments');

  String _newRequestId() {
    final random = Random.secure();
    final randomPart = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}-$randomPart';
  }

  bool _isCallableUnavailable(Object error) {
    if (error is FirebaseException && error.code == 'no-app') {
      return true;
    }
    return error is FirebaseFunctionsException && error.code == 'unimplemented';
  }

  /// Resolves a canonical Moment object to a short-lived, server-authorized
  /// media grant. Firestore download-token URLs are deliberately ignored:
  /// the callable rechecks publication, expiry, account restrictions and
  /// both block directions on every fresh grant.
  Future<Uri> resolveMediaUri({required String momentId, String? commentId}) {
    final uid = _auth.currentUser?.uid ?? '';
    final cleanMomentId = momentId.trim();
    final cleanCommentId = commentId?.trim();
    if (uid.isEmpty) {
      throw StateError('You must be signed in to play a Voice Moment.');
    }
    if (cleanMomentId.isEmpty ||
        cleanMomentId.contains('/') ||
        (cleanCommentId != null &&
            (cleanCommentId.isEmpty || cleanCommentId.contains('/')))) {
      throw const FormatException('The Voice Moment media id is invalid.');
    }
    final cacheKey = '$uid:$cleanMomentId:${cleanCommentId ?? ''}';
    final cacheEpoch = _mediaAccessCacheEpoch;
    final now = DateTime.now().toUtc();
    final cached = _mediaAccessCache[cacheKey];
    if (cached != null &&
        cached.expiresAt.isAfter(now.add(const Duration(seconds: 15)))) {
      return Future<Uri>.value(cached.uri);
    }
    return _pendingMediaAccess.putIfAbsent(cacheKey, () async {
      try {
        final payload = <String, Object?>{
          'momentId': cleanMomentId,
          'commentId': ?cleanCommentId,
        };
        final response = await _withTimeoutReplay(
          () => _mediaAccessInvoker != null
              ? _mediaAccessInvoker(payload)
              : _requestMediaAccess(payload),
        );
        if (_auth.currentUser?.uid != uid) {
          throw StateError(
            'Your account changed before media access was granted.',
          );
        }
        if (_mediaAccessCacheEpoch != cacheEpoch) {
          throw StateError('Voice Moment media access was cleared. Try again.');
        }
        final schemaVersion = response['schemaVersion'];
        final rawUrl = response['url'];
        final rawExpiry = response['expiresAtMillis'];
        final generation = response['mediaGeneration'];
        final contentType = response['mediaContentType'];
        final mediaSize = response['mediaSize'];
        if (schemaVersion != 1 ||
            rawUrl is! String ||
            rawUrl.length > 4096 ||
            rawExpiry is! int ||
            generation is! String ||
            !RegExp(r'^[0-9]{1,30}$').hasMatch(generation) ||
            !const <String>{
              'audio/mp4',
              'audio/m4a',
              'audio/x-m4a',
            }.contains(contentType) ||
            mediaSize is! int ||
            mediaSize < 512 ||
            mediaSize > 12 * 1024 * 1024) {
          throw const FormatException('Malformed private media grant.');
        }
        final uri = Uri.tryParse(rawUrl);
        final expiresAt = DateTime.fromMillisecondsSinceEpoch(
          rawExpiry,
          isUtc: true,
        );
        if (uri == null ||
            uri.scheme != 'https' ||
            uri.host != 'storage.googleapis.com' ||
            uri.hasPort ||
            uri.userInfo.isNotEmpty ||
            !expiresAt.isAfter(DateTime.now().toUtc())) {
          throw const FormatException('Unsafe private media grant.');
        }
        _mediaAccessCache[cacheKey] = _CachedMomentMediaAccess(
          uri: uri,
          expiresAt: expiresAt,
        );
        return uri;
      } finally {
        _pendingMediaAccess.remove(cacheKey);
      }
    });
  }

  Future<Map<Object?, Object?>> _requestMediaAccess(
    Map<String, Object?> payload,
  ) async {
    final functions = _functions;
    if (functions == null) {
      throw StateError('The YO Voice media service is unavailable.');
    }
    final result = await functions
        .httpsCallable('getVoiceMomentMediaAccess')
        .call<Map<Object?, Object?>>(payload);
    return result.data;
  }

  /// A timed-out callable may already have committed on the server. Retrying
  /// once is safe because every publish step carries the same requestId and
  /// every media grant is read-only. The bound prevents a platform channel or
  /// lost response from leaving the publish/player spinner running forever.
  Future<T> _withTimeoutReplay<T>(Future<T> Function() operation) async {
    if (callableTimeout <= Duration.zero) {
      throw ArgumentError.value(
        callableTimeout,
        'callableTimeout',
        'must be positive',
      );
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await operation().timeout(callableTimeout);
      } on TimeoutException catch (error, stackTrace) {
        if (attempt == 1) Error.throwWithStackTrace(error, stackTrace);
      }
    }
    throw StateError('The Voice Moment request did not complete.');
  }

  /// Invalidates every in-memory bearer grant, including a response already
  /// in flight. The logout coordinator calls this once; the static cache is
  /// shared by every MomentService instance used by playback surfaces.
  static void clearAllMediaAccessCaches() {
    _mediaAccessCacheEpoch += 1;
    _mediaAccessCache.clear();
    EphemeralMediaAccessRegistry.clearAll();
  }

  /// Backwards-compatible instance entry point for existing coordinators.
  void clearMediaAccessCache() => clearAllMediaAccessCaches();

  Stream<List<VoiceMoment>> watchPublishedMoments({int limit = 30}) {
    final bounded = limit.clamp(1, 10);
    return Stream<List<VoiceMoment>>.fromFuture(
      _readService.loadFeedPage(limit: bounded).then((page) => page.moments),
    );
  }

  /// One server-authorized snapshot of a Moment.
  ///
  /// For a surface that was handed a Moment fetched some time ago and
  /// then lets you act on it — the player sheet, where you can like it
  /// and comment on it. Without this the sheet showed the counters as
  /// they were when the tile was tapped, so your own like did not appear
  /// until the surface was rebuilt from somewhere else.
  ///
  /// This deliberately does not claim to be a foreign Firestore listener.
  /// Surfaces that remain mounted refresh after their own mutations or when
  /// they become visible again.
  Stream<VoiceMoment> watchMoment(String momentId) {
    return Stream<VoiceMoment>.fromFuture(
      loadMomentView(momentId).then((view) => view.moment),
    );
  }

  /// Like [watchMoment], but the callable's normalized unavailable result
  /// emits `null` instead of an error.
  ///
  /// For the detail screen, which must tell "this Moment is live" apart
  /// from "this Moment was deleted while you were looking at it" — the
  /// filtered stream above cannot express the second, and a surface that
  /// keeps rendering a deleted Moment forever is showing something that
  /// no longer exists.
  Stream<VoiceMoment?> watchMomentOrMissing(String momentId) {
    return Stream<VoiceMoment?>.fromFuture(
      loadMomentView(momentId)
          .then<VoiceMoment?>((view) => view.moment)
          .onError((Object error, StackTrace stackTrace) {
            if (error is FirebaseFunctionsException &&
                error.code == 'permission-denied') {
              return null;
            }
            Error.throwWithStackTrace(error, stackTrace);
          }),
    );
  }

  Future<VoiceMomentViewV2> loadMomentView(
    String momentId, {
    String? commentCursor,
    int commentLimit = 7,
    int reactionLimit = 3,
  }) => _readService.loadView(
    momentId: momentId,
    commentCursor: commentCursor,
    commentLimit: commentLimit,
    reactionLimit: reactionLimit,
  );

  /// Up to [limit] uids that liked this Moment, most recent first.
  ///
  /// Returned by the same server-owned v2 detail projection as the Moment.
  /// The server resolves only identities this viewer may see and retains the
  /// aggregate count for the hidden remainder; Build 20 never reads a foreign
  /// like subcollection or public-profile root directly.
  Future<List<String>> likerIds(String momentId, {int limit = 5}) async {
    final view = await loadMomentView(
      momentId,
      reactionLimit: limit.clamp(1, 3),
    );
    return view.topReactions
        .map((reactor) => reactor.uid)
        .toList(growable: false);
  }

  /// The identities behind [likerIds], best-effort.
  ///
  /// A private/blocked/restricted/deleted reactor is omitted by the callable,
  /// never invented: the like itself stays counted in the "+N" remainder the
  /// caller derives from `likeCount`.
  Future<List<MomentReactor>> topReactions(
    String momentId, {
    int limit = 5,
  }) async {
    final view = await loadMomentView(
      momentId,
      reactionLimit: limit.clamp(1, 3),
    );
    return view.topReactions;
  }

  /// The signed-in user's own Voice Moments, published and unpublished
  /// (drafts still uploading or that failed to finish publishing).
  Stream<List<VoiceMoment>> watchMyMoments() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(const <VoiceMoment>[]);

    return _moments.where('authorId', isEqualTo: user.uid).snapshots().map((
      snapshot,
    ) {
      final moments = snapshot.docs
          .map(VoiceMoment.fromFirestore)
          .toList(growable: false);
      moments.sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
      return moments;
    });
  }

  /// The comment thread under one Moment, oldest first — the same
  /// documents `MomentCommentsScreen` reads, exposed as a typed stream so
  /// the desktop detail panel can render the thread inline without
  /// duplicating the Firestore path or the field names.
  Stream<List<MomentComment>> watchComments(String momentId, {int limit = 80}) {
    return Stream<List<MomentComment>>.fromFuture(
      loadMomentView(
        momentId,
        commentLimit: limit.clamp(1, 7),
      ).then((view) => view.comments),
    );
  }

  /// Publishes a finished recording.
  ///
  /// [audio] is the platform seam: native passes a temporary file, web
  /// passes the native Blob the browser produced. Everything below — the draft
  /// reservation, the object metadata the Storage rules check, the
  /// finalize call, and the server-required failure path — is identical
  /// either way.
  /// [availability] names how long the Moment stays live — any whole-hour
  /// value from 24 through 720 (24h default), or permanent. It travels to
  /// `finalizeMomentDraft` as
  /// `availabilityHours`; the server validates it and stamps (or, for
  /// permanent, omits) `expiresAt`. The default sends nothing, which the
  /// server reads as 24 hours — today's behaviour, byte for byte.
  /// Ignored for voice replies, which have no expiry of their own.
  Future<String> publishRecordedMoment({
    required RecordedAudio audio,
    required int durationSeconds,
    required String caption,
    String? replyToMomentId,
    MomentAvailability availability = MomentAvailability.fallback,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to publish a Voice Moment.');
    }

    // The Storage rules fail an upload that violates these bounds, and a
    // rejected upload leaves a draft that never finalizes. Refuse here,
    // where the reason can still be explained.
    final unusable = validateRecordedAudio(audio);
    if (unusable != null) throw unusable;

    if (durationSeconds < 1 || durationSeconds > 60) {
      throw ArgumentError.value(
        durationSeconds,
        'durationSeconds',
        'Voice Moments must be between 1 and 60 seconds.',
      );
    }

    final normalizedCaption = caption.trim().isEmpty
        ? 'Voice Moment'
        : caption.trim();
    final trimmedReplyToMomentId = replyToMomentId?.trim();
    final normalizedReplyToMomentId =
        trimmedReplyToMomentId == null || trimmedReplyToMomentId.isEmpty
        ? null
        : trimmedReplyToMomentId;

    // Availability belongs only to root Moments. Normalize it before pinning
    // the retry identity so changing an ignored reply-only argument cannot
    // make an otherwise identical voice-reply retry look like new content.
    final pendingAvailability = normalizedReplyToMomentId == null
        ? availability
        : MomentAvailability.fallback;
    final existingPending = _pendingMomentPublishes[audio];
    if (existingPending != null &&
        !existingPending.matches(
          caption: normalizedCaption,
          durationSeconds: durationSeconds,
          replyToMomentId: normalizedReplyToMomentId,
          availability: pendingAvailability,
        )) {
      throw StateError(
        'Publishing already started with a different caption, duration, '
        'availability, or reply target. Restore the original details to '
        'retry this recording, or record again to publish the new version.',
      );
    }

    final pending = _pendingMomentPublishes.putIfAbsent(
      audio,
      () => _PendingMomentPublish(
        requestId: _newRequestId(),
        caption: normalizedCaption,
        durationSeconds: durationSeconds,
        replyToMomentId: normalizedReplyToMomentId,
        availability: pendingAvailability,
      ),
    );

    if (normalizedReplyToMomentId != null) {
      return _publishVoiceReply(
        parentMomentId: normalizedReplyToMomentId,
        audio: audio,
        durationSeconds: durationSeconds,
        caption: normalizedCaption,
        authorId: user.uid,
        pending: pending,
      );
    }

    try {
      final functions = _functions;
      if (functions == null) {
        throw FirebaseFunctionsException(
          code: 'no-app',
          message: 'Cloud Functions unavailable.',
        );
      }
      if (pending.momentId == null || pending.storagePath == null) {
        final reserve = functions.httpsCallable('reserveMomentDraft');
        final reserved = await _withTimeoutReplay(
          () => reserve.call<Map<Object?, Object?>>({
            'caption': normalizedCaption,
            'durationSeconds': durationSeconds,
            'requestId': pending.requestId,
          }),
        );
        pending
          ..momentId = reserved.data['momentId'] as String?
          ..storagePath = reserved.data['storagePath'] as String?;
      }

      final momentId = pending.momentId;
      final storagePath = pending.storagePath;
      if (momentId == null ||
          momentId.isEmpty ||
          storagePath == null ||
          storagePath.isEmpty) {
        throw StateError('Malformed server draft reservation for moment.');
      }
      final storageReference = _storage.ref(storagePath);

      if (pending.objectGeneration == null) {
        try {
          pending.objectGeneration = await audio.uploadTo(
            storageReference,
            SettableMetadata(
              contentType: audio.contentType,
              customMetadata: {'authorId': user.uid, 'momentId': momentId},
            ),
          );
        } catch (_) {
          // A mobile connection can drop after Storage commits the object but
          // before the client receives the upload response. Recovering the
          // generation turns that ambiguous failure into a safe finalize;
          // the server still validates size, MIME, metadata and ownership.
          pending.objectGeneration = await _uploadedGeneration(
            storageReference,
          );
          if (pending.objectGeneration == null) rethrow;
        }
      }

      final objectGeneration = pending.objectGeneration;
      if (objectGeneration == null || objectGeneration.isEmpty) {
        throw StateError('The upload did not return a valid generation.');
      }

      final finalize = functions.httpsCallable('finalizeMomentDraft');
      await _withTimeoutReplay(
        () => finalize.call<Map<Object?, Object?>>({
          'momentId': momentId,
          'objectGeneration': objectGeneration,
          'requestId': pending.requestId,
          // Additive and omitted for the default: an absent field means 24
          // hours server-side, so the default publish stays byte-identical
          // to every pre-availability client.
          if (!availability.isServerDefault)
            'availabilityHours': availability.wireValue,
        }),
      );

      _pendingMomentPublishes.remove(audio);
      return momentId;
    } catch (error) {
      if (!_isCallableUnavailable(error)) {
        rethrow;
      }
    }

    // NO LEGACY FALLBACK ANY MORE — a loud refusal instead, deliberately.
    //
    // The direct-write fallback predates the story-expiry contract. Under
    // it, only finalizeMomentDraft can stamp `expiresAt` (the create rule
    // BANS the field on client writes, so a forged expiry is impossible),
    // which means a fallback-published Moment would carry none. Under the
    // amended availability contract a missing expiresAt means PERMANENT —
    // so the fallback would silently grant every offline publish a
    // forever lifetime the author never chose, bypassing both the
    // validation and the server's active-Moment cap accounting. Publishing
    // with the wrong contract while reporting success is strictly worse
    // than failing with the truth. The recording itself is retained by
    // the pending-publish map, so a retry when the server is reachable
    // loses nothing.
    throw StateError(
      'Publishing needs the YO Voice server right now and it could not be '
      'reached. Your recording is kept — try again in a moment.',
    );
  }

  Future<String?> _uploadedGeneration(Reference reference) async {
    try {
      final metadata = await reference.getMetadata();
      final generation = metadata.generation?.trim();
      return generation == null || generation.isEmpty ? null : generation;
    } catch (_) {
      return null;
    }
  }

  Future<String> _publishVoiceReply({
    required String parentMomentId,
    required RecordedAudio audio,
    required int durationSeconds,
    required String caption,
    required String authorId,
    required _PendingMomentPublish pending,
  }) async {
    try {
      final functions = _functions;
      if (functions == null) {
        throw FirebaseFunctionsException(
          code: 'no-app',
          message: 'Cloud Functions unavailable.',
        );
      }
      if (pending.commentId == null || pending.storagePath == null) {
        final reserve = functions.httpsCallable('reserveVoiceCommentDraft');
        final reserved = await _withTimeoutReplay(
          () => reserve.call<Map<Object?, Object?>>({
            'durationSeconds': durationSeconds,
            'momentId': parentMomentId,
            'text': caption,
            'requestId': pending.requestId,
          }),
        );
        pending
          ..commentId = reserved.data['commentId'] as String?
          ..storagePath = reserved.data['storagePath'] as String?;
      }

      final commentId = pending.commentId;
      final storagePath = pending.storagePath;
      if (commentId == null ||
          commentId.isEmpty ||
          storagePath == null ||
          storagePath.isEmpty) {
        throw StateError('Malformed server voice-reply reservation.');
      }
      final storageReference = _storage.ref(storagePath);

      if (pending.objectGeneration == null) {
        try {
          pending.objectGeneration = await audio.uploadTo(
            storageReference,
            SettableMetadata(
              contentType: audio.contentType,
              customMetadata: {
                'authorId': authorId,
                'momentId': parentMomentId,
                'commentId': commentId,
              },
            ),
          );
        } catch (_) {
          // As for root Moments, an upload response can be lost after Storage
          // committed the object. Recovering its generation makes the next
          // step idempotent instead of uploading a second object.
          pending.objectGeneration = await _uploadedGeneration(
            storageReference,
          );
          if (pending.objectGeneration == null) rethrow;
        }
      }

      final objectGeneration = pending.objectGeneration;
      if (objectGeneration == null || objectGeneration.isEmpty) {
        throw StateError('The upload did not return a valid generation.');
      }

      final finalize = functions.httpsCallable('finalizeVoiceCommentDraft');
      // From this point a thrown transport error is ambiguous: the server may
      // already have atomically created the comment and its replay ledger.
      // Never delete the media after an attempted finalize. Retrying the same
      // recording reuses this request id, reservation and generation, so the
      // callable safely replays instead of creating a duplicate reply.
      await _withTimeoutReplay(
        () => finalize.call<Map<Object?, Object?>>({
          'momentId': parentMomentId,
          'commentId': commentId,
          'objectGeneration': objectGeneration,
          'requestId': pending.requestId,
        }),
      );

      _pendingMomentPublishes.remove(audio);
      return commentId;
    } catch (error) {
      if (!_isCallableUnavailable(error)) {
        rethrow;
      }
    }

    throw StateError(
      'Posting a voice reply needs the YO Voice server right now and it '
      'could not be reached. Your recording is kept — try again in a moment.',
    );
  }

  Future<String> createTextComment({
    required String momentId,
    required String text,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to comment on a Voice Moment.');
    }

    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      return '';
    }

    final requestId = _newRequestId();
    try {
      final functions = _functions;
      if (functions == null) {
        throw FirebaseFunctionsException(
          code: 'no-app',
          message: 'Cloud Functions unavailable.',
        );
      }
      final callable = functions.httpsCallable('createMomentComment');
      final response = await callable.call<Map<Object?, Object?>>({
        'momentId': momentId,
        'text': trimmedText,
        'requestId': requestId,
      });

      final data = response.data;
      final commentId = data['commentId'];
      if (commentId == null || commentId is! String || commentId.isEmpty) {
        throw StateError('Malformed server response for comment creation.');
      }
      return commentId;
    } catch (error) {
      if (!_isCallableUnavailable(error)) {
        rethrow;
      }
    }

    throw StateError(
      'Commenting needs the YO Voice server right now and it could not be '
      'reached. Your comment was not posted — try again in a moment.',
    );
  }

  Future<void> deleteMoment(VoiceMoment moment) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to delete a Voice Moment.');
    }
    if (moment.authorId != user.uid) {
      throw StateError('You can only delete your own Voice Moments.');
    }

    // THE CALLABLE, NEVER A CLIENT-SIDE SWEEP. The previous version batch
    // deleted the comments and likes subcollections directly — but the
    // deployed rules only let each COMMENT AUTHOR delete their own comment
    // and each LIKER their own like, so deleting any Moment somebody else
    // had engaged with failed permission-denied halfway through the batch.
    // The delete then broke on exactly the Moments that matter — and under
    // the availability amendment it is the ONLY exit for a permanent
    // Moment. The deployed `deleteMoment` callable performs the canonical
    // cleanup server-side (children, media, counters, audit) with the same
    // author-only authorization enforced where it cannot be bypassed.
    final functions = _functions;
    if (functions == null) {
      throw StateError(
        'Deleting needs the YO Voice server right now and it could not be '
        'reached. Try again in a moment.',
      );
    }
    final callable = functions.httpsCallable('deleteMoment');
    await callable.call<Map<Object?, Object?>>({
      'momentId': moment.id,
      'requestId': _newRequestId(),
    });
  }
}

class _PendingMomentPublish {
  _PendingMomentPublish({
    required this.requestId,
    required this.caption,
    required this.durationSeconds,
    required this.replyToMomentId,
    required this.availability,
  });

  final String requestId;
  final String caption;
  final int durationSeconds;
  final String? replyToMomentId;
  final MomentAvailability availability;
  String? momentId;
  String? commentId;
  String? storagePath;
  String? objectGeneration;

  bool matches({
    required String caption,
    required int durationSeconds,
    required String? replyToMomentId,
    required MomentAvailability availability,
  }) =>
      this.caption == caption &&
      this.durationSeconds == durationSeconds &&
      this.replyToMomentId == replyToMomentId &&
      this.availability == availability;
}

class _CachedMomentMediaAccess {
  const _CachedMomentMediaAccess({required this.uri, required this.expiresAt});

  final Uri uri;
  final DateTime expiresAt;
}
