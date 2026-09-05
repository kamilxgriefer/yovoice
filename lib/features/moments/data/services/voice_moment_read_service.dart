import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'package:yovoice/features/moments/data/models/voice_moment.dart';

typedef VoiceMomentFeedInvoker =
    Future<Map<Object?, Object?>> Function(Map<String, Object?> request);
typedef VoiceMomentViewInvoker =
    Future<Map<Object?, Object?>> Function(Map<String, Object?> request);

enum VoiceMomentFeedSort { recent, popular }

enum VoiceMomentFeedMode { discover, following }

/// Strict Build 20 read client for the server-owned Voice Moment projection.
///
/// No Firestore fallback belongs here: Build 19 retains its legacy direct-read
/// boundary, while Build 20 must fail closed if the v2 callable is unavailable.
class VoiceMomentReadService {
  VoiceMomentReadService({
    FirebaseFunctions? functions,
    VoiceMomentFeedInvoker? feedInvoker,
    VoiceMomentViewInvoker? viewInvoker,
    this.callableTimeout = const Duration(seconds: 20),
  }) : _functionsOverride = functions,
       _feedInvoker = feedInvoker,
       _viewInvoker = viewInvoker;

  final FirebaseFunctions? _functionsOverride;
  final VoiceMomentFeedInvoker? _feedInvoker;
  final VoiceMomentViewInvoker? _viewInvoker;
  final Duration callableTimeout;

  FirebaseFunctions? get _functions =>
      _functionsOverride ??
      (() {
        try {
          return FirebaseFunctions.instanceFor(region: 'europe-west1');
        } on FirebaseException catch (error) {
          if (error.code == 'no-app') return null;
          rethrow;
        }
      })();

  Future<VoiceMomentFeedPageV2> loadFeedPage({
    int limit = 10,
    String? cursor,
    VoiceMomentFeedSort sort = VoiceMomentFeedSort.recent,
    VoiceMomentFeedMode mode = VoiceMomentFeedMode.discover,
  }) async {
    if (limit < 1 || limit > 10) {
      throw RangeError.range(limit, 1, 10, 'limit');
    }
    final cleanCursor = _optionalCursor(cursor);
    if (mode == VoiceMomentFeedMode.following &&
        sort != VoiceMomentFeedSort.recent) {
      throw ArgumentError.value(
        sort,
        'sort',
        'following mode supports only recent order',
      );
    }
    final payload = <String, Object?>{
      'limit': limit,
      'sortMode': sort.name,
      'feedMode': mode.name,
    };
    if (cleanCursor != null) payload['cursor'] = cleanCursor;
    final response = await _withTimeoutReplay(
      () => _feedInvoker != null
          ? _feedInvoker(payload)
          : _call('getVoiceMomentsFeedV2', payload),
    );
    return VoiceMomentFeedPageV2.parse(response);
  }

  Future<VoiceMomentViewV2> loadView({
    required String momentId,
    int commentLimit = 7,
    int reactionLimit = 3,
    String? commentCursor,
  }) async {
    final cleanMomentId = _safeId(momentId, 'momentId');
    if (commentLimit < 1 || commentLimit > 7) {
      throw RangeError.range(commentLimit, 1, 7, 'commentLimit');
    }
    if (reactionLimit < 1 || reactionLimit > 3) {
      throw RangeError.range(reactionLimit, 1, 3, 'reactionLimit');
    }
    final cleanCursor = _optionalCursor(commentCursor);
    final payload = <String, Object?>{
      'momentId': cleanMomentId,
      'commentLimit': commentLimit,
      'reactionLimit': reactionLimit,
    };
    if (cleanCursor != null) payload['commentCursor'] = cleanCursor;
    final response = await _withTimeoutReplay(
      () => _viewInvoker != null
          ? _viewInvoker(payload)
          : _call('getVoiceMomentViewV2', payload),
    );
    return VoiceMomentViewV2.parse(response);
  }

  Future<Map<Object?, Object?>> _call(
    String name,
    Map<String, Object?> payload,
  ) async {
    final functions = _functions;
    if (functions == null) {
      throw StateError('The YO Voice Moment read service is unavailable.');
    }
    final result = await functions
        .httpsCallable(name)
        .call<Map<Object?, Object?>>(payload);
    return result.data;
  }

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
    throw StateError('The Voice Moment read did not complete.');
  }
}

