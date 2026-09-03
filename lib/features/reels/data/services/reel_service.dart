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
  });

  final ReelUploadPayload media;
  final ReelUploadPayload? backingAudio;
  final ReelComposition composition;

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
    : requestId = requestId ?? _newRequestId();

  final ReelDraftPlan plan;
  final String requestId;
  String? reelId;
  String? mediaStoragePath;
  String? backingAudioStoragePath;
  String? mediaGeneration;
  String? backingAudioGeneration;

  static String _newRequestId() {
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
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in before publishing a Reel.');
    final problem = session.plan.validate();
    if (problem != null) throw FormatException(problem);

    if (session.reelId == null || session.mediaStoragePath == null) {
      final plan = session.plan;
      final audio = plan.backingAudio;
      final reserved = await _call('reserveReelDraft', <String, Object?>{
        'requestId': session.requestId,
        'mediaKind': plan.media.mediaKind.name,
        'mediaContentType': plan.media.contentType,
        'mediaSize': plan.media.size,
        'durationMs': plan.media.durationMs,
        'hasBackingAudio': audio != null,
        'audioContentType': audio?.contentType,
        'audioSize': audio?.size,
        'audioDurationMs': audio?.durationMs,
      });
      session
        ..reelId = _requiredSafeId(reserved['reelId'], 'reelId')
        ..mediaStoragePath = _requiredPath(
          reserved['mediaStoragePath'],
          'mediaStoragePath',
        )
        ..backingAudioStoragePath = audio == null
            ? null
            : _requiredPath(
                reserved['backingAudioStoragePath'],
                'backingAudioStoragePath',
              );
    }

    final reelId = session.reelId!;
    session.mediaGeneration ??= await _upload(
      storagePath: session.mediaStoragePath!,
      payload: session.plan.media,
      metadata: <String, String>{
        'ownerId': user.uid,
        'reelId': reelId,
        'assetKind': 'media',
      },
      onProgress: onProgress == null
          ? null
          : (progress) => onProgress(progress * .8),
    );

    final audio = session.plan.backingAudio;
    if (audio != null) {
      session.backingAudioGeneration ??= await _upload(
        storagePath: session.backingAudioStoragePath!,
        payload: audio,
        metadata: <String, String>{
          'ownerId': user.uid,
          'reelId': reelId,
          'assetKind': 'backingAudio',
        },
        onProgress: onProgress == null
            ? null
            : (progress) => onProgress(.8 + (progress * .15)),
      );
    }

    final finalized = await _call('finalizeReelDraft', <String, Object?>{
      'requestId': session.requestId,
      'reelId': reelId,
      'mediaGeneration': session.mediaGeneration,
      'backingAudioGeneration': session.backingAudioGeneration,
      'composition': session.plan.composition.toWire(),
    });
    final finalizedId = _requiredSafeId(finalized['reelId'], 'reelId');
    if (finalizedId != reelId) {
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

  Future<ReelFeedPage> fetchFeed({String? cursor, int limit = 10}) async {
    if (_auth.currentUser == null) {
      throw StateError('Sign in before loading Reels.');
    }
    if (limit < 1 || limit > 20) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Use a page size from 1 to 20.',
      );
    }
    final response = await _call('listReels', <String, Object?>{
      'cursor': cursor,
      'limit': limit,
    });
    return ReelFeedPage.fromWire(response);
  }

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
        final response = await _call('getReelMediaAccess', <String, Object?>{
          'reelId': cleanId,
          'asset': asset.name,
        });
        if (_auth.currentUser?.uid != uid || epoch != _grantEpoch) {
          throw StateError('Reel media access was cleared. Try again.');
        }
        final rawUrl = response['url'];
        final rawExpiry = response['expiresAtMillis'];
        final generation = response['generation'];
        if (response['schemaVersion'] != 1 ||
            rawUrl is! String ||
            rawExpiry is! int ||
            generation is! String ||
            !RegExp(r'^[0-9]{1,30}$').hasMatch(generation)) {
          throw const FormatException('Malformed Reel media grant.');
        }
        final uri = Uri.tryParse(rawUrl);
        final expiry = DateTime.fromMillisecondsSinceEpoch(
          rawExpiry,
          isUtc: true,
        );
        if (uri == null ||
            uri.scheme != 'https' ||
            uri.host != 'storage.googleapis.com' ||
            uri.userInfo.isNotEmpty ||
            uri.hasPort ||
            !expiry.isAfter(DateTime.now().toUtc())) {
          throw const FormatException('Unsafe Reel media grant.');
        }
        _grantCache[key] = _CachedReelGrant(uri: uri, expiresAt: expiry);
        return uri;
      } finally {
        _pendingGrants.remove(key);
      }
    });
  }

  Future<void> deleteReel(String reelId, {String? requestId}) async {
    final id = _requiredSafeId(reelId, 'reelId');
    await _call('deleteReel', <String, Object?>{
      'reelId': id,
      'requestId': requestId ?? ReelPublishSession._newRequestId(),
    });
    _grantCache.removeWhere((key, _) => key.contains(':$id:'));
  }

  bool isCurrentUserAuthor(Reel reel) =>
      _auth.currentUser?.uid == reel.authorId;

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
      'requestId': requestId ?? ReelPublishSession._newRequestId(),
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

  static void clearAllMediaAccessCaches() {
    _grantEpoch += 1;
    _grantCache.clear();
  }
}

@immutable
class _CachedReelGrant {
  const _CachedReelGrant({required this.uri, required this.expiresAt});

  final Uri uri;
  final DateTime expiresAt;
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