@immutable
class VoiceMomentFeedPageV2 {
  const VoiceMomentFeedPageV2({
    required this.moments,
    required this.scannedCount,
    required this.hasMore,
    required this.nextCursor,
  });

  final List<VoiceMoment> moments;
  final int scannedCount;
  final bool hasMore;
  final String? nextCursor;

  factory VoiceMomentFeedPageV2.parse(Object? value) {
    final data = _exactMap(value, const <String>{
      'schemaVersion',
      'moments',
      'scannedCount',
      'hasMore',
      'nextCursor',
    }, 'Voice Moment feed');
    _expect(data['schemaVersion'] == 2, 'Unsupported Voice Moment feed.');
    final rawMoments = data['moments'];
    _expect(rawMoments is List, 'Malformed Voice Moment feed items.');
    final scannedCount = _boundedInt(
      data['scannedCount'],
      'scannedCount',
      min: 0,
      max: 10,
    );
    final rawHasMore = data['hasMore'];
    if (rawHasMore is! bool) {
      _malformed('Malformed Voice Moment feed boundary.');
    }
    final hasMore = rawHasMore;
    final nextCursor = _nullableCursor(data['nextCursor']);
    _expect(
      (hasMore && nextCursor != null) || (!hasMore && nextCursor == null),
      'Inconsistent Voice Moment feed boundary.',
    );
    final moments = <VoiceMoment>[
      for (final item in rawMoments as List<Object?>)
        _parseMomentProjection(item),
    ];
    _expect(
      moments.length <= scannedCount,
      'Malformed Voice Moment feed size.',
    );
    _expect(
      moments.map((moment) => moment.id).toSet().length == moments.length,
      'Duplicate Voice Moment projection.',
    );
    return VoiceMomentFeedPageV2(
      moments: List<VoiceMoment>.unmodifiable(moments),
      scannedCount: scannedCount,
      hasMore: hasMore,
      nextCursor: nextCursor,
    );
  }
}

@immutable
class VoiceMomentViewV2 {
  const VoiceMomentViewV2({
    required this.moment,
    required this.comments,
    required this.commentsTruncated,
    required this.nextCommentCursor,
    required this.topReactions,
  });

  final VoiceMoment moment;
  final List<MomentComment> comments;
  final bool commentsTruncated;
  final String? nextCommentCursor;
  final List<MomentReactor> topReactions;

  factory VoiceMomentViewV2.parse(Object? value) {
    final data = _exactMap(value, const <String>{
      'schemaVersion',
      'moment',
      'comments',
      'commentsTruncated',
      'nextCommentCursor',
      'topReactions',
    }, 'Voice Moment detail');
    _expect(data['schemaVersion'] == 2, 'Unsupported Voice Moment detail.');
    final rawComments = data['comments'];
    final rawReactions = data['topReactions'];
    _expect(rawComments is List, 'Malformed Voice Moment comments.');
    _expect(rawReactions is List, 'Malformed Voice Moment reactions.');
    final rawTruncated = data['commentsTruncated'];
    if (rawTruncated is! bool) {
      _malformed('Malformed Voice Moment comment boundary.');
    }
    final truncated = rawTruncated;
    final nextCursor = _nullableCursor(data['nextCommentCursor']);
    _expect(
      (truncated && nextCursor != null) || (!truncated && nextCursor == null),
      'Inconsistent Voice Moment comment boundary.',
    );
    final comments = <MomentComment>[
      for (final item in rawComments as List<Object?>)
        MomentComment.parse(item),
    ];
    final reactions = <MomentReactor>[
      for (final item in rawReactions as List<Object?>)
        MomentReactor.parse(item),
    ];
    _expect(comments.length <= 7, 'Too many Voice Moment comments.');
    _expect(reactions.length <= 3, 'Too many Voice Moment reactions.');
    return VoiceMomentViewV2(
      moment: _parseMomentProjection(data['moment']),
      comments: List<MomentComment>.unmodifiable(comments),
      commentsTruncated: truncated,
      nextCommentCursor: nextCursor,
      topReactions: List<MomentReactor>.unmodifiable(reactions),
    );
  }
}

@immutable
class MomentReactor {
  const MomentReactor({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;

  factory MomentReactor.parse(Object? value) {
    final data = _exactMap(value, const <String>{
      'userId',
      'displayName',
      'photoUrl',
    }, 'Voice Moment reaction');
    _expect(data['photoUrl'] == null, 'Durable reaction artwork is forbidden.');
    return MomentReactor(
      uid: _opaqueUid(data['userId'], 'reaction userId'),
      displayName: _trimmedString(
        data['displayName'],
        'reaction displayName',
        max: 80,
      ),
      photoUrl: null,
    );
  }
}

@immutable
class MomentComment {
  const MomentComment({
    required this.id,
    required this.type,
    required this.authorId,
    required this.authorName,
    required this.authorPhotoUrl,
    required this.text,
    required this.durationSeconds,
    required this.createdAt,
    this.reportReceipt,
  });

  final String id;
  final String type;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String text;
  final int durationSeconds;
  final DateTime createdAt;
  final String? reportReceipt;

  bool get isVoice => type == 'voice';

  factory MomentComment.parse(Object? value) {
    final data = _exactMap(value, const <String>{
      'schemaVersion',
      'commentId',
      'type',
      'authorId',
      'authorName',
      'authorPhotoUrl',
      'text',
      'durationSeconds',
      'createdAtMillis',
      'reportReceipt',
    }, 'Voice Moment comment');
    _expect(data['schemaVersion'] == 2, 'Unsupported Voice Moment comment.');
    _expect(
      data['authorPhotoUrl'] == null,
      'Durable comment artwork is forbidden.',
    );
    final rawType = data['type'];
    if (rawType != 'text' && rawType != 'voice') {
      _malformed('Malformed comment type.');
    }
    final type = rawType as String;
    final duration = data['durationSeconds'];
    if (type == 'text') {
      _expect(duration == null, 'Malformed text comment duration.');
    } else {
      _boundedInt(duration, 'durationSeconds', min: 1, max: 60);
    }
    final rawText = data['text'];
    if (rawText is! String) {
      _malformed('Malformed Voice Moment comment text.');
    }
    final text = rawText;
    _expect(
      (type == 'text' && text.isNotEmpty && text.length <= 1000) ||
          (type == 'voice' && text.length <= 140),
      'Malformed Voice Moment comment text.',
    );
    return MomentComment(
      id: _safeId(data['commentId'], 'commentId'),
      type: type,
      authorId: _opaqueUid(data['authorId'], 'comment authorId'),
      authorName: _trimmedString(
        data['authorName'],
        'comment authorName',
        max: 80,
      ),
      authorPhotoUrl: null,
      text: text,
      durationSeconds: duration is int ? duration : 0,
      createdAt: _dateFromMillis(data['createdAtMillis'], 'createdAtMillis'),
      reportReceipt: _reportReceipt(data['reportReceipt']),
    );
  }
}

VoiceMoment _parseMomentProjection(Object? value) {
  final data = _exactMap(value, const <String>{
    'schemaVersion',
    'momentId',
    'authorId',
    'authorName',
    'authorPhotoUrl',
    'caption',
    'durationSeconds',
    'likeCount',
    'commentCount',
    'callerLiked',
    'createdAtMillis',
    'publishedAtMillis',
    'expiresAtMillis',
    'reportReceipt',
  }, 'Voice Moment projection');
  _expect(data['schemaVersion'] == 2, 'Unsupported Voice Moment projection.');
  _expect(
    data['authorPhotoUrl'] == null,
    'Durable profile artwork is forbidden.',
  );
  final rawCaption = data['caption'];
  if (rawCaption is! String || rawCaption.length > 280) {
    _malformed('Malformed Voice Moment caption.');
  }
  final caption = rawCaption;
  final rawCallerLiked = data['callerLiked'];
  if (rawCallerLiked is! bool) {
    _malformed('Malformed Voice Moment like state.');
  }
  final callerLiked = rawCallerLiked;
  final createdAt = _dateFromMillis(data['createdAtMillis'], 'createdAtMillis');
  final publishedAt = _dateFromMillis(
    data['publishedAtMillis'],
    'publishedAtMillis',
  );
  _expect(
    !publishedAt.isBefore(createdAt),
    'Malformed Voice Moment publication time.',
  );
  final rawExpiry = data['expiresAtMillis'];
  final expiresAt = rawExpiry == null
      ? null
      : _dateFromMillis(rawExpiry, 'expiresAtMillis');
  _expect(
    expiresAt == null || expiresAt.isAfter(createdAt),
    'Malformed Voice Moment expiry.',
  );
  return VoiceMoment(
    id: _safeId(data['momentId'], 'momentId'),
    authorId: _opaqueUid(data['authorId'], 'authorId'),
    authorName: _trimmedString(data['authorName'], 'authorName', max: 80),
    authorPhotoUrl: null,
    caption: caption,
    audioUrl: null,
    durationSeconds: _boundedInt(
      data['durationSeconds'],
      'durationSeconds',
      min: 1,
      max: 60,
    ),
    likeCount: _boundedInt(data['likeCount'], 'likeCount', min: 0),
    commentCount: _boundedInt(data['commentCount'], 'commentCount', min: 0),
    isPublished: true,
    createdAt: createdAt,
    expiresAt: expiresAt,
    schemaVersion: 2,
    status: 'published',
    isDeleted: false,
    callerLiked: callerLiked,
    hasAuthorizedMedia: true,
    reportReceipt: _reportReceipt(data['reportReceipt']),
  );
}

String _reportReceipt(Object? value) {
  if (value is! String ||
      value.length != 43 ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    _malformed('Malformed Voice Moment report receipt.');
  }
  return value;
}

Map<String, Object?> _exactMap(
  Object? value,
  Set<String> expected,
  String label,
) {
  _expect(value is Map, '$label must be an object.');
  final source = value as Map<Object?, Object?>;
  _expect(
    source.keys.every((key) => key is String),
    '$label has invalid keys.',
  );
  final data = <String, Object?>{
    for (final entry in source.entries) entry.key as String: entry.value,
  };
  _expect(
    data.length == expected.length && data.keys.toSet().containsAll(expected),
    '$label schema does not match Build 20.',
  );
  return data;
}

int _boundedInt(
  Object? value,
  String label, {
  required int min,
  int max = 0x7fffffff,
}) {
  _expect(value is int && value >= min && value <= max, 'Malformed $label.');
  return value as int;
}

DateTime _dateFromMillis(Object? value, String label) =>
    DateTime.fromMillisecondsSinceEpoch(
      _boundedInt(value, label, min: 0, max: 253402300799999),
      isUtc: true,
    );

String _trimmedString(Object? value, String label, {required int max}) {
  _expect(
    value is String &&
        value.isNotEmpty &&
        value.length <= max &&
        value.trim() == value,
    'Malformed $label.',
  );
  return value as String;
}

String _safeId(Object? value, String label) {
  _expect(
    value is String && RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value),
    'Malformed $label.',
  );
  return value as String;
}

/// Firebase Authentication UIDs are intentionally opaque. They may contain
/// characters such as `:` that are not valid in our own document/request IDs;
/// the only client-side projection boundary is non-empty, bounded, slash-free
/// and free of ASCII control characters. The server remains authoritative.
String _opaqueUid(Object? value, String label) {
  _expect(
    value is String &&
        value.isNotEmpty &&
        value.length <= 128 &&
        !value.contains('/') &&
        !RegExp(r'[\x00-\x1F\x7F]').hasMatch(value),
    'Malformed $label.',
  );
  return value as String;
}

String? _nullableCursor(Object? value) {
  if (value == null) return null;
  _expect(
    value is String &&
        value.length <= 256 &&
        RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value),
    'Malformed Voice Moment cursor.',
  );
  return value as String;
}

String? _optionalCursor(String? value) {
  if (value == null) return null;
  final cursor = value.trim();
  _expect(
    cursor.isNotEmpty &&
        cursor == value &&
        cursor.length <= 256 &&
        RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(cursor),
    'Malformed Voice Moment cursor.',
  );
  return cursor;
}

Never _malformed(String message) => throw FormatException(message);

void _expect(bool condition, String message) {
  if (!condition) _malformed(message);
}
